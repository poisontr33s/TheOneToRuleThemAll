# TheOneToRuleThemAll

WoW Retail action-bar setup. The complete Method.gg Mythic+ version is on
[`astra`](https://github.com/poisontr33s/TheOneToRuleThemAll/tree/astra).

[Download the current build](https://github.com/poisontr33s/TheOneToRuleThemAll/actions/workflows/ci.yml?query=branch%3Aastra) · [Current setup instructions](https://github.com/poisontr33s/TheOneToRuleThemAll/blob/astra/TheOneToRuleThemAll/START-HERE.txt)

Main still contains the earlier Rogue version. The new class layouts move
here after acceptance in WoW. Claude's later review is separate.

Open `/tor` outside combat and Stealth. Review slots before **Apply layout**,
then `/reload`. Use `/tor undo` to restore the previous buttons.
Keep SavedVariables when replacing the addon folder.

[Working rules](AGENTS.md) · [Gem and enchant template](tools/class_data/gear.json)

Keep changes small and text short. Test actual behavior in WoW;
passing local checks alone does not establish that it works in the client.

For the source on this branch, install Python 3 and a Lua 5.4 shared library:
```sh
python3 TheOneToRuleThemAll/validation/run_lua_tests.py
python3 tools/package_addon.py
```
