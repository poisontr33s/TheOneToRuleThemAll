# TheOneToRuleThemAll

**The One To Rule Them All** sets up action bars for every WoW Retail class,
using Method.gg's published Mythic+ talent builds as the standard.
Development version: **0.4.1-astra**, Retail **12.1.5**.

[![Test and package](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml/badge.svg?branch=astra)](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml?query=branch%3Aastra)

Open `/tor`, copy a build from **Mythic+ talents**, import it in WoW's talent
window, then preview and apply the buttons. Healers can select **Mouseover**.
Use `/tor undo` to restore the previous buttons. Your keys and gear stay as they are.

## The standard

- Method's latest verified Mythic+ builds provide the talent codes for each spec.
- Published recommendations come first when the guide is clear. Where Method
  offers alternatives, they stay available under their published names.
- Fixed positions: core abilities on the main bar, utility on Bar 2,
  extra abilities on Bar 3, and active racials in Bar 3 slots 10–12.
- Only learned abilities are placed. Missing optional talents leave their slots alone.
- Buttons use native spells. Healer Mouseover creates ordinary localized macros;
  every action still requires the player's key or click.

References are bundled with the addon. They show the guide's patch, date and link;
there is no live website fetch inside WoW. Source updates are checked and shipped
as addon updates. The addon does not import talents or verify your entire talent tree.

Custom Rogue and Blood profiles, playing guides and simulation notes are preserved
unchanged in the repository. They are no longer loaded or included in the install
ZIP. They do not determine the standard or require further simulation work.
Existing backups remain available through Undo.

## Install and try in WoW

Download the addon ZIP from the latest successful
[Test and package run for astra](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml?query=branch%3Aastra).
It awaits Claude's review and is not the accepted combined release.

With WoW closed, replace `TheOneToRuleThemAll` under
`World of Warcraft/_retail_/Interface/AddOns/`. Keep SavedVariables.

Select your talents, dismount, leave combat and Stealth/Shadow Dance, and return
to the normal main bar. For Druid use Moonkin, Cat, Bear or caster form according
to your spec. Open `/tor`, review the affected slots and click **Apply layout**.
Only that form's main bar changes. Rogue's Stealth bar stays as it was.

Use `/reload`, then try the buttons, temporary spell replacements and any
mouseover macros on the actual character. Leave combat and use `/tor undo`
in the same spec, talent loadout and form. Check that the original buttons return.

Code checks pass only for the behavior they exercise. **Rendering, protected
actions and casting still need validation in the actual WoW client.**
See [START-HERE.txt](TheOneToRuleThemAll/START-HERE.txt) for setup and recovery.

The optional [Retail Lab](tools/retail_lab/README.md) observes Apply, reload and
Undo through a local Windows test desk. Its separate ZIP includes status and
restoration commands. It also awaits Windows and in-game acceptance.

## Development

Astra implements on `astra`. Claude reviews it and contributes on `claude`.
Reviewed work enters `combined`. The owner tries that version in WoW before
it can enter `main`. Fixes follow the same order.

Keep code small and readable, and player text short. Use Method and Blizzard
sources for behavior; passing mocks is not evidence that a macro works in WoW.
Do not introduce new builds, performance rankings or simulation requirements.

Class and racial records live in `tools/class_data/*.json`. Keep Method's exact
codes, names, guide dates and source links. Check the current guide when updating;
if recommendations conflict, retain its alternatives without inventing a winner.
The generator ships only dungeon references and records source hashes.

With Python 3 and a Lua 5.4 shared library installed:

```sh
python3 tools/generate_standard_profiles.py --check
python3 tools/check_foundation.py
python3 TheOneToRuleThemAll/validation/run_lua_tests.py
python3 -m unittest discover -s tools/retail_lab -p 'test_*.py'
python3 tools/package_addon.py
python3 tools/package_retail_lab.py
```

After changing class records, run `python3 tools/generate_standard_profiles.py`.
Archived custom modules remain test fixtures for existing placement and recovery
regressions; production tests also load the actual TOC without those modules.
The foundation check protects the original files without making their research
part of the addon. Do not refresh those hashes to conceal an unintended edit.

See [EXTENDING.txt](TheOneToRuleThemAll/EXTENDING.txt) for the code contract and
[CHANGELOG.txt](TheOneToRuleThemAll/CHANGELOG.txt) for changes.
