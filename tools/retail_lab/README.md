# Retail-lab

An optional test desk for the actual WoW client. It includes a browser view of
the WoW window and a companion addon that records Apply, reload and Undo using
the real client APIs. No game server, Lua emulator or gameplay bot is included.

On Windows, with Python 3.10+ and WoW already installed:

- Close WoW, extract the lab ZIP and open **Start-Lab.cmd**.
- The launcher finds WoW or asks for its installation folder. It installs the
  exact packaged addon and the test companion, backing up previous addon folders
  under `WTF/TORClientLabBackups`. Existing SavedVariables are kept. Reopening
  the same build reuses its installation; restore it before installing a
  different build.
- Start WoW, enable both addons and log in on the class you want to test.
  Choose its profile in `/tor`, outside combat with an empty cursor and bar
  page 1. Standard Balance requires Moonkin Form, Feral Cat Form, Guardian Bear
  Form and Restoration Druid caster form. Dismount and leave Stealth/Shadow
  Dance on Rogue.
- Use the browser desk to open the client test. Begin, Apply, Reload, then Undo
  are separate explicit clicks. Reload again to save the final observation.

The 0.4.0 Standard profiles cover all 40 specializations. Check the current
form's main buttons, Bar 2 utilities and Bar 3 extras/racials on each character
you test. Return to the same form and loadout before Undo. Custom Rogue
Stealth/Dance mirrors and custom Blood layouts keep their original behavior.
The talent browser only copies Method reference codes; it does not import them.

The desk is accessible only on this Windows machine through its private local
link. An agent connected to that machine's browser can operate the desk. A cloud
browser on a different machine cannot reach its loopback address. Keep the
launcher window open; Ctrl+C ends access. To reconnect without reinstalling,
run `python lab.py` from this directory. To choose a client explicitly:

```powershell
python lab.py --install --wow-path "D:\World of Warcraft\_retail_"
```

## Restore your previous addon folders

Open **Status-Lab.cmd** to check the installation and its backups. This only
reads files and can run while WoW is open. **Restore-Lab.cmd** puts the original
addon folders back after testing; close WoW before running it. If an addon was
not present before the test, its test folder is moved out of AddOns.

These commands are also available from the extracted lab directory:

```powershell
python lab.py --status --wow-path "D:\World of Warcraft\_retail_"
python lab.py --restore --wow-path "D:\World of Warcraft\_retail_"
```

Use the deployment ID reported by status with `--deployment ID` when selecting
a particular installation. Each new installation keeps its own manifest and
original-file hashes under `WTF/TORClientLabBackups`, so extracting a fresh lab
ZIP does not discard its recovery record.

Restore checks both addon folders and their backups before moving anything.
Unknown or changed files, missing backups, and linked folders stop the operation
with an explanation. Nothing is overwritten to force a match. Removed test
folders stay with the deployment's backups; keep that folder until you have
checked the result. If restoration is interrupted, close WoW and run the same
restore command again. Unchanged files allow it to continue from where it stopped.

SavedVariables are left alone. `/tor undo` is separate: it restores action-bar
buttons inside WoW. Use it, then reload or log out to save the result, before
closing WoW and restoring the addon folders if you want both changes reversed.

Older lab installations do not record hashes of the original folders. Automatic
restore refuses those installations; their backups need manual inspection and
restoration with WoW closed. Do not reinstall over them to create a new manifest.

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
One successful character does not approve all classes or talent combinations.
This Astra development package awaits Claude's review before entering combined.
Promote combined to main only after the owner accepts its in-game results.

Windows capture/input and the companion's in-game behavior require a real client
session for acceptance. Transport/installer checks do not count as that test.
The regular addon ZIP does not include this optional lab.
