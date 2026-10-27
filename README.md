# TheOneToRuleThemAll

WoW Retail addon for action-bar layouts and macros.

[Download a build](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml?query=branch%3Amain) · [Setup and Undo](TheOneToRuleThemAll/START-HERE.txt)

Version includes; Standard and Compact layouts; Compact uses manual Alt modifiers.

Place addon-folder under `_retail_/Interface/AddOns/`.

Select the matching [talents](TheOneToRuleThemAll/TALENTS.txt).

Open `/tor` outside combat and Stealth.

Review slots before **Apply layout**, then `/reload`. Use `/tor undo` to restore.

Read [Working rules](AGENTS.md) before changing any code; short text + tests for failure risk. 

Functionality must be tried in WoW.

Current dev. follow Method.gg — Mythic+ expanding class-cover on `astra`.

Approved changes can reach `main` without waiting for Claude.

Claude contributes on `claude`; reviewed work can later enter `combined`.

Addon changes will enter `main/origin` after the in-game functionality solidified.

Version hasn't been verified in WoW client yet.

Python 3 + Lua 5.4 shared library installed:

```sh
python3 TheOneToRuleThemAll/validation/run_lua_tests.py
python3 tools/package_addon.py
```

[Code contract](TheOneToRuleThemAll/EXTENDING.txt) · [Changes](TheOneToRuleThemAll/CHANGELOG.txt) · [Playing notes](TheOneToRuleThemAll/PLAY-GUIDE.txt)
