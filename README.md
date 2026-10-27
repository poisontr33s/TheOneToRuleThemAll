# TheOneToRuleThemAll

**The One To Rule Them All** is a World of Warcraft Retail addon with reversible
action-bar layouts for all **40 specializations across 13 classes**, alongside
the original custom Rogue and Blood Death Knight setups.
Current addon version: **0.4.0-astra**, targeting Retail **12.1.5**.

[![Test and package](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml/badge.svg?branch=astra)](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml?query=branch%3Aastra)

Open `/tor` to preview a layout, check what will change, apply it, or undo it.
Every combat action is chosen and pressed by the player.

**Talent builds** or `/tor talents` opens the bundled Method references for your
specialization. Choose a published build, copy its exact code, and import it in
WoW's talent window if you want it. Each reference keeps its guide link, patch
and update date. Browsing never changes your talents or applies a layout.

For SubBurst and Fatebound Assassination, **Play guide** in that panel or
`/tor guide` opens the original playing priorities alongside the selected
layout's actual keys. SubBurst includes both the precise and easier core rules
with the complete burst timing. Return to setup to apply or undo a layout.
The guide's comparisons refer to the original reference model, not a new live
measurement. Other profiles do not inherit these priorities.

The preview shows your existing keys alongside the abilities, including Compact
Alt combinations and unbound slots. Macro buttons describe the abilities they
cast. This reads WoW's built-in bindings; custom action-bar addons may use other
bindings. Opening the preview does not assign keys or move buttons.

## Included profiles

The `standard-*` profiles cover every specialization, including Outlaw,
Devourer, all healers and all tanks. They place learned core abilities on the
main bar, utility on Bar 2, and additional abilities on Bar 3. Learned racial
abilities use Bar 3 slots 10–12. Unlearned optional talents leave their slots
untouched. The layout keeps native base spell buttons through temporary procs;
it does not choose attacks or rank your talent combinations.

Healers can explicitly select **Mouseover** instead of **Standard**: friendly
spells use a valid mouseover, otherwise their normal target. Standard uses
individual spell buttons. Feral setup requires Cat Form, Guardian requires
Bear Form, and Restoration Druid requires caster form. Only the selected
form's main bar changes. Standard Rogue setup requires leaving Stealth/Shadow Dance and
changes the normal main bar; the original custom Rogue profiles below still
include their separate Stealth/Dance mirrors.

The custom foundations remain separate:

| Profile | Specialization | Layout |
| --- | --- | --- |
| `subburst` | Trickster Subtlety | Six offensive choices, with Dance/Blades/Goremaw sharing one macro |
| `sub` | Trickster Subtlety | Seven offensive choices, with separate Goremaw |
| `sublite` | Trickster Subtlety | Six offensive choices, omitting Goremaw use |
| `assa` | Fatebound Assassination | Eight offensive abilities |
| `blood-sanlayn` | San'layn Blood | Yipyep's Shed Assymetry: separate core attacks, DRW, movement and defensives |
| `blood-deathbringer` | Deathbringer Blood | Same Blood layout, with Reaper's Mark on Bar 2 slot 11 |

The custom Rogue profiles have Standard and Compact layouts. Compact uses manual
Alt modifiers. The custom Blood profiles use Standard with individual spell buttons and the character's
existing talent loadout. The preview starts with the compatible hero profile;
applying it is manual. No trinkets, talents or keys are changed. Unlearned optional
abilities leave their slots untouched. Read [BLOOD-SETUP.txt](TheOneToRuleThemAll/BLOOD-SETUP.txt)
for the exact slots and the San'layn/Deathbringer switch sequence.

## Install and test in WoW

1. Open the latest successful [Test and package run](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml)
   for `astra` and download its addon ZIP artifact. This is a development build
   awaiting Claude's review; it is not the reviewed combined candidate.
2. With WoW closed, extract the `TheOneToRuleThemAll` folder into
   `World of Warcraft/_retail_/Interface/AddOns/`. Keep existing SavedVariables.
3. Select your intended talent loadout. `/tor talents` shows the bundled Method
   references; [TALENTS.txt](TheOneToRuleThemAll/TALENTS.txt) retains the original
   custom Rogue codes. For custom Blood, keep your matching Shed Assymetry loadout.
4. Outside combat, on main-bar page 1 with an empty cursor, open `/tor`.
   Dismount, use the required Druid form and leave Stealth/Shadow Dance on Rogue. Review the main bar
   and every affected Bar 2 and Bar 3 slot before clicking **Apply layout**.
