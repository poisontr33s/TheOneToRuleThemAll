#!/usr/bin/env python3
"""Embed the original playing guide so WoW can load it as addon data."""

from pathlib import Path


ADDON = Path(__file__).resolve().parent.parent / "TheOneToRuleThemAll"
source = (ADDON / "PLAY-GUIDE.txt").read_text(encoding="utf-8")
delimiter = "="
while "]" + delimiter + "]" in source:
    delimiter += "="
output = (
    "-- Generated from PLAY-GUIDE.txt by tools/sync_play_guide.py.\n"
    "-- Edit the original text, then run that script to update this copy.\n"
    "TheOneToRuleThemAll.playGuideSource = [" + delimiter + "[\n"
    + source + "]" + delimiter + "]\n"
)
(ADDON / "PlayGuideData.lua").write_text(output, encoding="utf-8")
