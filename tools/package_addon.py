#!/usr/bin/env python3
"""Build the install ZIP after a successful test run; no research archive needed."""

import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "TheOneToRuleThemAll"
TOC = ADDON / "TheOneToRuleThemAll.toc"
SUMMARY = ADDON / "validation" / "validation-summary.json"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def build():
    toc = TOC.read_text(encoding="utf-8")
    match = re.search(r"^## Version:\s*(\S+)\s*$", toc, re.MULTILINE)
    require(match is not None, "The TOC must declare a version.")
    version = match.group(1)
    require(re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?", version),
            "The TOC version is not a safe release version.")
    require(SUMMARY.is_file(), "Run validation/run_lua_tests.py before packaging.")
    summary = json.loads(SUMMARY.read_text(encoding="utf-8"))
    total, passed, failed = (summary.get(key) for key in ("tests", "passed", "failed"))
    require(all(type(value) is int for value in (total, passed, failed)),
            "Test counts must be integers.")
    require(summary.get("suite_completed") is True and summary.get("exit_ok") is True,
            "The test suite did not complete successfully.")
    require(total > 0 and passed == total and failed == 0,
            "Packaging requires a nonempty, fully passing test suite.")
    require(summary.get("version") == version, "Tested version does not match the TOC.")

    # Keep developer tooling and generated test output out of the installed addon.
    files = []
    for path in sorted(ADDON.rglob("*")):
        relative = path.relative_to(ADDON)
        if "validation" in relative.parts or any(part.startswith(".") for part in relative.parts):
            continue
        if path.is_file() and path.suffix.lower() in {".toc", ".lua", ".txt"}:
            require(not path.is_symlink() and path.resolve().is_relative_to(ADDON.resolve()),
                    "Addon files must be regular files within the addon directory.")
            files.append(path)
    included = {path.relative_to(ADDON).as_posix() for path in files}
    require(TOC.name in included, "The install package is missing its TOC.")
    for line in toc.splitlines():
        resource = line.strip().replace("\\", "/")
        if resource and not resource.startswith("#"):
            require(resource in included, f"TOC resource missing from package: {resource}")

    destination = ROOT / "dist"
    destination.mkdir(exist_ok=True)
    output = destination / f"TheOneToRuleThemAll-{version}.zip"
    temporary = output.with_suffix(".zip.tmp")
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            name = "TheOneToRuleThemAll/" + path.relative_to(ADDON).as_posix()
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes(), compresslevel=9)
    with zipfile.ZipFile(temporary) as archive:
        require(archive.testzip() is None, "Generated ZIP failed its integrity check.")
        require("TheOneToRuleThemAll/TheOneToRuleThemAll.toc" in archive.namelist(),
                "Generated ZIP does not have the required AddOns folder structure.")
    temporary.replace(output)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    (destination / "SHA256SUMS.txt").write_text(f"{digest}  {output.name}\n", encoding="utf-8")
    print(json.dumps({"file": str(output), "version": version, "tests": total,
                      "files": len(files), "sha256": digest}))


if __name__ == "__main__":
    try:
        build()
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"Cannot package addon: {error}", file=sys.stderr)
        raise SystemExit(1)