5. After successful setup, use `/reload`, then try the buttons on a training dummy.
   On Blood, check Heart Strike/Vampiric Strike or Marrowrend/Exterminate through
   a proc, plus the separate movement and defensive buttons. On Rogue, check
   the builder in and out of Stealth, burst, and Compact's manual Alt choices.
6. Leave combat and return to the original specialization/loadout, form and
   main-bar page 1. Use `/tor undo` and check that your previous buttons return.

Existing keys keep their bindings, but will cast the new abilities placed in their
slots. Read [START-HERE.txt](TheOneToRuleThemAll/START-HERE.txt) for upgrade details
and [PLAY-GUIDE.txt](TheOneToRuleThemAll/PLAY-GUIDE.txt) for the playing priorities.

Automated tests use mocked WoW APIs and widgets. Actual client rendering,
protected actions and macro casting have **not yet been verified in WoW**.
The checks above remain open until performed in the client. A passing CI run
means the code tests and packaging passed; it does not mark these checks complete.

The optional [Retail test desk](tools/retail_lab/README.md) packages this unchanged
addon with a Windows browser bridge and a companion for observing Apply, reload
and Undo inside the real client. It is a separate ZIP in the same build artifacts.
The desk itself still needs Windows/in-game acceptance; its transport and file
checks do not count as that acceptance.

## Shared development

This repository is the source for changes by Astra, Claude and the owner.
Astra implements on `astra`. Claude reviews that branch and makes its review
changes on `claude`. Only after that round do the reviewed changes enter
`combined`. This includes fixes and follow-up work: Astra does not develop
straight on `combined`. Merge commits preserve both contributions.

This all-class build is on `astra`, awaiting Claude. The earlier combined
merge is a historical baseline; its ancestry alone does not prove approval.

This build combines Astra's key preview and Blood profiles with Claude's clearer
messages, Toy Box support and missing-button handling during Undo. Incomplete
restoration keeps the backup available, whether it follows failed Apply or
explicit Undo. Setup stays blocked until the original buttons are restored.
Unavailable originals are reported so Undo can be retried after recovery.

`combined` is the candidate to try in game after Claude's review round.
Promote it to `main` only after the owner confirms it works there.
Record code checks and actual in-game results separately. CI does not merge branches.

Use Git to fetch source changes. ZIP files are installation builds, so source code
does not need to be passed between chats. A local clone contains the addon in the
`TheOneToRuleThemAll/` subfolder; the repository root itself is not an addon folder.

## Local validation and packaging

Requires Python 3 and a Lua 5.4 shared library. On Ubuntu:

```sh
sudo apt-get update
sudo apt-get install -y liblua5.4-0
python3 tools/generate_standard_profiles.py --check
python3 tools/check_foundation.py
python3 TheOneToRuleThemAll/validation/run_lua_tests.py
python3 tools/package_addon.py
```

GitHub Actions runs those checks on pushes and pull requests and produces the ZIP.
Generated test summaries and ZIPs are not committed. The action-bar and macro
tests are kept beside the addon under `validation/`.

`PLAY-GUIDE.txt` remains the playing-guide source. After editing it, run
`python3 tools/sync_play_guide.py` to update the Lua copy WoW loads. The tests
check that the loaded text matches the source exactly.

Standard class and racial data lives in `tools/class_data/*.json`. Edit those
reviewed records, then run `python3 tools/generate_standard_profiles.py` to
update `StandardData.lua`. The generator checks coverage, spell records and
talent-code specialization headers, and records source-file hashes. `--check`
rejects a stale generated file; it does not test a build in WoW.
`python3 tools/check_foundation.py` checks the recorded hashes of the original
custom modules and source guides, so an accidental rewrite fails validation.

## Simulation scope

The current Rogue policies retain the original fixed-gear study described in
[GEAR-LOCK.txt](TheOneToRuleThemAll/GEAR-LOCK.txt) and the playing guide.
The custom Blood module installs the user's existing custom talent foundation as a
button layout. It has no automatic priorities or coupled casts and makes no
new DPS or survivability claim. Earlier Blood DPS simulations do not validate
tank survivability. Both hero variants retain manual Death Strike, DRW and
defensive timing. The addon does not validate the full talent code.
The all-class Standard layouts are manual button setups with published Method
12.1.5 references. They have not been tested in the live client or optimized
for every race, hero tree and talent combination.
The full research archive remains a separate historical artifact and is not
required to test or package this addon. This repository does not contain its raw
simulation runs.

See [CHANGELOG.txt](TheOneToRuleThemAll/CHANGELOG.txt) for addon changes and
[EXTENDING.txt](TheOneToRuleThemAll/EXTENDING.txt) for class-module requirements.
