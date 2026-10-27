"""Install and restore the two test addons without deleting player files."""

from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import stat
import time

MAIN = "TheOneToRuleThemAll"
PROBE = MAIN + "_ClientTest"
ADDONS = (MAIN, PROBE)
ID = re.compile(r"[a-f0-9]{32}\Z")
HASH = re.compile(r"[a-f0-9]{64}\Z")
PHASES = {"installing", "installed", "restoring", "restored"}


def _no_links(path, boundary):
    path, boundary = Path(path), Path(boundary)
    if not path.is_relative_to(boundary):
        raise ValueError("A deployment path is outside the selected WoW installation.")
    while True:
        try:
            info = path.lstat()
        except FileNotFoundError:
            info = None
        if info and (stat.S_ISLNK(info.st_mode) or
                     getattr(info, "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 1024)):
            raise ValueError(f"Linked or redirected paths are not supported: {path}")
        if path == boundary:
            return
        path = path.parent


def _tree(path, client):
    """A complete directory inventory; None means the directory is absent."""
    _no_links(path, client)
    if not path.exists():
        return None
    if not path.is_dir():
        raise ValueError(f"Expected an addon directory: {path}")
    files, directories = {}, []
    def unreadable(error):
        raise error
    for current, dirs, names in os.walk(path, followlinks=False, onerror=unreadable):
        parent = Path(current)
        for name in dirs:
            child = parent / name
            _no_links(child, client)
            directories.append(child.relative_to(path).as_posix())
        for name in names:
            child = parent / name
            _no_links(child, client)
            if not stat.S_ISREG(child.stat().st_mode):
                raise ValueError(f"An addon contains an unsupported file: {child}")
            digest = hashlib.sha256()
            with child.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            files[child.relative_to(path).as_posix()] = digest.hexdigest()
    return {"files": files, "directories": sorted(directories)}


def _inventory(files):
    directories = set()
    for name in files:
        parent = PurePosixPath(name).parent
        while parent != PurePosixPath("."):
            directories.add(parent.as_posix())
            parent = parent.parent
    return {"files": {name: hashlib.sha256(data).hexdigest() for name, data in files.items()},
            "directories": sorted(directories)}


def _relative(name):
    return (isinstance(name, str) and name != "" and "\\" not in name and ":" not in name
            and not name.startswith("/") and all(part not in {"", ".", ".."} for part in name.split("/")))


def _valid_tree(value):
    return (isinstance(value, dict) and set(value) == {"files", "directories"}
            and isinstance(value["files"], dict) and isinstance(value["directories"], list)
            and all(_relative(name) and isinstance(digest, str) and HASH.fullmatch(digest)
                    for name, digest in value["files"].items())
            and all(_relative(name) for name in value["directories"])
            and len(set(value["directories"])) == len(value["directories"]))


def _root(client):
    return client / "WTF" / "TORClientLabBackups"


def _read(path, client):
    _no_links(path, client)
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def _atomic_json(path, data):
    temporary = path.with_name("." + path.name + "-" + secrets.token_hex(8) + ".tmp")
    created = False
    try:
        with temporary.open("x", encoding="utf-8") as stream:
            created = True
            json.dump(data, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)
    finally:
        if created and temporary.exists():
            temporary.unlink()


@contextmanager
def _lock(client):
    root = _root(client)
    _no_links(root, client)
    root.mkdir(parents=True, exist_ok=True)
    path = root / "lab.lock"
    _no_links(path, client)
    with path.open("a+b") as stream:
        if stream.tell() == 0:
            stream.write(b"0")
            stream.flush()
        stream.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise ValueError("Another Lab install or restore is running for this WoW installation.") from error
        try:
            yield
        finally:
            if os.name == "nt":
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def _manifest(client, path):
    value = _read(path, client)
    if (not isinstance(value, dict) or value.get("schema") != 2
            or not ID.fullmatch(str(value.get("deployment_id", "")))
            or value.get("client") != str(client)
            or not HASH.fullmatch(str(value.get("source_sha256", "")))
            or not HASH.fullmatch(str(value.get("probe_sha256", "")))
            or set(value.get("originals", {})) != set(ADDONS)
            or set(value.get("installed", {})) != set(ADDONS)):
        raise ValueError("The deployment manifest is invalid or belongs to a different WoW installation.")
    root = _root(client) / value["deployment_id"]
    if path != root / "deployment.json" or value.get("backup") != str(root):
        raise ValueError("The deployment manifest does not match its backup location.")
    for name in ADDONS:
        if not _valid_tree(value["installed"][name]):
            raise ValueError("The installed-file inventory is invalid.")
        if value["originals"][name] is not None and not _valid_tree(value["originals"][name]):
            raise ValueError("The original-file inventory is invalid.")
    expected = {addon + "/" + name: digest for addon in ADDONS
                for name, digest in value["installed"][addon]["files"].items()}
    if value.get("files") != expected:
        raise ValueError("The deployment's file records disagree.")
    return value


def _receipt(client, manifest):
    try:
        value = _read(_root(client) / manifest["deployment_id"] / "receipt.json", client)
    except FileNotFoundError:
        # The manifest is written before the first progress receipt or move.
        # A crash in that gap is recoverable only if every original is intact.
        for name in ADDONS:
            target, backup, removed, _ = _locations(client, manifest, name)
            if (_tree(target, client) != manifest["originals"][name]
                    or _tree(backup, client) is not None or _tree(removed, client) is not None):
                raise ValueError("The progress record is missing and original locations cannot be confirmed.")
        return {"deployment_id": manifest["deployment_id"], "phase": "installing"}
    if (not isinstance(value, dict) or value.get("deployment_id") != manifest["deployment_id"]
            or value.get("phase") not in PHASES or type(value.get("from_install", False)) is not bool):
        raise ValueError("The deployment progress record is invalid. No files were changed.")
    return value


def _locations(client, manifest, name):
    root = _root(client) / manifest["deployment_id"]
    return (client / "Interface" / "AddOns" / name, root / name,
            root / "installed" / name, root / "staged" / name)


def _steps(client, manifest, receipt):
    """Validate both addons before returning the next safe folder moves."""
    result = []
    installing = receipt["phase"] == "installing" or receipt.get("from_install", False)
    for name in ADDONS:
        target, backup, removed, staged = _locations(client, manifest, name)
        current, old, parked, stage = (_tree(path, client) for path in (target, backup, removed, staged))
        original, installed = manifest["originals"][name], manifest["installed"][name]
        if old is not None and old != original:
            raise ValueError(f"Original backup is changed or contains unknown files: {name}. Nothing was overwritten.")
        if parked is not None and parked != installed:
            raise ValueError(f"Retained test files changed: {name}. Nothing was overwritten.")
        if installing and parked is None and (
                (current == original and old is None) or (current is None and old == original)):
            # A failed write can leave an incomplete staging directory. It is
            # retained verbatim; restoring a verified original never uses it.
            if current is None and original is not None:
                result.append((backup, target))
            continue
        if stage is not None and stage != installed:
            raise ValueError(f"Staged test files changed: {name}. Nothing was overwritten.")
        if parked is not None and stage is not None:
            raise ValueError(f"Conflicting retained and staged files: {name}.")
        if receipt["phase"] == "installed":
            if current != installed or old != original or parked is not None or stage is not None:
                raise ValueError(f"Installed files or the original backup are missing or changed: {name}. Nothing was overwritten.")
            result.append((target, removed))
            if original is not None:
                result.append((backup, target))
            continue
        if parked is not None:
            if current is None and old == original:
                if original is not None:
                    result.append((backup, target))
            elif current != original or old is not None:
                raise ValueError(f"Cannot safely resume restoration of {name}; an original or destination changed.")
        elif installing and current == original and old is None:
            # Installation had not moved this original. Leave it where it is.
            pass
        elif current == installed and old == original and stage is None:
            result.append((target, removed))
            if original is not None:
                result.append((backup, target))
        elif installing and current is None and old == original and stage is not None:
            if original is not None:
                result.append((backup, target))
        else:
            raise ValueError(f"Cannot safely restore {name}; a backup, installed folder or original is missing or changed.")
    return result


def _result(state, manifest=None, errors=None):
    return {"state": state, "deployment_id": manifest.get("deployment_id") if manifest else None,
            "manifest": manifest, "errors": errors or []}


def status(client, state_dir, deployment_id=None):
    """Read-only discovery; no directories, locks or state files are created."""
    client, state_dir = Path(client), Path(state_dir)
    try:
        if deployment_id is not None and not ID.fullmatch(deployment_id):
            raise ValueError("The deployment ID must be the full ID printed by --status.")
        local = state_dir / "deployment.json"
        _no_links(local.absolute(), Path(local.absolute().anchor))
        if local.exists():
            value = json.loads(local.read_text(encoding="utf-8"))
            if not isinstance(value, dict):
                raise ValueError("The local deployment record must be a JSON object.")
            if value.get("client") != str(client):
                raise ValueError("The local deployment record belongs to a different WoW installation.")
            if value.get("schema") == 1:
                return _result("legacy", value, ["This older installation has no verified original-file inventory. Restore it manually; automatic restore cannot safely infer the backup contents."])
            if value.get("schema") != 2:
                raise ValueError("The local deployment record has an unsupported format.")
        root = _root(client)
        _no_links(root, client)
        paths = []
        if deployment_id:
            paths = [root / deployment_id / "deployment.json"]
        elif root.exists():
            for child in sorted(root.iterdir()):
                if ID.fullmatch(child.name):
                    _no_links(child, client)
                    if child.is_dir() and not any(child.iterdir()):
                        continue  # No manifest or addon move was ever written.
                    paths.append(child / "deployment.json")
        if not paths:
            if local.exists():
                raise ValueError("The recorded deployment backup is missing; keep the installed files and recover the backup first.")
            return _result("not_installed")
        active, completed = [], []
        for path in paths:
            manifest = _manifest(client, path)
            receipt = _receipt(client, manifest)
            if receipt["phase"] == "restored":
                completed.append({**_result("restored", manifest), "already_restored": True})
                continue
            try:
                _steps(client, manifest, receipt)
                state = {"installed": "installed", "installing": "install_pending", "restoring": "restore_pending"}[receipt["phase"]]
                active.append(_result(state, manifest))
            except (OSError, ValueError) as error:
                active.append(_result("blocked", manifest, [str(error)]))
        if len(active) > 1:
            return _result("blocked", errors=["Several unfinished deployments exist. Use --status --deployment ID to inspect each record. Resolve the conflicting history manually before automatic restore."])
        if active:
            return active[0]
        return max(completed, key=lambda item: item["manifest"]["installed_at"])
    except (OSError, ValueError, TypeError, KeyError) as error:
        return _result("blocked", errors=[str(error)])


def _save_receipt(client, manifest, phase, from_install=False):
    path = _root(client) / manifest["deployment_id"] / "receipt.json"
    _no_links(path, client)
    _atomic_json(path, {"deployment_id": manifest["deployment_id"], "phase": phase,
                        "from_install": from_install})


def _restore(client, manifest, ensure_closed):
    receipt = _receipt(client, manifest)
    if receipt["phase"] == "restored":
        return {**_result("restored", manifest), "already_restored": True}
    moves = _steps(client, manifest, receipt)
    ensure_closed()
    _save_receipt(client, manifest, "restoring", receipt["phase"] == "installing" or receipt.get("from_install", False))
    for source, destination in moves:
        ensure_closed()
        _no_links(source, client)
        _no_links(destination, client)
        addon = source.name
        expected = manifest["installed"][addon] if source.parent == client / "Interface" / "AddOns" else manifest["originals"][addon]
        if _tree(source, client) != expected:
            raise ValueError(f"Files changed before moving {addon}. Nothing was overwritten.")
        if destination.exists():
            raise ValueError(f"Restore destination appeared during the operation: {destination}. Nothing was overwritten.")
        destination.parent.mkdir(parents=True, exist_ok=True)
        source.rename(destination)
    # Recheck every directory before recording successful completion.
    receipt = _receipt(client, manifest)
    if _steps(client, manifest, receipt):
        raise ValueError("Restoration is incomplete. Run --restore again with WoW closed.")
    _save_receipt(client, manifest, "restored")
    return _result("restored", manifest)


def restore(client, state_dir, ensure_closed, deployment_id=None):
    client, state_dir = Path(client), Path(state_dir)
    ensure_closed()
    initial = status(client, state_dir, deployment_id)
    latest = status(client, state_dir)
    if deployment_id and (latest["state"] not in {"not_installed", "restored"}
                          and latest["deployment_id"] != deployment_id):
        raise ValueError(" ".join(latest["errors"]) or "Another unfinished deployment is current: " + str(latest["deployment_id"]) + ". Inspect --status before restoring.")
    if initial["state"] == "restored":
        return {**initial, "already_restored": True}
    if initial["state"] not in {"installed", "restore_pending", "install_pending"}:
        raise ValueError(" ".join(initial["errors"]) or "There is no Lab installation to restore.")
    with _lock(client):
        current = status(client, state_dir, deployment_id)
        if current["state"] not in {"installed", "restore_pending", "install_pending", "restored"}:
            raise ValueError(" ".join(current["errors"]) or "The deployment changed before restore.")
        return _restore(client, current["manifest"], ensure_closed)


def install(client, state_dir, main_files, probe_files, source_sha256, ensure_closed):
    client, state_dir = Path(client), Path(state_dir)
    ensure_closed()
    if state_dir.exists() and not state_dir.is_dir():
        raise NotADirectoryError(f"The Lab state path is not a directory: {state_dir}")
    probe_sha256 = hashlib.sha256(json.dumps({name: hashlib.sha256(data).hexdigest()
                                            for name, data in sorted(probe_files.items())}).encode()).hexdigest()
    for files in (main_files, probe_files):
        if not files or any(not _relative(name) or not isinstance(data, bytes) for name, data in files.items()):
            raise ValueError("The addon payload contains invalid file names or bytes.")
    if "ClientTest.lua" not in probe_files or not HASH.fullmatch(source_sha256):
        raise ValueError("The addon payload is incomplete.")
    initial = status(client, state_dir)
    if initial["state"] not in {"not_installed", "restored", "installed"}:
        raise ValueError(" ".join(initial["errors"]) or "Finish --restore for the previous deployment before installing again.")
    with _lock(client):
        current = status(client, state_dir)
        if current["state"] == "installed":
            manifest = current["manifest"]
            if manifest["source_sha256"] == source_sha256 and manifest["probe_sha256"] == probe_sha256:
                return manifest
            raise ValueError("A different Lab build is installed. Run --restore with WoW closed before installing this one.")
        if current["state"] not in {"not_installed", "restored"}:
            raise ValueError(" ".join(current["errors"]) or "Finish --restore for the previous deployment before installing again.")
        state_dir.mkdir(parents=True, exist_ok=True)
        if state_dir.is_symlink():
            raise ValueError("The Lab state directory must not be linked.")
        addons = client / "Interface" / "AddOns"
        _no_links(addons, client)
        originals = {name: _tree(addons / name, client) for name in ADDONS}
        deployment_id = secrets.token_hex(16)
        root = _root(client) / deployment_id
        root.mkdir()
        probe_files = dict(probe_files)
        header = ('TheOneToRuleThemAllClientTestDeployment = { id = "' + deployment_id
                  + '", source_sha256 = "' + source_sha256 + '" }\n').encode("ascii")
        probe_files["ClientTest.lua"] = header + probe_files["ClientTest.lua"]
        payload = {MAIN: main_files, PROBE: probe_files}
        installed = {name: _inventory(files) for name, files in payload.items()}
        manifest = {"schema": 2, "deployment_id": deployment_id, "source_sha256": source_sha256,
                    "probe_sha256": probe_sha256, "installed_at": time.time(), "client": str(client),
                    "backup": str(root), "originals": originals, "installed": installed,
                    "files": {addon + "/" + name: digest for addon, tree in installed.items()
                              for name, digest in tree["files"].items()}}
        _atomic_json(root / "deployment.json", manifest)
        _save_receipt(client, manifest, "installing")
        try:
            for name, files in payload.items():
                staging = root / "staged" / name
                for relative, data in files.items():
                    output = staging / relative
                    output.parent.mkdir(parents=True, exist_ok=True)
                    output.write_bytes(data)
                if _tree(staging, client) != installed[name]:
                    raise OSError("The staged addon does not match the packaged files.")
            addons.mkdir(parents=True, exist_ok=True)
            for name in ADDONS:
                ensure_closed()
                target, backup, _, staged = _locations(client, manifest, name)
                if _tree(target, client) != originals[name]:
                    raise ValueError("An original addon changed during installation. No changed files were overwritten.")
                if originals[name] is not None:
                    target.rename(backup)
                staged.rename(target)
            _save_receipt(client, manifest, "installed")
            _atomic_json(state_dir / "deployment.json", manifest)
            return manifest
        except Exception as error:
            try:
                _restore(client, manifest, ensure_closed)
            except Exception as recovery:
                raise RuntimeError(f"Installation stopped. Backups were retained; use --status and --restore. {recovery}") from error
            raise
