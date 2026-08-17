"""Static validation for the self-contained Chinese Workshop package."""

from __future__ import annotations

import hashlib
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image


DISPLAY_VERSION = "2.5.15"
METADATA_VERSION = "2.5.15"
WORKSHOP_ID = "3776882944"
EXPECTED_PREVIEW_SHA256 = "E187031C27C032EB11DBD2943BC75A4067E2FEA250A155B8DB3B08F06CFDB7C9"

REQUIRED_FILES = {
    "main.lua",
    "metadata.xml",
    "preview.png",
    "FONT-LICENSE-OFL.txt",
    "THIRD-PARTY-DATA.md",
    "THIRD-PARTY-FONTS.md",
    "resources/font/fusion/10.fnt",
    "resources/font/fusion/10_0.png",
    "resources/font/fusion/12.fnt",
    "resources/font/fusion/12_0.png",
    "resources/font/fusion/12_1.png",
    "resources/font/fusion/LICENSE-OFL",
    "resources/font/isaac_console_fusion10.fnt",
    "resources/font/isaac_console_fusion10_0.png",
    "resources/font/isaac_console_fusion12.fnt",
    "resources/font/isaac_console_fusion12_0.png",
    "resources/font/isaac_console_fusion12_1.png",
    "resources/font/isaac_console_zh.fnt",
    "resources/font/isaac_console_zh_0.png",
    "resources/gfx/ui/isaac_console_pixel.anm2",
    "resources/gfx/ui/isaac_console_pixel.png",
    "scripts/data.lua",
    "scripts/command_specs.lua",
    "scripts/command_catalog.lua",
    "scripts/official_objects.lua",
    "scripts/object_pinyin_aliases.lua",
    "scripts/pinyin_aliases.lua",
    "scripts/search_aliases.lua",
}


def fail(message: str) -> None:
    raise AssertionError(message)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_workshop_mod_zh.py <mod-dir>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve()
    package_files = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file()
    }
    missing = sorted(REQUIRED_FILES - package_files)
    unexpected = sorted(package_files - REQUIRED_FILES)
    if missing:
        fail(f"missing files: {missing}")
    if unexpected:
        fail(f"unrelated files found in Workshop package: {unexpected}")
    forbidden = {".exe", ".dll", ".hta", ".ps1", ".cmd", ".bat"}
    offenders = sorted(path.as_posix() for path in root.rglob("*") if path.suffix.lower() in forbidden)
    if offenders:
        fail(f"external executable/script found: {offenders}")

    metadata = ET.parse(root / "metadata.xml").getroot()
    expected_metadata = {
        "name": "Isaac Chinese Console",
        "directory": "isaac_chinese_console_workshop",
        "id": WORKSHOP_ID,
        "version": METADATA_VERSION,
        "visibility": "Public",
    }
    for field, expected in expected_metadata.items():
        if (metadata.findtext(field) or "").strip() != expected:
            fail(f"metadata {field} mismatch")

    main_lua = (root / "main.lua").read_text(encoding="utf-8")
    checks = {
        "Chinese Mod registration": 'RegisterMod("Isaac Chinese Console", 1)',
        "display version": f'local VERSION = "{DISPLAY_VERSION}"',
        "named controller Y details": 'controllerButton("BUTTON_Y")',
        "semantic details paging": "function Presentation.advanceDetails(entries)",
        "contextual device help": "function Presentation.entryHintCandidates(entry, isFavorite, effectPageCount)",
        "semantic Toast layout": "function Presentation.toastLines(toast, width)",
        "semantic Toast colors": "Presentation.toastColors[kind]",
        "measured layout": "local function computeLayout(screenWidth, screenHeight)",
        "native pause detection": "Game():IsPaused()",
        "favorite state": "function FavoriteModel.finalizeOrder(forceAvailableCatalog)",
        "optional MCM command-close setting": "普通命令执行后关闭界面: ",
    }
    for label, needle in checks.items():
        if needle not in main_lua:
            fail(f"missing implementation: {label}")
    for forbidden_source in ('controllerButton("BUTTON_Y",', "IS_REPENTOGON"):
        if forbidden_source in main_lua:
            fail(f"runtime-specific controller behavior remains: {forbidden_source}")

    animation_root = ET.parse(root / "resources/gfx/ui/isaac_console_pixel.anm2").getroot()
    animation_info = animation_root.find("Info")
    if animation_info is None or animation_info.get("Version") != "31":
        fail("UI ANM2 must use the Repentance-compatible Version 31 structure")
    with Image.open(root / "resources/gfx/ui/isaac_console_pixel.png") as image:
        if image.size != (1, 1):
            fail("UI pixel texture must be 1x1")

    preview = root / "preview.png"
    preview_sha256 = hashlib.sha256(preview.read_bytes()).hexdigest().upper()
    if preview_sha256 != EXPECTED_PREVIEW_SHA256:
        fail("Workshop preview differs from the verified remote preview")
    if preview.stat().st_size > 1_000_000:
        fail("Workshop preview exceeds 1 MB")

    print("validation ok")
    print(f"identity: Isaac Chinese Console {DISPLAY_VERSION}; workshop_id={WORKSHOP_ID}")
    print(f"package: {len(package_files)} allowlisted files; preview={preview_sha256}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
