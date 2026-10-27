#!/usr/bin/env python3
"""Validate reviewed class data and emit the addon's deterministic Lua tables."""

import argparse
import datetime
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "tools" / "class_data"
OUTPUT = ROOT / "TheOneToRuleThemAll" / "StandardData.lua"
FILES = ("plate.json", "leather.json", "mail.json", "cloth.json", "racials.json")
ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
ROSTER = {
    "DEATHKNIGHT": {250: "Blood", 251: "Frost", 252: "Unholy"},
    "PALADIN": {65: "Holy", 66: "Protection", 70: "Retribution"},
    "WARRIOR": {71: "Arms", 72: "Fury", 73: "Protection"},
    "DRUID": {102: "Balance", 103: "Feral", 104: "Guardian", 105: "Restoration"},
    "MONK": {268: "Brewmaster", 269: "Windwalker", 270: "Mistweaver"},
    "DEMONHUNTER": {577: "Havoc", 581: "Vengeance", 1480: "Devourer"},
    "ROGUE": {259: "Assassination", 260: "Outlaw", 261: "Subtlety"},
    "HUNTER": {253: "Beast Mastery", 254: "Marksmanship", 255: "Survival"},
    "SHAMAN": {262: "Elemental", 263: "Enhancement", 264: "Restoration"},
    "EVOKER": {1467: "Devastation", 1468: "Preservation", 1473: "Augmentation"},
    "MAGE": {62: "Arcane", 63: "Fire", 64: "Frost"},
    "PRIEST": {256: "Discipline", 257: "Holy", 258: "Shadow"},
    "WARLOCK": {265: "Affliction", 266: "Demonology", 267: "Destruction"},
}
TANKS = {66, 73, 104, 250, 268, 581}
HEALERS = {65, 105, 256, 257, 264, 270, 1468}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def text(value, location):
    require(isinstance(value, str) and bool(value.strip()), f"{location}: expected nonempty text")
    require(not any(ord(c) < 32 for c in value), f"{location}: unexpected control character")


def positive_id(value, location):
    require(type(value) is int and value > 0, f"{location}: expected a positive integer ID")


def url(value, location):
    text(value, location)
    parsed = urlparse(value)
    require(parsed.scheme == "https" and bool(parsed.netloc), f"{location}: expected an HTTPS source URL")


def date(value, location):
    text(value, location)
    try:
        parsed = datetime.date.fromisoformat(value)
    except ValueError:
        raise ValueError(f"{location}: expected an ISO date") from None
    require(parsed.isoformat() == value, f"{location}: expected YYYY-MM-DD")


def talent_header(code, location="talent code"):
    # Blizzard writes least-significant bits first, including within each 6-bit character.
    # RFC 4648 base64 decoding would read this header in the wrong order.
    require(isinstance(code, str) and len(code) >= 26, f"{location}: incomplete talent header")
    require(all(c in ALPHABET for c in code), f"{location}: invalid talent import character")
    bits = sum(ALPHABET.index(c) << (6 * i) for i, c in enumerate(code[:4]))
    return bits & 255, (bits >> 8) & 65535


def validate_action(action, location):
    require(isinstance(action, dict), f"{location}: expected an action object")
    positive_id(action.get("id"), location + ".id")
    text(action.get("name"), location + ".name")
    require(type(action.get("required")) is bool, f"{location}.required: expected true or false")
    for flag in ("helpful", "targetDead"):
        if flag in action:
            require(type(action[flag]) is bool, f"{location}.{flag}: expected true or false")
    alternatives = action.get("alternatives", [])
    require(isinstance(alternatives, list), f"{location}.alternatives: expected an array")
    ids = [action["id"]]
    for value in alternatives:
        positive_id(value, location + ".alternatives")
        require(value not in ids, f"{location}: repeated alternative spell {value}")
        ids.append(value)
    return ids


