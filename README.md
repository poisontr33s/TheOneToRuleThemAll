# TheOneToRuleThemAll

**The One To Rule Them All** is a World of Warcraft Retail addon that installs
Rogue action-bar layouts and native macros, with an option to restore the previous
setup. Current addon version on this branch: **0.2.2-claude**, targeting Retail **12.1.5**.

[![Test and package](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml/badge.svg)](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml)

Open `/tor` to preview a layout, check what will change, apply it, or undo it.
Every combat action is chosen and pressed by the player.

## Included profiles

| Profile | Specialization | Layout |
| --- | --- | --- |
| `subburst` | Trickster Subtlety | Six offensive choices, with Dance/Blades/Goremaw sharing one macro |
| `sub` | Trickster Subtlety | Seven offensive choices, with separate Goremaw |
| `sublite` | Trickster Subtlety | Six offensive choices, omitting Goremaw use |
| `assa` | Fatebound Assassination | Eight offensive abilities |

Each profile has Standard and Compact layouts. Compact uses manual Alt modifiers.
Other classes and Outlaw have no playable profile yet and remain passive.

## Install and test in WoW

1. Open the latest successful [Test and package run](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml)
   for `main` and download its addon ZIP artifact.
2. With WoW closed, extract the `TheOneToRuleThemAll` folder into
   `World of Warcraft/_retail_/Interface/AddOns/`. Keep existing SavedVariables.
3. Import the relevant code from [TALENTS.txt](TheOneToRuleThemAll/TALENTS.txt).
4. Outside combat and Stealth, on main-bar page 1 with an empty cursor, open `/tor`.
   Review the main bar and every affected Bar 2 slot before clicking **Apply layout**.
5. After successful setup, `/reload` saves the previous setup. `/tor undo` restores
   it in the original specialization and talent loadout.

Existing keys keep their bindings, but will cast the new abilities placed in their
slots. Read [START-HERE.txt](TheOneToRuleThemAll/START-HERE.txt) for upgrade details
and [PLAY-GUIDE.txt](TheOneToRuleThemAll/PLAY-GUIDE.txt) for the playing priorities.

Automated tests use mocked WoW APIs and widgets. Actual client rendering,
protected actions and macro casting have **not yet been verified in WoW**.

## Shared development

This repository is the source for changes by Astra, Claude and the owner.
Read the current `main` before starting, make each change on a separate branch,
and use a pull request for review. Include the purpose, test results and any
remaining live-client checks. This is the working convention; branch protection
is not configured by this initial upload.

Use Git to fetch source changes. ZIP files are installation builds, so source code
does not need to be passed between chats. A local clone contains the addon in the
`TheOneToRuleThemAll/` subfolder; the repository root itself is not an addon folder.

## Local validation and packaging

Requires Python 3 and a Lua 5.4 shared library. On Ubuntu:

```sh
sudo apt-get update
sudo apt-get install -y liblua5.4-0
python3 TheOneToRuleThemAll/validation/run_lua_tests.py
python3 tools/package_addon.py
```

GitHub Actions runs those checks on pushes and pull requests and produces the ZIP.
Generated test summaries and ZIPs are not committed. The action-bar and macro
tests are kept beside the addon under `validation/`.

## Simulation scope

The current Rogue policies retain the original fixed-gear study described in
[GEAR-LOCK.txt](TheOneToRuleThemAll/GEAR-LOCK.txt) and the playing guide. Versions
0.2.0 and 0.2.1 improved setup and recovery; they do not claim a new DPS gain.
The full research archive remains a separate historical artifact and is not
required to test or package this addon. This repository does not contain its raw
simulation runs.

See [CHANGELOG.txt](TheOneToRuleThemAll/CHANGELOG.txt) for addon changes and
[EXTENDING.txt](TheOneToRuleThemAll/EXTENDING.txt) for class-module requirements.
