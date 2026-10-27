#!/usr/bin/env python3
"""A local, real-client test desk. No emulated WoW APIs or remote shell."""

import argparse
import base64
import csv
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit
import webbrowser


HERE = Path(__file__).resolve().parent
MAIN = "TheOneToRuleThemAll"
PROBE = MAIN + "_ClientTest"
REPORT_VARIABLE = "TheOneToRuleThemAllClientTestReport"
COMMANDS = {"tor", "guide", "test", "reload"}
MAX_REPORT_BYTES = 2 * 1024 * 1024


def client_directory(path):
    path = Path(path).expanduser().resolve()
    for folder in (path, path / "_retail_", path / "_ptr_"):
        executable = "WowT.exe" if folder.name.lower() == "_ptr_" else "Wow.exe"
        if folder.name.lower() in {"_retail_", "_ptr_"} and (folder / executable).is_file():
            return folder
    raise ValueError("Choose the World of Warcraft folder containing _retail_/Wow.exe or _ptr_/WowT.exe.")


def find_client():
    candidates = []
    if os.name == "nt":
        import winreg
        for key in (r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft",
                    r"SOFTWARE\Blizzard Entertainment\World of Warcraft"):
            try:
                with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, key) as handle:
                    candidates.append(Path(winreg.QueryValueEx(handle, "InstallPath")[0]))
            except OSError:
                pass
    for variable in ("ProgramFiles(x86)", "ProgramFiles"):
        if os.environ.get(variable):
            candidates.append(Path(os.environ[variable]) / "World of Warcraft")
    for candidate in candidates:
        try:
            return client_directory(candidate)
        except ValueError:
            pass
    return None


def source_files(folder):
    files = {}
    for file in sorted(folder.rglob("*")):
        relative = file.relative_to(folder)
        if "validation" in relative.parts or any(part.startswith(".") for part in relative.parts):
            continue
        if file.is_file() and file.suffix.lower() in {".lua", ".toc", ".txt"}:
            if file.is_symlink() or not file.resolve().is_relative_to(folder.resolve()):
                raise ValueError("Linked addon source files are not supported.")
            files[relative.as_posix()] = file.read_bytes()
    if folder.name + ".toc" not in files:
        raise ValueError(f"Missing {folder.name}.toc in {folder}")
    return files


def source_digest(files):
    # Hash names and bytes with explicit lengths; whitespace stays significant.
    digest = hashlib.sha256()
    for name, data in sorted(files.items()):
        encoded = name.encode("utf-8")
        digest.update(len(encoded).to_bytes(8, "big"))
        digest.update(encoded)
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)
    return digest.hexdigest()


def no_links(path, boundary):
    current = path
    while current != boundary:
        if current.is_symlink() or (hasattr(current, "is_junction") and current.is_junction()):
            raise ValueError(f"Refusing to install through a link: {current}")
        if current.parent == current:
            raise ValueError("Installation path is outside the selected client.")
        current = current.parent


def install_addons(client, state_dir, main_source, probe_source):
    main_files, probe_files = source_files(main_source), source_files(probe_source)
    digest = source_digest(main_files)
    deployment_id = secrets.token_hex(16)
    header = ('TheOneToRuleThemAllClientTestDeployment = { id = "' + deployment_id
              + '", source_sha256 = "' + digest + '" }\n').encode("ascii")
    probe_files["ClientTest.lua"] = header + probe_files["ClientTest.lua"]
    addons = client / "Interface" / "AddOns"
    no_links(addons, client)
    addons.mkdir(parents=True, exist_ok=True)
    backup_root = client / "WTF" / "TORClientLabBackups" / deployment_id
    no_links(backup_root, client)
    staged, installed, moved = {}, [], []
    try:
        for name, files in ((MAIN, main_files), (PROBE, probe_files)):
            target = addons / name
            no_links(target, client)
            staging = addons / (".tor-lab-" + deployment_id + "-" + name)
            staging.mkdir()
            staged[name] = staging
            for relative, data in files.items():
                output = staging / relative
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(data)
                if output.read_bytes() != data:
                    raise OSError("Written addon bytes did not match the source.")
        for name in (MAIN, PROBE):
            target = addons / name
            if target.exists():
                backup_root.mkdir(parents=True, exist_ok=True)
                target.rename(backup_root / name)
                moved.append(name)
            staged[name].rename(target)
            installed.append(name)
        manifest = {"schema": 1, "deployment_id": deployment_id, "source_sha256": digest,
                    "installed_at": time.time(), "client": str(client),
                    "backup": str(backup_root) if moved else None,
                    "files": {addon + "/" + name: hashlib.sha256(data).hexdigest()
                              for addon, files in ((MAIN, main_files), (PROBE, probe_files))
                              for name, data in files.items()}}
        state_dir.mkdir(parents=True, exist_ok=True)
        temporary = state_dir / "deployment.tmp"
        temporary.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        temporary.replace(state_dir / "deployment.json")
        return manifest
    except Exception:
        # If either installation fails, put both original addon folders back.
        for name in reversed(installed):
            shutil.rmtree(addons / name)
        for name in reversed(moved):
            (backup_root / name).rename(addons / name)
        raise
    finally:
        for staging in staged.values():
            if staging.exists():
                shutil.rmtree(staging)


