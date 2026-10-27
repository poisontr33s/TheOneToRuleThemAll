#!/usr/bin/env python3
"""Check that the original custom profiles and their source notes are unchanged."""

import hashlib
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
BASELINE = "47ea6a3159e4ae9ae616494b742ef7a205761f39"


def check(root=ROOT):
    manifest = json.loads((root / "tools" / "foundation.json").read_text(encoding="utf-8"))
    if manifest.get("sourceCommit") != BASELINE or manifest.get("algorithm") != "sha256":
        raise ValueError("Foundation manifest does not identify the original baseline.")
    files = manifest.get("files")
    if not isinstance(files, dict) or len(files) != 5:
        raise ValueError("Foundation manifest must protect the five original source files.")
    changed = []
    for name, expected in files.items():
        path = Path(name)
        if path.is_absolute() or ".." in path.parts or not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise ValueError("Foundation manifest contains an invalid path or SHA-256.")
        try:
            actual = hashlib.sha256((root / path).read_bytes()).hexdigest()
        except FileNotFoundError:
            changed.append(name + " (missing)")
            continue
        if actual != expected:
            changed.append(name)
    return changed


if __name__ == "__main__":
    try:
        changed = check()
        if changed:
            print("Foundation changed: " + ", ".join(changed), file=sys.stderr)
            raise SystemExit(1)
        print("Foundation unchanged: original custom profiles and source notes match the baseline.")
    except (OSError, ValueError) as error:
        print(f"Cannot verify foundation: {error}", file=sys.stderr)
        raise SystemExit(1)
