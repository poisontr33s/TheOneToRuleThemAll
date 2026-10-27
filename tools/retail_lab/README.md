# Retail-lab

An optional test desk for the actual WoW client. It includes a browser view of
the WoW window and a companion addon that records Apply, reload and Undo using
the real client APIs. No game server, Lua emulator or gameplay bot is included.

On Windows, with Python 3.10+ and WoW already installed:

- Close WoW, extract the lab ZIP and open **Start-Lab.cmd**.
- The launcher finds WoW or asks for its installation folder. It installs the
  exact packaged addon and the test companion, backing up previous addon folders
  under `WTF/TORClientLabBackups`. Existing SavedVariables are kept.
- Start WoW, enable both addons and log in on the intended Rogue or Blood DK.
  Stand safely outside combat and Stealth, with an empty cursor and bar page 1.
- Use the browser desk to open the client test. Begin, Apply, Reload, then Undo
  are separate explicit clicks. Reload again to save the final observation.

The desk is accessible only on this Windows machine through its private local
link. An agent connected to that machine's browser can operate the desk. A cloud
browser on a different machine cannot reach its loopback address. Keep the
launcher window open; Ctrl+C ends access. To reconnect without reinstalling,
run `python lab.py` from this directory. To choose a client explicitly:

```powershell
python lab.py --install --wow-path "D:\World of Warcraft\_retail_"
```

The bridge can capture the selected WoW window, click within a fresh screenshot,
press Escape, or send `/tor`, `/tor guide`, `/tortest` and `/reload`. It cannot run
arbitrary commands or type account credentials. Use windowed or borderless WoW;
capture/input are refused when the target cannot be verified. Do not cover WoW
with another window or run WoW as administrator while the bridge is unelevated.

Read reports in the desk after a reload. Reports are matched to this deployment
and source hash, so old character results cannot approve a new build. The Lua
report is decoded as data, never executed. Native widget creation, spell/item
observations and core-confirmed macro restoration are reported separately.
Rendering quality and actual casting remain unverified until observed in game.

Windows capture/input and the companion's in-game behavior require a real client
session for acceptance. Transport/installer checks do not count as that test.
The regular addon ZIP does not include this optional lab.
