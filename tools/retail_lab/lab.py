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
import stat
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit
import webbrowser

import deployment


HERE = Path(__file__).resolve().parent
MAIN = "TheOneToRuleThemAll"
PROBE = MAIN + "_ClientTest"
REPORT_VARIABLE = "TheOneToRuleThemAllClientTestReport"
COMMANDS = {"tor", "talents", "test", "reload"}
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
    toc = folder / (folder.name + ".toc")
    if not toc.is_file():
        raise ValueError(f"Missing {folder.name}.toc in {folder}")
    no_links(toc, folder)
    resources = {line.strip().replace("\\", "/") for line in toc.read_text(encoding="utf-8").splitlines()
                 if line.strip() and not line.lstrip().startswith("#")}
    resources.add(toc.name)
    resources.update(name for name in ("START-HERE.txt", "CHANGELOG.txt", "EXTENDING.txt")
                     if (folder / name).is_file())
    for name in sorted(resources):
        if Path(name).is_absolute() or ".." in Path(name).parts:
            raise ValueError("Addon source paths must stay within their folder.")
        file = folder / name
        no_links(file, folder)
        if not file.resolve().is_relative_to(folder.resolve()):
            raise ValueError("Linked addon source files are not supported.")
        files[name] = file.read_bytes()
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
    while True:
        try:
            attributes = current.lstat()
        except FileNotFoundError:
            attributes = None
        if attributes and (stat.S_ISLNK(attributes.st_mode) or
                getattr(attributes, "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 1024)):
            raise ValueError(f"Refusing to use a linked path: {current}")
        if current == boundary:
            break
        if current.parent == current:
            raise ValueError("Installation path is outside the selected client.")
        current = current.parent


def _ensure_wow_closed():
    if wow_running():
        raise ValueError("Close WoW before installing or restoring addon folders.")


def install_addons(client, state_dir, main_source, probe_source):
    main_files, probe_files = source_files(main_source), source_files(probe_source)
    return deployment.install(client, state_dir, main_files, probe_files,
                              source_digest(main_files), _ensure_wow_closed)


def deployment_status(client, state_dir, deployment_id=None):
    return deployment.status(client, state_dir, deployment_id)


def restore_addons(client, state_dir, deployment_id=None):
    return deployment.restore(client, state_dir, _ensure_wow_closed, deployment_id)


def verify_install(client, manifest):
    errors = []
    files = manifest.get("files")
    required = {MAIN + "/" + MAIN + ".toc", PROBE + "/" + PROBE + ".toc", PROBE + "/ClientTest.lua"}
    if (manifest.get("schema") not in (1, 2) or not isinstance(files, dict) or not required <= files.keys()
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
        raise RuntimeError("Could not establish whether WoW is closed. Keep WoW closed before retrying.") from error
    rows = [row for row in csv.reader(result.stdout.splitlines()) if row]
    if not rows or any(len(row) < 2 or not row[1].strip().isdigit() for row in rows):
        raise RuntimeError("Could not read the Windows process list. Keep WoW closed before retrying.")
    return any(row[0].lower() in {"wow.exe", "wowt.exe"} for row in rows)


def print_deployment_status(result):
    labels = {
        "not_installed": "No test installation found.",
        "installed": "Test build installed. Original addon folders can be restored.",
        "restore_pending": "Restore was interrupted. Close WoW and run --restore again.",
        "install_pending": "Installation was interrupted. Close WoW and run --restore to recover.",
        "restored": "Original addon folders restored. Test files and saved settings were kept.",
        "legacy": "Older installation: automatic restoration is unavailable.",
        "blocked": "Restoration is blocked. No files were changed.",
    }
    if result.get("already_restored"):
        print("This deployment was already restored. Current addon folders were left as they are.")
    else:
        print(labels.get(result["state"], result["state"]))
    if result.get("deployment_id"):
        print("Deployment: " + result["deployment_id"])
    for error in result.get("errors", []):
        print(error)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wow-path", type=Path, help="World of Warcraft, _retail_, or _ptr_ folder")
    operation = parser.add_mutually_exclusive_group()
    operation.add_argument("--install", action="store_true", help="Install this source build; back up existing addon folders")
    operation.add_argument("--restore", action="store_true", help="Restore the original addon folders; keep saved settings and test files")
    operation.add_argument("--status", action="store_true", help="Inspect installation and backup integrity without writing files")
    parser.add_argument("--deployment", help="Inspect or restore a specific deployment shown by --status")
    parser.add_argument("--port", type=int, default=0, help="Local port (default: pick an available port)")
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args(argv)
    if args.install and args.deployment:
        parser.error("--deployment selects an existing installation; use it with --status or --restore.")
    if os.name != "nt" and not args.status:
        parser.error("This bridge needs Windows with the real WoW client. It does not simulate a client.")
    client = client_directory(args.wow_path) if args.wow_path else find_client()
    if not client:
        typed = input("WoW installation folder: ").strip().strip('"')
        client = client_directory(typed)
    state_dir = HERE / "state"
    if args.status:
        result = deployment_status(client, state_dir, args.deployment)
        print_deployment_status(result)
        return 1 if result["state"] in {"blocked", "legacy"} else 0
    if args.restore:
        print_deployment_status(restore_addons(client, state_dir, args.deployment))
        return 0
    if args.install:
        main_source = HERE / "payload" / MAIN
        if not main_source.is_dir():
            main_source = HERE.parents[1] / MAIN
        manifest = install_addons(client, state_dir, main_source, HERE / "addon" / PROBE)
        print("Test build ready. Original addon folders and saved settings were kept. --restore puts the original folders back.")
    else:
        result = deployment_status(client, state_dir, args.deployment)
        if result["state"] not in {"installed", "legacy"}:
            print_deployment_status(result)
            raise ValueError("No intact active test build is available for this desk.")
        manifest = result["manifest"]
    import windows
    executable = client / ("WowT.exe" if client.name.lower() == "_ptr_" else "Wow.exe")
    windows.configure(str(executable))
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
        raise SystemExit(main() or 0)
    except (OSError, ValueError, RuntimeError) as error:
        print("Cannot start the test desk: " + str(error))
        raise SystemExit(1)
