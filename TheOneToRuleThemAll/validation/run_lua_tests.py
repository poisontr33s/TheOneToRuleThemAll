import ctypes
import ctypes.util
import os
import json
from pathlib import Path
base = Path(__file__).resolve().parent
addon_dir = Path(os.environ.setdefault("TOR_ADDON_DIR", str(base.parent)))
summary_path = base / "validation-summary.json"
# Never leave an earlier successful result behind if this run cannot start.
summary_path.unlink(missing_ok=True)
version = next((line.partition(":")[2].strip()
                for line in (addon_dir / "TheOneToRuleThemAll.toc").read_text().splitlines()
                if line.startswith("## Version:")), None)
if not version:
    raise SystemExit("The addon TOC has no Version field; tests were not run.")
library_name = ctypes.util.find_library("lua5.4") or ctypes.util.find_library("lua54") or "liblua5.4.so.0"
try:
    lib = ctypes.CDLL(library_name)
except OSError as error:
    raise SystemExit("Lua 5.4 shared library is required. On Ubuntu, install liblua5.4-0. "
                     f"Could not load {library_name}: {error}") from error
lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
lib.luaL_loadfilex.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_char_p]
lib.luaL_loadfilex.restype=ctypes.c_int
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p]
lib.lua_pcallk.restype=ctypes.c_int
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.POINTER(ctypes.c_size_t)]
lib.lua_tolstring.restype=ctypes.c_char_p
lib.lua_close.argtypes=[ctypes.c_void_p]
lib.lua_getglobal.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
lib.lua_getglobal.restype=ctypes.c_int
lib.lua_tointegerx.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.POINTER(ctypes.c_int)]
lib.lua_tointegerx.restype=ctypes.c_longlong
state=lib.luaL_newstate()
if not state:
    raise SystemExit("Could not create a Lua 5.4 state; tests were not run.")
lib.luaL_openlibs(state)
suite=base / "test_setup.lua"
rc=lib.luaL_loadfilex(state,str(suite).encode(),None)
if not rc: rc=lib.lua_pcallk(state,0,-1,0,0,None)
if rc:
    print(lib.lua_tolstring(state,-1,None).decode())
lib.lua_getglobal(state,b"TOR_TEST_TOTAL")
total_is_integer=ctypes.c_int()
total=lib.lua_tointegerx(state,-1,ctypes.byref(total_is_integer))
lib.lua_getglobal(state,b"TOR_TEST_FAILED")
failed_is_integer=ctypes.c_int()
failed=lib.lua_tointegerx(state,-1,ctypes.byref(failed_is_integer))
# Both globals are written at the end of the Lua suite. Missing counts, zero
# tests and Lua errors must never produce a green CI result.
valid_counts=bool(total_is_integer.value and failed_is_integer.value and total > 0 and 0 <= failed <= total)
suite_completed=rc == 0 and valid_counts
exit_ok=suite_completed and failed == 0
summary_path.write_text(json.dumps({
    "addon": "The One To Rule Them All", "version": version,
    "tests": total, "passed": total-failed, "failed": failed,
    "suite_completed": suite_completed, "exit_ok": exit_ok,
    "runtime": "Lua 5.4 mock WoW APIs", "live_client_tested": False,
    "scope": "Action-bar guards, macro strings, placement, backup/restore, saved-loadout identity, failure recovery, read-only inspection and native-panel callback tests with mocked widgets. No live rendering, protected-action or casting validation."
}, indent=2) + "\n")
lib.lua_close(state)
if not exit_ok:
    print("Validation failed: Lua must finish successfully and report at least one test with zero failures.")
raise SystemExit(0 if exit_ok else 1)
