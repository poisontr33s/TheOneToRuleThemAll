"""Host-side checks only. These never certify WoW rendering or addon behavior."""

import base64
import ctypes
import ctypes.util
import hashlib
import http.client
import json
from pathlib import Path
import struct
import tempfile
import threading
import unittest
from unittest.mock import patch
import zlib

import lab
import windows


class WindowFixture:
    """Transport fixture, not an implementation of the WoW API."""
    def __init__(self):
        self.info = {"hwnd": 123, "pid": 456, "width": 20, "height": 10,
                     "client_x": 0, "client_y": 0}
        self.actions = []

    def describe(self):
        return self.info.copy()

    def capture(self):
        return windows._png(20, 10, b"\x11\x22\x33\xff" * 200)

    def click(self, x, y):
        self.actions.append((x, y))
        return {"sent": "click"}

    def command(self, name):
        self.actions.append(name)
        return {"sent": name}


class InstallTests(unittest.TestCase):
    def setUp(self):
        closed = patch("lab.wow_running", return_value=False)
        closed.start()
        self.addCleanup(closed.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.client = self.root / "_retail_"
        self.client.mkdir()
        (self.client / "Wow.exe").write_bytes(b"fixture")
        self.main = self.root / "source" / lab.MAIN
        self.probe = self.root / "source" / lab.PROBE
        for source in (self.main, self.probe):
            source.mkdir(parents=True)
            (source / (source.name + ".toc")).write_text("## Interface: 120105\n")
        (self.main / "Core.lua").write_bytes(b"-- untouched\r\nlocal x = 'ae\xc3\xb8'\n")
        (self.probe / "ClientTest.lua").write_bytes(b"-- client probe\n")
        self.state = self.root / "state"

    def install(self):
        return lab.install_addons(self.client, self.state, self.main, self.probe)

    def test_installs_exact_source_and_keeps_old_folders(self):
        old = self.client / "Interface" / "AddOns" / lab.MAIN
        old.mkdir(parents=True)
        (old / "previous.txt").write_text("old build")
        manifest = self.install()
        self.assertEqual((old / "Core.lua").read_bytes(), (self.main / "Core.lua").read_bytes())
        self.assertEqual((Path(manifest["backup"]) / lab.MAIN / "previous.txt").read_text(), "old build")
        self.assertEqual(lab.verify_install(self.client, manifest), [])
        (self.client / "Interface" / "AddOns" / lab.PROBE / "ClientTest.lua").unlink()
        self.assertTrue(lab.verify_install(self.client, manifest))

    def test_failed_manifest_write_restores_both_originals(self):
        addons = self.client / "Interface" / "AddOns"
        for name in (lab.MAIN, lab.PROBE):
            (addons / name).mkdir(parents=True)
            (addons / name / "original.txt").write_text(name)
        self.state.write_text("not a directory")
        with self.assertRaises(OSError):
            self.install()
        for name in (lab.MAIN, lab.PROBE):
            self.assertEqual((addons / name / "original.txt").read_text(), name)
        self.assertFalse(list(addons.glob(".tor-lab-*")))

    def test_manifest_rejects_empty_traversal_and_links(self):
        manifest = self.install()
        self.assertTrue(lab.verify_install(self.client, {**manifest, "files": {}}))
        (self.client / "Interface" / "outside.txt").write_bytes(b"outside")
        bad = {**manifest, "files": {**manifest["files"], "../outside.txt": hashlib.sha256(b"outside").hexdigest()}}
        self.assertTrue(lab.verify_install(self.client, bad))
        target = self.client / "Interface" / "AddOns" / lab.MAIN / "Core.lua"
        target.unlink()
        try:
            target.symlink_to(self.main / "Core.lua")
        except OSError:
            self.skipTest("Symlinks unavailable on this host")
        self.assertTrue(lab.verify_install(self.client, manifest))

    def test_saved_report_requires_current_deployment(self):
        manifest = self.install()
        directory = self.client / "WTF" / "Account" / "TEST" / "Realm" / "Character" / "SavedVariables"
        directory.mkdir(parents=True)
        file = directory / (lab.PROBE + ".lua")
        report = {"schema": 1, "loaded": True, "phase": "prepared", "deployment_id": "old",
                  "source_sha256": manifest["source_sha256"], "text": "Æøå\n\"quoted\""}
        def save():
            encoded = base64.b64encode(json.dumps(report, ensure_ascii=False).encode()).decode()
            file.write_text(lab.REPORT_VARIABLE + ' = "' + encoded + '"\n', encoding="utf-8")
        save()
        self.assertFalse(lab.read_reports(self.client, manifest)["reports"])
        report["deployment_id"] = manifest["deployment_id"]
        save()
        self.assertEqual(lab.read_reports(self.client, manifest)["reports"][0]["report"], report)
        file.write_text(lab.REPORT_VARIABLE + ' = os.execute("must never execute")\n')
        with self.assertRaises(ValueError):
            lab.decode_report(file)


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.backend = WindowFixture()
        self.lab = lab.Lab(self.backend, Path("/unused"), {}, token="private-test-token")
        self.server = lab.ThreadingHTTPServer(("127.0.0.1", 0), lab.handler_for(self.lab))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop)
        self.origin = "http://127.0.0.1:" + str(self.server.server_port)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def post(self, path, data, origin=None, token=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=2)
        try:
            connection.request("POST", "/private-test-token/" + path, json.dumps(data), headers={
                "Content-Type": "application/json", "Origin": self.origin if origin is None else origin,
                "X-Lab-Token": "private-test-token" if token is None else token})
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def test_origin_token_and_command_allowlist(self):
        for origin, token in (("https://other.example", None), (None, "wrong")):
            self.assertEqual(self.post("action", {"action": "tor"}, origin, token)[0], 400)
        self.assertEqual(self.post("action", {"action": "shell"})[0], 400)
        self.assertEqual(self.post("action", {"action": []})[0], 400)
        self.assertFalse(self.backend.actions)
        self.assertEqual(self.post("action", {"action": "tor"})[0], 200)
        self.assertEqual(self.backend.actions, ["tor"])

    def test_capture_id_matches_image_and_stale_clicks_are_refused(self):
        status, headers, image = self.post("capture", {})
        self.assertEqual(status, 200)
        self.assertTrue(image.startswith(b"\x89PNG"))
        first = headers["X-Capture-ID"]
        second = self.post("capture", {})[1]["X-Capture-ID"]
        self.assertNotEqual(first, second)
        self.assertEqual(self.post("action", {"action": "click", "x": 1, "y": 1, "capture_id": first})[0], 400)
        self.backend.info["client_x"] = 10
        self.assertEqual(self.post("action", {"action": "click", "x": 1, "y": 1, "capture_id": second})[0], 400)
        fresh = self.post("capture", {})[1]["X-Capture-ID"]
        self.assertEqual(self.post("action", {"action": "click", "x": 20, "y": 1, "capture_id": fresh})[0], 400)
        self.assertEqual(self.post("action", {"action": "click", "x": 2, "y": 1, "capture_id": fresh})[0], 200)
        self.assertEqual(self.backend.actions, [(2, 1)])
        self.assertEqual(self.post("action", {"action": "click", "x": 2, "y": 1, "capture_id": fresh})[0], 400)


