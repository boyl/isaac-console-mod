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
    publish_script = ROOT / "tools" / "publish-workshop.ps1"
    parse_command = (
        "$errors=$null; "
        f"[void][System.Management.Automation.Language.Parser]::ParseFile('{publish_script}',[ref]$null,[ref]$errors); "
        "if($errors.Count){$errors | ForEach-Object { Write-Error $_ }; exit 1}"
    )
    run(["pwsh", "-NoLogo", "-NoProfile", "-Command", parse_command])

    publish_source = publish_script.read_text(encoding="utf-8-sig")
    assert publish_source.count("Click-Relative -Window $main -X 0.26 -Y 0.16") == 1
    assert "if (-not $Publish)" in publish_source
    assert "之后只轮询远端，不重复点击" in publish_source

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
