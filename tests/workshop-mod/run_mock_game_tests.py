"""Run the real Workshop Lua entry point against the deterministic mock game."""

from __future__ import annotations

import ctypes
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MOD_ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "workshop-mod-en"
HARNESS = Path(__file__).with_name("mock_game_harness.lua")
EXPECTED_NAME = sys.argv[2] if len(sys.argv) > 2 else "Console UI"
EXPECTED_VERSION = sys.argv[3] if len(sys.argv) > 3 else "2.5.4-en.5"
LUA_DLL_CANDIDATES = [
    Path(r"C:\Program Files\obs-studio\bin\64bit\lua51.dll"),
    Path(r"C:\Program Files\bililive\livehime\7.54.0.10521\lua51.dll"),
]


def lua_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return lua_string(str(value))


def load_lua() -> tuple[ctypes.CDLL, Path]:
    errors: list[str] = []
    for path in LUA_DLL_CANDIDATES:
        if not path.is_file():
            continue
        try:
            dll = ctypes.CDLL(str(path))
            return dll, path
        except OSError as exc:
            errors.append(f"{path}: {exc}")
    raise RuntimeError("no compatible 64-bit Lua runtime found\n" + "\n".join(errors))


def configure_lua(dll: ctypes.CDLL) -> None:
    dll.luaL_newstate.restype = ctypes.c_void_p
    dll.luaL_openlibs.argtypes = [ctypes.c_void_p]
    dll.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
    dll.luaL_loadbuffer.restype = ctypes.c_int
    dll.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    dll.lua_pcall.restype = ctypes.c_int
    dll.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
    dll.lua_tolstring.restype = ctypes.c_char_p
    dll.lua_close.argtypes = [ctypes.c_void_p]


def error_text(dll: ctypes.CDLL, state: int) -> str:
    size = ctypes.c_size_t()
    raw = dll.lua_tolstring(state, -1, ctypes.byref(size))
    if not raw:
        return "unknown Lua error"
    return ctypes.string_at(raw, size.value).decode("utf-8", errors="replace")


def run_scenario(dll: ctypes.CDLL, config: dict[str, object]) -> None:
    fields = ", ".join(f"{key} = {lua_value(value)}" for key, value in config.items())
    source = (
        f"MOD_ROOT = {lua_string(MOD_ROOT.as_posix())}\n"
        f"TEST_CONFIG = {{ {fields} }}\n"
        f"dofile({lua_string(HARNESS.as_posix())})\n"
    ).encode("utf-8")
    state = dll.luaL_newstate()
    if not state:
        raise RuntimeError("luaL_newstate failed")
    try:
        dll.luaL_openlibs(state)
        status = dll.luaL_loadbuffer(state, source, len(source), b"mock-game-wrapper")
        if status:
            raise AssertionError(error_text(dll, state))
        status = dll.lua_pcall(state, 0, 0, 0)
        if status:
            raise AssertionError(error_text(dll, state))
    finally:
        dll.lua_close(state)