def verify_install(client, manifest):
    errors = []
    files = manifest.get("files")
    required = {MAIN + "/" + MAIN + ".toc", PROBE + "/" + PROBE + ".toc", PROBE + "/ClientTest.lua"}
    if (manifest.get("schema") != 1 or not isinstance(files, dict) or not required <= files.keys()
            or not re.fullmatch(r"[a-f0-9]{32}", str(manifest.get("deployment_id", "")))
            or not re.fullmatch(r"[a-f0-9]{64}", str(manifest.get("source_sha256", "")))):
        return ["Missing or invalid deployment manifest. Install the lab build again."]
    if str(client) != manifest.get("client"):
        return ["This deployment belongs to a different WoW installation."]
    for relative, expected in files.items():
        parts = Path(relative).parts
        if (not parts or parts[0] not in {MAIN, PROBE} or ".." in parts
                or Path(relative).is_absolute() or not re.fullmatch(r"[a-f0-9]{64}", str(expected))):
            return ["Invalid deployment file entry."]
        file = client / "Interface" / "AddOns" / relative
        root = client / "Interface" / "AddOns"
        try:
            no_links(file, client)
        except ValueError:
            return ["Linked deployment files are not accepted."]
        if not file.resolve().is_relative_to(root.resolve()):
            return ["Deployment file is outside AddOns."]
        if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != expected:
            errors.append("Source changed: " + relative)
    return errors


def decode_report(path):
    if path.stat().st_size > MAX_REPORT_BYTES:
        raise ValueError("Report is too large.")
    text = path.read_text(encoding="utf-8-sig")
    match = re.search(r'^' + REPORT_VARIABLE + r'\s*=\s*"([A-Za-z0-9+/=]+)"\s*$', text, re.MULTILINE)
    if not match:
        raise ValueError("No saved client report yet; use Reload in the test panel.")
    report = json.loads(base64.b64decode(match.group(1), validate=True).decode("utf-8"))
    if not isinstance(report, dict) or report.get("schema") != 1 or report.get("loaded") is not True:
        raise ValueError("Unsupported client report.")
    return report


def read_reports(client, manifest):
    errors = verify_install(client, manifest)
    if errors:
        raise ValueError("The installed source no longer matches this test: " + "; ".join(errors))
    current, previous, unreadable = [], 0, 0
    root = client / "WTF" / "Account"
    for file in root.glob("*/*/*/SavedVariables/" + PROBE + ".lua"):
        try:
            report = decode_report(file)
            if (report.get("deployment_id") != manifest.get("deployment_id")
                    or report.get("source_sha256") != manifest.get("source_sha256")):
                previous += 1
                continue
            current.append({"saved_at": file.stat().st_mtime, "report": report})
        except (OSError, ValueError, UnicodeError):
            unreadable += 1
    return {"reports": sorted(current, key=lambda x: x["saved_at"], reverse=True),
            "previous_deployments": previous, "unreadable": unreadable,
            "note": "Saved observations only. Reload or logout flushes the game's report to disk."}


class Lab:
    def __init__(self, backend, client, manifest, token=None):
        self.backend, self.client, self.manifest = backend, client, manifest
        self.token = token or secrets.token_urlsafe(32)
        self.lock = threading.Lock()
        self.last_capture = None

    def capture(self):
        before = self.backend.describe()
        png = self.backend.capture()
        after = self.backend.describe()
        keys = ("hwnd", "pid", "width", "height", "client_x", "client_y")
        if any(before.get(key) != after.get(key) for key in keys):
            raise RuntimeError("WoW moved while capturing. Take a new screenshot.")
        self.last_capture = {**after, "taken_at": time.monotonic(), "id": secrets.token_hex(8)}
        return png

    def action(self, request):
        action = request.get("action")
        if not isinstance(action, str):
            raise ValueError("An action name is required.")
        if action == "click":
            capture = self.last_capture
            if (not capture or request.get("capture_id") != capture["id"]
                    or time.monotonic() - capture["taken_at"] > 30):
                raise ValueError("Take a fresh screenshot before clicking.")
            now = self.backend.describe()
            for key in ("hwnd", "pid", "width", "height", "client_x", "client_y"):
                if now.get(key) != capture.get(key):
                    raise ValueError("WoW changed since the screenshot. Capture it again.")
            x, y = request.get("x"), request.get("y")
            if type(x) is not int or type(y) is not int or not (0 <= x < now["width"] and 0 <= y < now["height"]):
                raise ValueError("Click must be inside the current WoW screenshot.")
            self.last_capture = None
            return self.backend.click(x, y)
        if action in COMMANDS:
            self.last_capture = None
            return self.backend.command(action)
        if action == "escape":
            self.last_capture = None
            return self.backend.escape()
        raise ValueError("That action is not available in this test desk.")