class FormatTests(unittest.TestCase):
    def test_screenshot_encoder_preserves_pixels_and_png_checksums(self):
        png = windows._png(2, 1, b"\x00\x00\xff\xff\x00\xff\x00\xff")
        position, pixels = 8, b""
        while position < len(png):
            size = struct.unpack(">I", png[position:position + 4])[0]
            kind = png[position + 4:position + 8]
            data = png[position + 8:position + 8 + size]
            checksum = struct.unpack(">I", png[position + 8 + size:position + 12 + size])[0]
            self.assertEqual(checksum, zlib.crc32(kind + data))
            if kind == b"IDAT":
                pixels += data
            position += 12 + size
        self.assertEqual(zlib.decompress(pixels), b"\x00\xff\x00\x00\x00\xff\x00")
        with self.assertRaises(RuntimeError):
            windows._png(1, 1, b"\0" * 4)

    def test_companion_lua_syntax_only(self):
        library = ctypes.util.find_library("lua5.4")
        if not library:
            self.skipTest("Lua compiler unavailable; this is not a client test")
        lua = ctypes.CDLL(library)
        lua.luaL_newstate.restype = ctypes.c_void_p
        lua.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
        lua.luaL_loadfilex.restype = ctypes.c_int
        lua.lua_close.argtypes = [ctypes.c_void_p]
        state = lua.luaL_newstate()
        try:
            file = lab.HERE / "addon" / lab.PROBE / "ClientTest.lua"
            self.assertEqual(lua.luaL_loadfilex(state, str(file).encode(), None), 0)
        finally:
            lua.lua_close(state)


if __name__ == "__main__":
    unittest.main()
