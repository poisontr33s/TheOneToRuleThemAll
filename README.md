# TheOneToRuleThemAll

**The One To Rule Them All** is a World of Warcraft Retail addon that installs
Rogue and Blood Death Knight action-bar layouts, with an option to restore the
previous setup. Current addon version: **0.3.1-combined**, targeting Retail **12.1.5**.

[![Test and package](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml/badge.svg?branch=combined)](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml?query=branch%3Acombined)

Open `/tor` to preview a layout, check what will change, apply it, or undo it.
Every combat action is chosen and pressed by the player.

The preview shows your existing keys alongside the abilities, including Compact
Alt combinations and unbound slots. Macro buttons describe the abilities they
cast. This reads WoW's built-in bindings; custom action-bar addons may use other
bindings. Opening the preview does not assign keys or move buttons.

## Included profiles

| Profile | Specialization | Layout |
| --- | --- | --- |
| `subburst` | Trickster Subtlety | Six offensive choices, with Dance/Blades/Goremaw sharing one macro |
| `sub` | Trickster Subtlety | Seven offensive choices, with separate Goremaw |
| `sublite` | Trickster Subtlety | Six offensive choices, omitting Goremaw use |
| `assa` | Fatebound Assassination | Eight offensive abilities |
| `blood-sanlayn` | San'layn Blood | Yipyep's Shed Assymetry: separate core attacks, DRW, movement and defensives |
| `blood-deathbringer` | Deathbringer Blood | Same Blood layout, with Reaper's Mark on Bar 2 slot 11 |

Rogue profiles have Standard and Compact layouts. Compact uses manual Alt modifiers.
Blood profiles use Standard with individual spell buttons and the character's
existing talent loadout. The preview starts with the compatible hero profile;
applying it is manual. No trinkets, talents or keys are changed. Unlearned optional
abilities leave their slots untouched. Read [BLOOD-SETUP.txt](TheOneToRuleThemAll/BLOOD-SETUP.txt)
for the exact slots and the San'layn/Deathbringer switch sequence.
Other classes, other DK specializations and Outlaw remain passive.

## Install and test in WoW

1. Open the latest successful [Test and package run](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml)
   for `combined` and download its addon ZIP artifact. It contains the integrated
   changes from `astra` and `claude`; `main` is the previous shared baseline.
2. With WoW closed, extract the `TheOneToRuleThemAll` folder into
   `World of Warcraft/_retail_/Interface/AddOns/`. Keep existing SavedVariables.
3. Select your intended talent loadout; reference codes are in
   [TALENTS.txt](TheOneToRuleThemAll/TALENTS.txt). For Blood, keep the matching
   Shed Assymetry loadout you already use.
4. Outside combat and Stealth, on main-bar page 1 with an empty cursor, open `/tor`.
   Review the main bar and every affected Bar 2 slot before clicking **Apply layout**.
5. After successful setup, use `/reload`, then try the buttons on a training dummy.
   On Blood, check Heart Strike/Vampiric Strike or Marrowrend/Exterminate through
   a proc, plus the separate movement and defensive buttons. On Rogue, check
   the builder in and out of Stealth, burst, and Compact's manual Alt choices.
6. Leave combat and return to the original specialization/loadout and main-bar
   page 1. Use `/tor undo` and check that your previous buttons return.

Existing keys keep their bindings, but will cast the new abilities placed in their
slots. Read [START-HERE.txt](TheOneToRuleThemAll/START-HERE.txt) for upgrade details
and [PLAY-GUIDE.txt](TheOneToRuleThemAll/PLAY-GUIDE.txt) for the playing priorities.

Automated tests use mocked WoW APIs and widgets. Actual client rendering,
protected actions and macro casting have **not yet been verified in WoW**.
The checks above remain open until performed in the client. A passing CI run
means the code tests and packaging passed; it does not mark these checks complete.

## Shared development

This repository is the source for changes by Astra, Claude and the owner.
`astra` and `claude` are the development branches. `combined` brings their
reviewed improvements together for one installable build. Merge commits retain
both source histories. Fix integration problems on `combined`, and bring later
source changes in explicitly after reviewing their diff.

This build combines Astra's key preview and Blood profiles with Claude's clearer
messages, Toy Box support and missing-button handling during Undo. Failed Apply
now uses strict rollback: incomplete restoration keeps the backup available and
does not report that all original buttons were restored.

Use a pull request from `combined` to `main` for the shared release. Record the
code checks and actual in-game results separately. CI does not merge branches.

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
[GEAR-LOCK.txt](TheOneToRuleThemAll/GEAR-LOCK.txt) and the playing guide.
The Blood module installs the user's existing custom talent foundation as a
button layout. It has no automatic priorities or coupled casts and makes no
new DPS or survivability claim. Earlier Blood DPS simulations do not validate
tank survivability. Both hero variants retain manual Death Strike, DRW and
defensive timing. The addon does not validate the full talent code.
The full research archive remains a separate historical artifact and is not
required to test or package this addon. This repository does not contain its raw
simulation runs.

See [CHANGELOG.txt](TheOneToRuleThemAll/CHANGELOG.txt) for addon changes and
[EXTENDING.txt](TheOneToRuleThemAll/EXTENDING.txt) for class-module requirements.