def handler_for(lab):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # The URL contains a capability token; never write it to logs.

        def reply(self, status, body, content_type="application/json", extra=None):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("X-Frame-Options", "DENY")
            for key, value in (extra or {}).items():
                self.send_header(key, value)
            self.end_headers()
            self.wfile.write(body)

        def json(self, status, value):
            self.reply(status, json.dumps(value).encode("utf-8"))

        def route(self):
            expected_host = "127.0.0.1:" + str(self.server.server_port)
            if self.headers.get("Host") != expected_host:
                raise ValueError("Local host only.")
            path = urlsplit(self.path).path
            parts = path.strip("/").split("/")
            if not parts or not parts[0].isascii() or not hmac.compare_digest(parts[0], lab.token):
                raise ValueError("Open this desk using its private session link.")
            return "/".join(parts[1:])

        def do_GET(self):
            try:
                route = self.route()
                if route == "":
                    nonce = secrets.token_urlsafe(24)
                    html = (HERE / "desk.html").read_text(encoding="utf-8").replace("NONCE", nonce)
                    policy = ("default-src 'none'; script-src 'nonce-" + nonce
                              + "'; style-src 'nonce-" + nonce
                              + "'; img-src 'self' blob:; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'")
                    self.reply(200, html.encode("utf-8"), "text/html; charset=utf-8", {"Content-Security-Policy": policy})
                elif route == "state":
                    with lab.lock:
                        state = lab.backend.describe()
                        self.json(200, {"window": state, "capture": lab.last_capture,
                                        "source_errors": verify_install(lab.client, lab.manifest)})
                elif route == "reports":
                    self.json(200, read_reports(lab.client, lab.manifest))
                else:
                    self.json(404, {"error": "Not found."})
            except (ValueError, OSError, RuntimeError) as error:
                self.json(400, {"error": str(error)})

        def do_POST(self):
            try:
                route = self.route()
                origin = "http://127.0.0.1:" + str(self.server.server_port)
                if (self.headers.get("Origin") != origin
                        or not hmac.compare_digest(self.headers.get("X-Lab-Token", ""), lab.token)):
                    raise ValueError("Use the local test desk to send actions.")
                if self.headers.get("Content-Type") != "application/json":
                    raise ValueError("JSON requests only.")
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 4096:
                    raise ValueError("Invalid request size.")
                request = json.loads(self.rfile.read(length))
                if not isinstance(request, dict):
                    raise ValueError("Expected a JSON object.")
                with lab.lock:
                    if route == "capture":
                        png = lab.capture()
                        self.reply(200, png, "image/png", {"X-Capture-ID": lab.last_capture["id"]})
                    elif route == "action":
                        self.json(200, lab.action(request))
                    else:
                        self.json(404, {"error": "Not found."})
            except (ValueError, OSError, RuntimeError) as error:
                self.json(400, {"error": str(error)})
    return Handler


def wow_running():
    """Check processes, including minimized clients, before replacing any files."""
    executable = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32" / "tasklist.exe"
    try:
        result = subprocess.run([str(executable), "/FO", "CSV", "/NH"], capture_output=True,
                                text=True, check=True, timeout=15,
                                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    except (OSError, subprocess.SubprocessError) as error:
        raise RuntimeError("Could not establish whether WoW is closed. No addon files were changed.") from error
    return any(row and row[0].lower() in {"wow.exe", "wowt.exe"} for row in csv.reader(result.stdout.splitlines()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wow-path", type=Path, help="World of Warcraft, _retail_, or _ptr_ folder")
    parser.add_argument("--install", action="store_true", help="Install this source build; back up existing addon folders")
    parser.add_argument("--port", type=int, default=0, help="Local port (default: pick an available port)")
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("This bridge needs Windows with the real WoW client. It does not simulate a client.")
    import windows
    client = client_directory(args.wow_path) if args.wow_path else find_client()
    if not client:
        typed = input("WoW installation folder: ").strip().strip('"')
        client = client_directory(typed)
    executable = client / ("WowT.exe" if client.name.lower() == "_ptr_" else "Wow.exe")
    windows.configure(str(executable))
    state_dir = HERE / "state"
    if args.install:
        if wow_running():
            raise ValueError("Close WoW before installing the test build, then run Start-Lab again.")
        main_source = HERE / "payload" / MAIN
        if not main_source.is_dir():
            main_source = HERE.parents[1] / MAIN
        manifest = install_addons(client, state_dir, main_source, HERE / "addon" / PROBE)
        print("Installed the source build and its client test. Existing addon folders were backed up; saved settings were kept.")
    else:
        manifest = json.loads((state_dir / "deployment.json").read_text(encoding="utf-8"))
    errors = verify_install(client, manifest)
    if errors:
        raise ValueError("\n".join(errors))
    lab = Lab(windows, client, manifest)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(lab))
    server.daemon_threads = True
    url = "http://127.0.0.1:" + str(server.server_port) + "/" + lab.token + "/"
    print("Start WoW, enable both addons, and log in on the intended test character.")
    print("Test desk: " + url)
    print("Keep this window open. Ctrl+C stops access.")
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        print("Cannot start the test desk: " + str(error))
        raise SystemExit(1)
