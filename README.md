# TheOneToRuleThemAll

WoW Retail addon for Rogue action-bar layouts and macros, with Undo.
**main currently holds 0.2.1 · Retail 12.1.5.**

[Download a build](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml?query=branch%3Amain) · [Setup and Undo](TheOneToRuleThemAll/START-HERE.txt)

This version includes Trickster Subtlety and Fatebound Assassination profiles.
Standard and Compact layouts are available; Compact uses manual Alt modifiers.

With WoW closed, place the addon folder under `_retail_/Interface/AddOns/`.
Keep SavedVariables and select the matching [talents](TheOneToRuleThemAll/TALENTS.txt).
Open `/tor` outside combat and Stealth, on main-bar page 1 with an empty cursor.
Review the slots before **Apply layout**, then `/reload`. Use `/tor undo`
in the original spec and talent loadout to restore your previous buttons.

Read [Working rules](AGENTS.md) before changing code: small readable changes,
short plain text, and tests for real failure risks. Functionality must be tried in WoW.
Current development follows Method Mythic+ and expands class coverage on `astra`.
Claude reviews and contributes on `claude`; reviewed work enters `combined`.
Addon changes enter `main` after the owner's in-game acceptance.
This retained version has not yet been verified in the WoW client.

With Python 3 and a Lua 5.4 shared library installed:
```sh
python3 TheOneToRuleThemAll/validation/run_lua_tests.py
python3 tools/package_addon.py
```
[Code contract](TheOneToRuleThemAll/EXTENDING.txt) · [Changes](TheOneToRuleThemAll/CHANGELOG.txt) · [Playing notes](TheOneToRuleThemAll/PLAY-GUIDE.txt)
