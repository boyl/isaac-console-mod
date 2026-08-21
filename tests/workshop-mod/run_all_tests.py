"""Run the complete bilingual source regression gate."""

from __future__ import annotations

import subprocess
import sys
import json
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
    assert "Invoke-WorkshopRelease.ps1" in publish_source
    assert "GAME_MODDING_TOOLKIT_ROOT" in publish_source
    assert "if($Publish)" in publish_source
    assert "arguments.Publish=$true" in publish_source
    assert "Click-GMTIsaacRelative" not in publish_source

    release_profile = json.loads(
        (ROOT / "tools" / "workshop-release-profile.json").read_text(encoding="utf-8-sig")
    )
    assert release_profile["schemaVersion"] == 1
    assert release_profile["adapter"]["id"] == "isaac-mod-uploader"
    assert release_profile["policies"] == {
        "requireCleanPushedHead": True,
        "preserveRemotePreview": True,
    }
    assert {item["name"] for item in release_profile["variants"]} == {"zh", "en"}
    lock = json.loads(
        (ROOT / "tools" / "game-modding-toolkit.lock.json").read_text(encoding="utf-8-sig")
    )
    assert lock["repository"] == "https://github.com/boyl/game-modding-toolkit"
    assert len(lock["verifiedCommit"]) == 40

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
