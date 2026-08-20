"""Run the complete bilingual source regression gate."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TEST_ROOT = Path(__file__).resolve().parent


def run(arguments: list[str]) -> None:
    print("+", " ".join(arguments), flush=True)
    subprocess.run(arguments, cwd=ROOT, check=True)


def main() -> int:
    profiles = (
        ("workshop-mod", "Isaac Chinese Console", "2.5.17"),
        ("workshop-mod-en", "Console UI", "2.5.4-en.12"),
    )
    for directory, mod_name, version in profiles:
        run([
            sys.executable,
            str(TEST_ROOT / "run_mock_game_tests.py"),
            str(ROOT / directory),
            mod_name,
            version,
        ])
        run([
            sys.executable,
            str(TEST_ROOT / "run_cold_start_tests.py"),
            str(ROOT / directory),
            mod_name,
        ])
    print("bilingual source gate ok: 178 Mock + 8 cold-start/lifecycle scenarios")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
