# TheOneToRuleThemAll

WoW Retail action-bar setup for every class, based on Method.gg Mythic+ builds.
**0.5.0-astra · Retail 12.1.5 · in-game acceptance pending.**

[Download a build](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml?query=branch%3Aastra) · [Setup and Undo](TheOneToRuleThemAll/START-HERE.txt)

With WoW closed, replace the addon folder under `_retail_/Interface/AddOns/`.
Keep SavedVariables. Open `/tor`, copy a **Mythic+ talents** code and import it
in WoW. Review the buttons before **Apply layout**; use `/tor undo` to restore them.

Core spells use the main bar, utility Bar 2, and extras Bar 3. Active racials
have reserved slots. Healers can choose Mouseover. Existing keys and gear stay.
Method references update with addon releases. Talents are imported manually.
**Show details** includes the fixed gem/enchant template and the correct leg enchant.

Read [Working rules](AGENTS.md) before changing code: small readable changes,
short plain text, and tests for real failure risks. Functionality must be tried in WoW.
Astra develops on `astra`; approved changes can reach `main` without waiting for Claude.
`combined` is for later work with `claude`. New gameplay still needs acceptance in WoW.

For local checks, install Python 3 and a Lua 5.4 shared library, then run:
```sh
python3 tools/generate_standard_profiles.py --check
python3 TheOneToRuleThemAll/validation/run_lua_tests.py
python3 tools/package_addon.py
```
[Code contract](TheOneToRuleThemAll/EXTENDING.txt) · [Changes](TheOneToRuleThemAll/CHANGELOG.txt) · [Optional Retail Lab](tools/retail_lab/README.md)