def validate_profile(profile, location):
    require(isinstance(profile, dict), f"{location}: expected a profile object")
    for key in ("id", "class", "specName", "role", "patch"):
        text(profile.get(key), location + "." + key)
    require(re.fullmatch(r"standard-[a-z0-9-]+", profile["id"]), f"{location}: invalid profile ID")
    positive_id(profile.get("spec"), location + ".spec")
    cls, spec = profile["class"], profile["spec"]
    require(cls in ROSTER and spec in ROSTER[cls], f"{location}: unknown class/spec pair {cls}/{spec}")
    require(profile["specName"] == ROSTER[cls][spec], f"{location}: spec name does not match {spec}")
    role = "TANK" if spec in TANKS else "HEALER" if spec in HEALERS else "DAMAGER"
    require(profile["role"] == role, f"{location}: {spec} must have role {role}")
    require(re.fullmatch(r"\d+\.\d+\.\d+", profile["patch"]), f"{location}: invalid patch metadata")
    url(profile.get("guide"), location + ".guide")
    date(profile.get("updated"), location + ".updated")
    require(isinstance(profile.get("builds"), list), f"{location}.builds: expected an array")
    for index, build in enumerate(profile["builds"]):
        where = f"{location}.builds[{index}]"
        require(isinstance(build, dict), f"{where}: expected a build object")
        for key in ("label", "hero"):
            text(build.get(key), where + "." + key)
        require(build.get("content") in ("raid", "dungeon"), f"{where}: unknown content type")
        version, imported_spec = talent_header(build.get("code"), where + ".code")
        require(version == 2, f"{where}: unsupported talent serialization version {version}")
        require(imported_spec == spec, f"{where}: import belongs to spec {imported_spec}, expected {spec}")
    require(any(build["content"] == "dungeon" for build in profile["builds"]),
            f"{location}: a published Method Mythic+ build is required")
    seen_spells = set()
    for lane, maximum in (("main", 9), ("utility", 12), ("extra", 9)):
        actions = profile.get(lane)
        require(isinstance(actions, list), f"{location}.{lane}: expected an array")
        require(len(actions) <= maximum, f"{location}.{lane}: exceeds {maximum} slots")
        for index, action in enumerate(actions):
            ids = validate_action(action, f"{location}.{lane}[{index}]")
            require(not seen_spells.intersection(ids), f"{location}: spell is assigned to multiple slots")
            seen_spells.update(ids)
    if "requiredForm" in profile:
        require(type(profile["requiredForm"]) is int and profile["requiredForm"] >= 0,
                f"{location}.requiredForm: expected a form spell ID or 0")
    if "formSpellIDs" in profile:
        require(isinstance(profile["formSpellIDs"], list), f"{location}.formSpellIDs: expected an array")
        for value in profile["formSpellIDs"]:
            positive_id(value, location + ".formSpellIDs")
    if "blockedWhileStealthed" in profile:
        require(type(profile["blockedWhileStealthed"]) is bool,
                f"{location}.blockedWhileStealthed: expected true or false")
    if "notes" in profile:
        require(isinstance(profile["notes"], list), f"{location}.notes: expected an array")
        for note in profile["notes"]:
            text(note, location + ".notes")
    require(isinstance(profile.get("spellSources"), (dict, list)) and bool(profile["spellSources"]),
            f"{location}.spellSources: expected source references")
    sources = profile["spellSources"]
    for source in sources.values() if isinstance(sources, dict) else sources:
        url(source, location + ".spellSources")


def validate_racials(data):
    require(isinstance(data, dict), "racials.json: expected an object")
    date(data.get("checked"), "racials.json.checked")
    require(isinstance(data.get("sources"), list) and bool(data["sources"]), "racials.json: sources are missing")
    for source in data["sources"]:
        url(source, "racials.json.sources")
    require(isinstance(data.get("spells"), list) and bool(data["spells"]), "racials.json: spells are missing")
    names, ids = set(), set()
    for spell in data["spells"]:
        require(isinstance(spell, dict), "racials.json: expected a spell object")
        text(spell.get("name"), "racial name")
        require(spell["name"] not in names, f"racials.json: repeated racial {spell['name']}")
        names.add(spell["name"])
        require(isinstance(spell.get("ids"), list) and bool(spell["ids"]), "racial IDs are missing")
        for value in spell["ids"]:
            positive_id(value, "racial spell ID")
            require(value not in ids, f"racials.json: repeated spell ID {value}")
            ids.add(value)
        url(spell.get("source"), "racial source")


