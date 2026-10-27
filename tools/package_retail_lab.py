#!/usr/bin/env python3
"""Package the optional Windows test desk with the unchanged addon source."""
from pathlib import Path
import hashlib
import sys
import zipfile

ROOT = Path(__file__).resolve().parent.parent
LAB = ROOT / "tools" / "retail_lab"
sys.path.insert(0, str(LAB))
from lab import MAIN, PROBE, source_files


def build():
    files = {name: (LAB / name).read_bytes()
             for name in ("lab.py", "windows.py", "desk.html", "Start-Lab.cmd", "README.md")}
    files.update({"payload/" + MAIN + "/" + name: data
                  for name, data in source_files(ROOT / MAIN).items()})
    files.update({"addon/" + PROBE + "/" + name: data
                  for name, data in source_files(LAB / "addon" / PROBE).items()})
    destination = ROOT / "dist"
    destination.mkdir(exist_ok=True)
    output = destination / "TheOneToRuleThemAll-Retail-Lab.zip"
    temporary = output.with_suffix(".zip.tmp")
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo("Retail-Lab/" + name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    with zipfile.ZipFile(temporary) as archive:
        if archive.testzip() is not None:
            raise ValueError("The lab ZIP failed its integrity check.")
        for name, data in files.items():
            if archive.read("Retail-Lab/" + name) != data:
                raise ValueError("Packaged source differs from the checkout.")
    temporary.replace(output)
    print(str(output))
    print("SHA256 " + hashlib.sha256(output.read_bytes()).hexdigest())


if __name__ == "__main__":
    build()
