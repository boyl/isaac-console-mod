"""Run language-neutral first-open controller regression scenarios."""

from __future__ import annotations

import sys
from pathlib import Path

import run_mock_game_tests as suite


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: run_cold_start_tests.py <mod-dir> <RegisterMod-name>", file=sys.stderr)
        return 2

    mod_root = Path(sys.argv[1]).resolve()
    expected_name = sys.argv[2]
    if not mod_root.is_dir():
        print(f"mod directory is missing: {mod_root}", file=sys.stderr)
        return 2

    suite.MOD_ROOT = mod_root
    dll, dll_path = suite.load_lua()
    suite.configure_lua(dll)
    cases = [
        {
            "scenario": "cold_start_focus",
            "label": "empty Featured keyboard first-open focus and semantic D-pad",
            "repPlus": True,
            "eid": False,
            "controllerIndex": 2,
            "expectedModName": expected_name,
        },
        {
            "scenario": "cold_start_focus",
            "label": "empty Featured L3 first-open focus and semantic D-pad",
            "repPlus": True,
            "eid": False,
            "controllerIndex": 2,
            "openWithController": True,
            "expectedModName": expected_name,
        },
        {
            "scenario": "cold_start_focus",
            "label": "saved favorite remains the first-open view",
            "repPlus": True,
            "eid": False,
            "controllerIndex": 2,
            "initialFavorite": True,
            "expectedModName": expected_name,
        },
        {
            "scenario": "toast_restart",
            "label": "R restart and Rerun frame resets clear transient Toasts",
            "repPlus": True,
            "eid": False,
            "expectedModName": expected_name,
        },
    ]
    for index, config in enumerate(cases, 1):
        print(f"[{index:02d}/{len(cases):02d}] {config['label']}")
        suite.run_scenario(dll, config)
    print(f"cold-start and lifecycle integration ok: {len(cases)} scenarios")
    print(f"lua runtime: {dll_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