def quote(value):
    escapes = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\r": "\\r", "\t": "\\t"}
    return '"' + "".join(escapes.get(c, f"\\{ord(c):03d}" if ord(c) < 32 or ord(c) == 127 else c)
                         for c in value) + '"'


def lua(value, depth=0):
    """Preserve every JSON field; reject values Lua would silently lose."""
    if isinstance(value, str):
        return quote(value)
    if type(value) is bool:
        return "true" if value else "false"
    if type(value) in (int, float):
        require(math.isfinite(value), "Non-finite numbers cannot be written to Lua")
        return repr(value)
    require(isinstance(value, (dict, list)), "JSON null is not supported; omit an absent field instead")
    if not value:
        return "{}"
    indent = "    " * (depth + 1)
    if isinstance(value, dict):
        entries = [f"[{quote(key)}] = {lua(value[key], depth + 1)}" for key in sorted(value)]
    else:
        entries = [lua(item, depth + 1) for item in value]
    return "{\n" + "\n".join(indent + entry + "," for entry in entries) + "\n" + "    " * depth + "}"


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def generate(source=SOURCE):
    profiles, hashes = [], []
    for filename in FILES:
        raw = (source / filename).read_bytes()
        hashes.append(f"-- {filename}: {hashlib.sha256(raw).hexdigest()}")
        data = json.loads(raw.decode("utf-8"), object_pairs_hook=reject_duplicate_keys)
        if filename == "racials.json":
            validate_racials(data)
            racials = data
        else:
            require(isinstance(data, list), f"{filename}: expected a profile array")
            for index, profile in enumerate(data):
                validate_profile(profile, f"{filename}[{index}]")
                # Keep other references in the source archive, outside the addon.
                profile["builds"] = [build for build in profile["builds"] if build["content"] == "dungeon"]
                profiles.append(profile)
    require(len({p['id'] for p in profiles}) == len(profiles), "Duplicate profile ID")
    require(len({p['spec'] for p in profiles}) == len(profiles), "Duplicate specialization")
    expected = {spec for specs in ROSTER.values() for spec in specs}
    actual = {p["spec"] for p in profiles}
    require(actual == expected, f"Incomplete roster; missing specs: {sorted(expected - actual)}")
    require(len(profiles) == 40 and len({p['class'] for p in profiles}) == 13,
            "Expected all 40 specializations across 13 classes")
    profiles.sort(key=lambda profile: (profile["class"], profile["spec"]))
    header = ["-- Generated by tools/generate_standard_profiles.py; edit tools/class_data/*.json.",
              "-- Source SHA-256:", *hashes, "local A = TheOneToRuleThemAll", ""]
    metadata = {key: value for key, value in racials.items() if key != "spells"}
    return "\n".join(header) + "\nA.standardDefinitions = " + lua(profiles) + \
        "\n\nA.racialDefinitions = " + lua(racials["spells"]) + \
        "\n\nA.racialMetadata = " + lua(metadata) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the generated Lua file differs")
    args = parser.parse_args()
    expected = generate().encode("utf-8")
    if args.check:
        require(OUTPUT.is_file() and OUTPUT.read_bytes() == expected,
                "StandardData.lua is missing or stale; run tools/generate_standard_profiles.py")
        print("StandardData.lua matches validated source data.")
    else:
        temporary = OUTPUT.with_suffix(".lua.tmp")
        temporary.write_bytes(expected)
        temporary.replace(OUTPUT)
        print("Generated StandardData.lua for 40 specializations across 13 classes.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"Cannot generate standard profiles: {error}", file=sys.stderr)
        raise SystemExit(1)