def scenarios() -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    search_cases = (
        ("sacred heart", "giveitem c182"),
        ("sacred", "giveitem c182"),
        ("brim", "giveitem c118"),
        ("260", "giveitem c260"),
    )
    for rep_plus in (False, True):
        for eid in (False, True):
            for query, expected_command in search_cases:
                runtime = "Repentance+" if rep_plus else "Repentance"
                dependency = "EID-on" if eid else "EID-off"
                result.append(
                    {
                        "scenario": "search",
                        "label": f"search {runtime} {dependency} {query}",
                        "repPlus": rep_plus,
                        "eid": eid,
                        "query": query,
                        "expectedCommand": expected_command,
                    }
                )
    result.extend(
        [
            {"scenario": "favorite", "label": "dynamic favorite transaction", "repPlus": True, "eid": True},
            {
                "scenario": "official_objects",
                "label": "1056 official objects and typed favorites EID-off",
                "repPlus": False,
                "eid": False,
            },
            {
                "scenario": "official_objects",
                "label": "1056 official objects and typed favorites EID-on",
                "repPlus": True,
                "eid": True,
            },
            {
                "scenario": "idle_restarts",
                "label": "20 idle R restarts without catalog or exit save",
                "repPlus": False,
                "eid": False,
            },
            {"scenario": "history20", "label": "20 consecutive games", "repPlus": True, "eid": False},
            {"scenario": "oversized", "label": "oversized save compaction", "repPlus": False, "eid": False},
            {"scenario": "upgrade", "label": "v2.4.2 save upgrade", "repPlus": False, "eid": False},
            {
                "scenario": "save_failure",
                "label": "favorite rollback on SaveData failure",
                "repPlus": True,
                "eid": False,
                "saveFail": True,
            },
            {
                "scenario": "load_failure",
                "label": "protected LoadData failure",
                "repPlus": True,
                "eid": False,
                "loadFail": True,
            },
            {"scenario": "interactions", "label": "keyboard mouse controller layout", "repPlus": True, "eid": True},
            {
                "scenario": "stage_safety",
                "label": "normal and Greed mode-specific stage whitelists",
                "repPlus": True,
                "eid": False,
                "greedMode": True,
            },
            {
                "scenario": "controller",
                "label": "Repentance accepted controller path remains unchanged",
                "repPlus": False,
                "eid": True,
                "controllerIndex": 1,
                "actionsUnavailable": True,
            },
            {
                "scenario": "controller",
                "label": "Repentance+ A/B actions and raw-X fallback survive legacy Controller overwrites",
                "repPlus": True,
                "eid": True,
                "controllerIndex": 1,
                "physicalConfirmButton": 5,
                "physicalFavoriteButton": 4,
                "physicalBackButton": 6,
                "menuTabActionUnavailable": True,
            },
            {
                "scenario": "controller",
                "label": "REPENTOGON A confirm outranks raw-4 favorite and X MENUTAB favorites",
                "repPlus": True,
                "eid": True,
                "controllerIndex": 2,
                "physicalConfirmButton": 4,
                "physicalFavoriteButton": 6,
                "physicalBackButton": 5,
            },
            {
                "scenario": "cold_start_focus",
                "label": "empty Featured keyboard first-open focus and semantic D-pad",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 2,
            },
            {
                "scenario": "cold_start_focus",
                "label": "empty Featured L3 first-open focus and semantic D-pad",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 2,
                "openWithController": True,
            },
            {
                "scenario": "cold_start_focus",
                "label": "saved favorite remains the first-open view",
                "repPlus": False,
                "eid": False,
                "controllerIndex": 1,
                "initialFavorite": True,
            },
            {"scenario": "eid_overlay", "label": "language-specific EID overlay ownership", "repPlus": True, "eid": True},
            {"scenario": "toast_restart", "label": "R restart and Rerun frame resets clear transient Toasts", "repPlus": True, "eid": False},
            {
                "scenario": "run_boundary_controller",
                "label": "R Rewind and Rerun release controller lifecycle state",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 1,
                "playerControllerIndexes": [1],
            },
            {"scenario": "ctrl_a_isolation", "label": "focused Ctrl+A isolation for search and command", "repPlus": True, "eid": False},
            {
                "scenario": "command_editor",
                "label": "manual command replace clear click and history draft",
                "repPlus": True,
                "eid": False,
            },
            {
                "scenario": "editable_text_confirm_collision",
                "label": "Repentance text keys outrank menu confirm",
                "repPlus": False,
                "eid": False,
                "controllerIndex": 0,
            },
            {
                "scenario": "editable_text_confirm_collision",
                "label": "Repentance+ text keys outrank menu confirm",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 2,
            },
            {
                "scenario": "editable_text_confirm_collision",
                "label": "REPENTOGON text keys outrank menu confirm",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 3,
            },
            {
                "scenario": "pause_suspension",
                "label": "native pause suspends overlay and blocks resume penetration",
                "repPlus": True,
                "eid": True,
            },
            {
                "scenario": "assigned_controller_isolation",
                "label": "unassigned controller cannot navigate execute or join",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 1,
                "unassignedControllerIndex": 3,
                "playerControllerIndexes": [1],
            },
            {
                "scenario": "closing_input_lease",
                "label": "closing inputs cannot join a second player or block run transitions",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 1,
                "playerControllerIndexes": [1],
            },
            {
                "scenario": "controller_repeat",
                "label": "Repentance raw LB/RB identity controller 0",
                "repPlus": False,
                "eid": False,
                "controllerIndex": 0,
                "actionsUnavailable": True,
            },
            {
                "scenario": "controller_repeat",
                "label": "Repentance LB/RB outrank ambiguous menu-tab actions controller 2",
                "repPlus": False,
                "eid": False,
                "controllerIndex": 2,
            },
            {
                "scenario": "controller_repeat",
                "label": "Repentance+ raw LB/RB identity controller 1",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 1,
                "actionsUnavailable": True,
            },
            {
                "scenario": "controller_repeat",
                "label": "Repentance+ LB/RB outrank ambiguous menu-tab actions controller 3",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 3,
            },
            {
                "scenario": "controller_repeat",
                "label": "REPENTOGON LB/RB outrank ambiguous menu-tab actions controller 0",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 0,
            },
            {
                "scenario": "controller_repeat",
                "label": "REPENTOGON LB/RB outrank ambiguous menu-tab actions controller 3",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 3,
            },
            {
                "scenario": "controller_paging",
                "label": "Repentance raw LT/RT focus paging controller 0",
                "repPlus": False,
                "eid": False,
                "controllerIndex": 0,
                "actionsUnavailable": True,
                "screenWidth": 455,
                "screenHeight": 256,
            },
            {
                "scenario": "controller_paging",
                "label": "Repentance LT/RT raw identity with menu-tab noise controller 2",
                "repPlus": False,
                "eid": False,
                "controllerIndex": 2,
                "screenWidth": 1280,
                "screenHeight": 720,
            },
            {
                "scenario": "controller_paging",
                "label": "Repentance+ raw LT/RT focus paging controller 1",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 1,
                "actionsUnavailable": True,
                "screenWidth": 2048,
                "screenHeight": 1152,
            },
            {
                "scenario": "controller_paging",
                "label": "Repentance+ LT/RT raw identity with menu-tab noise controller 3",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 3,
            },
            {
                "scenario": "controller_paging",
                "label": "REPENTOGON LT/RT raw identity with menu-tab noise controller 0",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 0,
            },
            {
                "scenario": "controller_paging",
                "label": "REPENTOGON LT/RT raw identity with menu-tab noise controller 3",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 3,
            },
            {
                "scenario": "mcm_settings_254",
                "label": "MCM startup hint and controller favorite persistence rollback",
                "repPlus": True,
                "eid": False,
                "mcm": True,
            },
            {
                "scenario": "official_immediate_grant",
                "label": "ItemConfig grants reject misleading removal without manual ID flags",
                "repPlus": True,
                "eid": False,
                "controllerIndex": 1,
                "physicalConfirmButton": 5,
                "physicalFavoriteButton": 4,
                "physicalBackButton": 6,
            },
            {
                "scenario": "queue_invariant",
                "label": "queue progress clamp and single completion",
                "repPlus": False,
                "eid": False,
                "controllerIndex": 3,
            },
            {
                "scenario": "command_feedback_duration",
                "label": "success and failure command feedback durations",
                "repPlus": True,
                "eid": False,
            },
            {
                "scenario": "measured_footer_stars",
                "label": "455x256 complete footer and favorite markers",
                "repPlus": False,
                "eid": False,
                "screenWidth": 455,
                "screenHeight": 256,
            },
            {
                "scenario": "measured_footer_stars",
                "label": "1280x720 command detail layout",
                "repPlus": False,
                "eid": False,
                "screenWidth": 1280,
                "screenHeight": 720,
            },
            {
                "scenario": "measured_footer_stars",
                "label": "2048x1152 command detail layout",
                "repPlus": False,
                "eid": False,
                "screenWidth": 2048,
                "screenHeight": 1152,
            },
            {
                "scenario": "category_description_matrix",
                "label": "455x256 all category search and Greed descriptions",
                "repPlus": True,
                "eid": False,
                "screenWidth": 455,
                "screenHeight": 256,
            },
            {
                "scenario": "category_description_matrix",
                "label": "1280x720 progressive footer contexts",
                "repPlus": False,
                "eid": False,
                "screenWidth": 1280,
                "screenHeight": 720,
            },
            {
                "scenario": "category_description_matrix",
                "label": "2048x1152 progressive footer contexts",
                "repPlus": True,
                "eid": False,
                "screenWidth": 2048,
                "screenHeight": 1152,
            },
            {
                "scenario": "font_fallback",
                "label": "language-specific Repentance+ font route",
                "repPlus": True,
                "eid": False,
                "fontMode": "normal",
            },
            {
                "scenario": "font_failure",
                "label": "English font failure page",
                "repPlus": False,
                "eid": False,
                "fontMode": "all_fail",
            },
            {
                "scenario": "mcm_keybind",
                "label": "optional MCM custom open key and rollback",
                "repPlus": True,
                "eid": False,
                "mcm": True,
            },
        ]
    )
    return result


def main() -> int:
    if not MOD_ROOT.is_dir() or not HARNESS.is_file():
        print("mock test inputs are missing", file=sys.stderr)
        return 2
    dll, dll_path = load_lua()
    configure_lua(dll)
    cases = scenarios()
    common = {
        "expectedModName": EXPECTED_NAME,
        "expectedVersion": EXPECTED_VERSION,
        "language": "zh" if EXPECTED_NAME == "Isaac Chinese Console" else "en",
    }
    for index, config in enumerate(cases, 1):
        label = str(config["label"])
        print(f"[{index:02d}/{len(cases):02d}] {label}")
        complete = dict(common)
        complete.update(config)
        run_scenario(dll, complete)
    print(f"mock integration ok: {len(cases)} scenarios")
    print(f"lua runtime: {dll_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
