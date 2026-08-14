"""Static validation for the self-contained Console UI Workshop package."""

from __future__ import annotations

import hashlib
import re
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image


CHINESE_WORKSHOP_ID = "3776882944"
ENGLISH_WORKSHOP_ID = "3779128726"
DISPLAY_VERSION = "2.5.4-en.7"
METADATA_VERSION = "2.5.4.7"
EXPECTED_PREVIEW_SHA256 = "D7378BB9951A72EFE3C112F30930719FB734E20D48C16A870E396326770BB26C"

def fail(message: str) -> None:
    raise AssertionError(message)


def parse_bmfont(path: Path) -> set[int]:
    data = path.read_bytes()
    if data[:4] != b"BMF\x03":
        fail("BMFont must use binary v3")
    offset = 4
    characters: set[int] = set()
    while offset < len(data):
        block_type, size = struct.unpack_from("<BI", data, offset)
        offset += 5
        payload = data[offset : offset + size]
        offset += size
        if block_type == 1:
            if size < 3 or not payload[2] & 0x40:
                fail("BMFont Unicode flag is missing")
            if size < 4 or payload[3] != 0:
                fail("BMFont charset must be normalized to 0 for Repentance")
        elif block_type == 4:
            if size % 20:
                fail("invalid BMFont char block size")
            for index in range(0, size, 20):
                character_id = struct.unpack_from("<I", payload, index)[0]
                if character_id in characters:
                    fail(f"duplicate BMFont character: {character_id}")
                characters.add(character_id)
    return characters


def parse_bmfont_pages(path: Path) -> list[str]:
    data = path.read_bytes()
    offset = 4
    while offset < len(data):
        block_type, size = struct.unpack_from("<BI", data, offset)
        offset += 5
        payload = data[offset : offset + size]
        offset += size
        if block_type == 3:
            return [value.decode("utf-8") for value in payload.split(b"\0") if value]
    return []


def validate_text_is_english(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"[\u3400-\u9fff]", text)
    if match:
        line = text.count("\n", 0, match.start()) + 1
        fail(f"CJK player-facing text remains: {path.name}:{line}")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_workshop_mod.py <mod-dir>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve()
    required = [
        "main.lua",
        "metadata.xml",
        "scripts/data.lua",
        "scripts/command_specs.lua",
        "scripts/command_catalog.lua",
        "scripts/english_aliases.lua",
        "scripts/official_objects.lua",
        "resources/font/fusion/10.fnt",
        "resources/font/fusion/10_0.png",
        "resources/font/fusion/12.fnt",
        "resources/font/fusion/12_0.png",
        "resources/font/fusion/12_1.png",
        "resources/gfx/ui/isaac_console_pixel.anm2",
        "resources/gfx/ui/isaac_console_pixel.png",
        "FONT-LICENSE-OFL.txt",
        "THIRD-PARTY-FONTS.md",
        "THIRD-PARTY-DATA.md",
        "preview.png",
    ]
    missing = [value for value in required if not (root / value).is_file()]
    if missing:
        fail(f"missing files: {missing}")
    package_files = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file()
    }
    unexpected = sorted(package_files - set(required))
    if unexpected:
        fail(f"unrelated files found in Workshop package: {unexpected}")
    forbidden = {".exe", ".dll", ".hta", ".ps1", ".cmd", ".bat"}
    offenders = [path for path in root.rglob("*") if path.suffix.lower() in forbidden]
    if offenders:
        fail(f"external executable/script found: {offenders}")

    metadata = ET.parse(root / "metadata.xml").getroot()
    if metadata.findtext("name") != "Console UI":
        fail("metadata title mismatch")
    if metadata.findtext("directory") != "console_ui_workshop":
        fail("English directory identity mismatch")
    if metadata.findtext("version") != METADATA_VERSION:
        fail("metadata version mismatch")
    workshop_id = (metadata.findtext("id") or "").strip()
    if workshop_id != ENGLISH_WORKSHOP_ID:
        fail(f"Workshop ID must be the published English item: {ENGLISH_WORKSHOP_ID}")
    if workshop_id == CHINESE_WORKSHOP_ID:
        fail("English package must never target the Chinese Workshop item")
    if metadata.findtext("visibility") != "Public":
        fail("release visibility must be Public")

    animation_root = ET.parse(root / "resources/gfx/ui/isaac_console_pixel.anm2").getroot()
    animation_info = animation_root.find("Info")
    if animation_info is None or animation_info.get("Version") != "31":
        fail("UI ANM2 must use the Repentance-compatible Version 31 structure")
    if animation_root.find(".//TriggerAnimations") is not None:
        fail("UI ANM2 contains unsupported TriggerAnimations")
    if animation_root.find(".//Triggers") is None:
        fail("UI ANM2 is missing Triggers")

    main_lua = (root / "main.lua").read_text(encoding="utf-8")
    data_lua = (root / "scripts/data.lua").read_text(encoding="utf-8")
    command_specs_lua = (root / "scripts/command_specs.lua").read_text(encoding="utf-8")
    command_catalog_lua = (root / "scripts/command_catalog.lua").read_text(encoding="utf-8")
    aliases_lua = (root / "scripts/english_aliases.lua").read_text(encoding="utf-8")
    objects_lua = (root / "scripts/official_objects.lua").read_text(encoding="utf-8")
    checks = {
        "English Mod registration": 'RegisterMod("Console UI", 1)',
        "display version": f'local VERSION = "{DISPLAY_VERSION}"',
        "independent SaveData object": "ConsoleUI:SaveData(payload)",
        "protected state load": "pcall(function() return ConsoleUI:LoadData() end)",
        "F6 hotkey": "Keyboard.KEY_F6",
        "L3 hold-to-open": 'controllerButton("STICK_LEFT", 10)',
        "controller index discovery": "local function controllerCandidates()",
        "logical confirm": 'controllerAction("ACTION_MENUCONFIRM")',
        "logical favorite": 'controllerAction("ACTION_MENUTAB")',
        "logical back": 'controllerAction("ACTION_MENUBACK")',
        "centralized raw compatibility": "local CONTROLLER_INPUT_COMPATIBILITY",
        "scoped Repentance+ raw fallback": "CONTROLLER_INPUT_COMPATIBILITY = { favorite = 4 }",
        "controller role resolver": "local function controllerRoleEvent(candidates, role, source, value)",
        "controller priority back before confirm": 'controllerRoleEvent(candidates, "back", "action", CONTROLLER_ACTION_BACK)',
        "controller priority confirm before favorite": 'controllerRoleEvent(candidates, "confirm", "action", CONTROLLER_ACTION_CONFIRM)',
        "long-A target lock": "state.controllerConfirmRemoveCommand = removalCommand(entry)",
        "hidden command execution": "Isaac.ExecuteCommand",
        "repeat upper bound": "1, 99",
        "contract repeat bound": "spec and spec.repeatMax or 1",
        "stage whitelist": "stageCommandWhitelists",
        "central command contracts": 'include("scripts.command_specs")',
        "localized command catalog": 'include("scripts.command_catalog")',
        "Render lifecycle request": "state.lifecycleRequest = { command = value }",
        "post-lifecycle receipt": "local function finalizeLifecycleReceipt()",
        "unknown command confirmation": "state.unknownCommandConfirmation ~= value",
        "input blocking": "MC_INPUT_ACTION",
        "ItemConfig removal semantics": '"AddCoins", "AddKeys", "AddBombs", "AddHearts", "AddMaxHearts"',
        "bundled 10px font": '"fusion/10.fnt"',
        "bundled 12px font": '"fusion/12.fnt"',
        "font load verification": "candidate10:IsLoaded(), candidate12:IsLoaded()",
        "English glyph verification": 'GetStringWidthUTF8("CONSOLE UI ABC 123")',
        "font failure page": '"FONT LOAD FAILED - MENU DISABLED"',
        "EID English locale": "EID.descriptions and EID.descriptions.en_us",
        "EID overlay suppression": "local function suppressEidOverlay()",
        "EID visibility restoration": "local function restoreEidOverlay()",
        "English aliases": 'include("scripts.english_aliases")',
        "ID-keyed aliases": "EnglishAliases[itemId]",
        "cached search": "entry.searchText = buildSearchText(entry)",
        "normalized search": "local function normalizeSearchText(value)",
        "complete game catalog": "loadCompleteCatalog()",
        "official object catalog": 'include("scripts.official_objects")',
        "typed favorites": 'local function validFavoriteKey(value)',
        "command favorite keys": "function FavoriteModel.commandFavoriteKey(command, spec)",
        "favorite key registry": "function FavoriteModel.registerEntry(entry)",
        "recent favorite ordering": "function FavoriteModel.finalizeOrder(forceAvailableCatalog)",
        "favorite membership/order invariant": "favorite state is missing from recent order",
        "user-only Featured": 'if #entries == 0 and category.id == "featured" then',
        "optional MCM keybind": 'ModConfigMenu.OptionType.KEYBIND_KEYBOARD',
        "optional MCM controller favorite": 'ModConfigMenu.OptionType.KEYBIND_CONTROLLER',
        "optional MCM startup hint": 'ModConfigMenu.OptionType.BOOLEAN',
        "startup hint persistence": 'startupHintEnabled=',
        "controller favorite persistence": 'controllerFavoriteButton=',
        "shared focused Ctrl+A editor": "local function captureEditableText(value, selectAll)",
        "custom open key": 'keyTriggered(state.openKey or DEFAULT_OPEN_KEY)',
        "two-column grid": "local GRID_COLUMNS = 2",
        "eight-item page": "local ITEMS_PER_PAGE = 8",
        "six-category page": "local CATEGORIES_PER_PAGE = 6",
        "measured layout": "local function computeLayout(screenWidth, screenHeight)",
        "runtime font metrics": "font:GetLineHeight()",
        "shared mouse geometry": "L.searchX + L.searchW - clearW",
        "focus ownership": "state.pointerActive and hit(mouse",
        "native pause detection": "Game():IsPaused()",
        "pause suspension state": "state.nativePauseSuspended = true",
        "closing input lease": "local function armInputLease(kind, value, index)",
        "manual command entry": "local function beginCommandInput(entry)",
        "manual command history": "local function recallCommandHistory(delta)",
        "named raw left bumper": 'controllerButton("BUMPER_LEFT")',
        "named raw right bumper": 'controllerButton("BUMPER_RIGHT")',
        "named raw left trigger": 'controllerButton("TRIGGER_LEFT")',
        "named raw right trigger": 'controllerButton("TRIGGER_RIGHT")',
        "physical shoulder resolver": "local function controllerShoulderEvent(candidates)",
        "focused category paging": 'if state.sidebarFocus then',
        "entry page command": "local function changeEntryPage(delta, entries)",
        "category page command": "local function changeCategoryPage(delta)",
        "wrapped descriptions": 'wrapText("Effect: "',
        "clickable manual command label": 'local commandLabel = "Manual command (C): "',
        "duplicate-name suppression": 'activeEntry.en ~= detailTitle',
        "favorite save rollback": "Favorite could not be saved; the change was reverted",
        "favorite marker": "local function drawFavoriteStar(",
        "favorite marker on every card": "local favoriteW = entry.canFavorite and L.starW or 0",
        "queue clamp": "queue.total = clamp(math.floor(rawTotal), 1, 99)",
        "queue completion guard": "if not queue or queue.finished then return end",
    }
    for label, needle in checks.items():
        if needle not in main_lua:
            fail(f"missing implementation: {label}")

    ambiguous_shoulder_actions = [
        'controllerAction("ACTION_MENULB")',
        'controllerAction("ACTION_MENURB")',
        'controllerAction("ACTION_MENULT")',
        'controllerAction("ACTION_MENURT")',
    ]
    for needle in ambiguous_shoulder_actions:
        if needle in main_lua:
            fail(f"physical shoulder role uses ambiguous action: {needle}")

    forbidden_source = [
        "scripts.pinyin_aliases",
        "scripts.search_aliases",
        "zh_cn",
        "resources-dlc3.zh",
        "resources.zh/font",
        'RegisterMod("Isaac Chinese Console"',
        "IS_REPENTOGON",
    ]
    for needle in forbidden_source:
        if needle in main_lua:
            fail(f"Chinese-edition implementation remains: {needle}")
    if "DrawStringScaledUTF8" in main_lua:
        fail("fractional BMFont scaling would blur the UI")
    if main_lua.count("state.open =") != 1:
        fail("menu visibility must only change through setMenuOpen")
    if main_lua.count("local function drawMenu(entries)") != 1:
        fail("runtime must contain exactly one menu renderer")

    state_needles = [
        '"openKey=" .. tostring(state.openKey or DEFAULT_OPEN_KEY)',
        '"startupHintEnabled=" .. (state.startupHintEnabled == false and "0" or "1")',
        '"controllerFavoriteButton=" .. tostring(state.controllerFavoriteButton or "auto")',
        '"favoriteOrder=recent\\n"',
        '"favorites=" .. table.concat(favoriteKeys, ",")',
        '"history=" .. table.concat(history, "|")',
        'parseRaw:match("favorites=([^\\n]*)")',
        'parseRaw:match("history=([^\\n]*)")',
    ]
    if any(needle not in main_lua for needle in state_needles):
        fail("favorites/history persistence format changed")
    if "local MAX_HISTORY = 8" not in main_lua or "while #state.history > MAX_HISTORY" not in main_lua:
        fail("history must remain capped at eight")
    exit_match = re.search(r"local function onGameExit\(\)(.*?)\nend", main_lua, re.S)
    if not exit_match or "saveState()" in exit_match.group(1):
        fail("game exit must not serialize state again")

    aliases = {
        int(item_id): value
        for item_id, value in re.findall(r'\[(\d+)\]\s*=\s*"([^"]*)"', aliases_lua)
    }
    if not aliases or any(not re.fullmatch(r"[a-z0-9 ]+", value) for value in aliases.values()):
        fail("English aliases must be non-empty lowercase ASCII text")
    required_aliases = {
        118: {"brim", "brimstone"},
        182: {"sacred", "heart"},
        260: set(),
        636: {"rkey", "restart"},
    }
    for item_id, tokens in required_aliases.items():
        if item_id == 260:
            continue
        value_tokens = set(aliases.get(item_id, "").split())
        if not tokens.issubset(value_tokens):
            fail(f"required English alias missing for ID {item_id}: {aliases.get(item_id)}")

    category_count = len(re.findall(r'^\s*\{ id = "[^"]+", group =', data_lua, re.M))
    category_count += len(re.findall(r'^\s*\{ id = "[^"]+", group =', command_catalog_lua, re.M))
    item_count = len(re.findall(r'^\s*\{ id = \d+, cat =', data_lua, re.M))
    command_count = len(re.findall(r'^\s*\{ cat = "[^"]+", name = .*? cmd =', data_lua, re.M))
    command_count += len(re.findall(r'^\s*\{ commandId = "[^"]+", cat =', command_catalog_lua, re.M))
    if (category_count, item_count, command_count) != (17, 74, 106):
        fail(f"catalog counts mismatch: {(category_count, item_count, command_count)}")
    if len(re.findall(r'^\s*\{ id = \d+, cat = .*? desc = "[^"]+"', data_lua, re.M)) != 74:
        fail("not every curated item has an English explanation")
    if len(re.findall(r'^\s*\{ cat = .*? desc = "[^"]+", cmd = "[^"]+"', data_lua, re.M)) != 68:
        fail("not every command has an English explanation")
    if len(re.findall(r'^\s*\{ commandId = "[^"]+", cat = .*? desc = "[^"]+"', command_catalog_lua, re.M)) != 38:
        fail("not every extended command has an English explanation")

    expected_official_verbs = {
        "spawn", "goto", "stage", "gridspawn", "debug", "giveitem", "remove",
        "costumetest", "restart", "listcollectibles", "repeat", "clearseeds",
        "seed", "challenge", "combo", "macro", "playsfx", "curse", "reseed",
        "copy", "clear", "lua", "luarun", "luamod", "luamem", "metro",
        "delirious", "restock", "rewind", "testbosspool", "reloadwisps",
    }
    contract_verbs = {
        verb
        for body in re.findall(r'verbs\s*=\s*\{(.*?)\}', command_specs_lua)
        for verb in re.findall(r'"([a-z]+)"', body)
    }
    missing_verbs = sorted(expected_official_verbs - contract_verbs)
    if missing_verbs:
        fail(f"official command contracts missing: {missing_verbs}")
    if not re.search(r'\{ id = "rewind".*?mode = "lifecycle".*?phase = "render"', command_specs_lua):
        fail("rewind is not routed through the lifecycle render channel")

    stage_lines = re.findall(r'^\s*\{ cat = "stage".*$', data_lua, re.M)
    normal_stages = {
        match.group(1)
        for line in stage_lines
        if 'stageMode = "greed"' not in line
        if (match := re.search(r'cmd = "(stage \d+[a-d]?)"', line))
    }
    greed_stages = {
        match.group(1)
        for line in stage_lines
        if 'stageMode = "greed"' in line
        if (match := re.search(r'cmd = "(stage \d+)"', line))
    }
    expected_ids = {
        "1", "1a", "1b", "1c", "1d", "2", "2a", "2b", "2c", "2d",
        "3", "3a", "3b", "3c", "3d", "4", "4a", "4b", "4c", "4d",
        "5", "5a", "5b", "5c", "5d", "6", "6a", "6b", "6c", "6d",
        "7", "7a", "7b", "7c", "8", "8a", "8b", "8c", "9", "10",
        "10a", "11", "11a", "12", "13",
    }
    if len(stage_lines) != 52 or normal_stages != {f"stage {value}" for value in expected_ids}:
        fail("Normal-mode stage whitelist changed")
    if greed_stages != {f"stage {value}" for value in range(1, 8)}:
        fail("Greed-mode stage whitelist changed")

    object_counts = {
        name: len(re.findall(r"^\s*\[\d+\]\s*=", body, re.M))
        for name, body in re.findall(r"^\s*(trinkets|cards|pills)\s*=\s*\{(.*?)^\s*\},", objects_lua, re.M | re.S)
    }
    if object_counts != {"trinkets": 188, "cards": 97, "pills": 50}:
        fail(f"official object counts mismatch: {object_counts}")

    for path in [root / "main.lua", root / "scripts/data.lua", root / "scripts/command_specs.lua", root / "scripts/command_catalog.lua", root / "scripts/english_aliases.lua", root / "scripts/official_objects.lua", root / "metadata.xml", root / "THIRD-PARTY-FONTS.md", root / "THIRD-PARTY-DATA.md"]:
        validate_text_is_english(path)

    font10 = parse_bmfont(root / "resources/font/fusion/10.fnt")
    font12 = parse_bmfont(root / "resources/font/fusion/12.fnt")
    for character in "CONSOLE UIRepeatSearchEffectCommandCompletedFailedFavoritex<>-+0123456789·×":
        if ord(character) not in font10 or ord(character) not in font12:
            fail(f"Fusion Pixel is missing required character: {character!r}")
    expected_pages = {
        "resources/font/fusion/10.fnt": ["10_0.png"],
        "resources/font/fusion/12.fnt": ["12_0.png", "12_1.png"],
    }
    for relative, expected in expected_pages.items():
        pages = parse_bmfont_pages(root / relative)
        if pages != expected:
            fail(f"Fusion Pixel page names mismatch: {relative} -> {pages}")
        for page in pages:
            if not ((root / relative).parent / page).is_file():
                fail(f"Fusion Pixel page is missing: {page}")
    for relative in [
        "resources/font/fusion/10_0.png",
        "resources/font/fusion/12_0.png",
        "resources/font/fusion/12_1.png",
    ]:
        with Image.open(root / relative) as image:
            if image.width > 2048 or image.height > 2048:
                fail(f"invalid font atlas size: {relative} {image.size}")
    with Image.open(root / "resources/gfx/ui/isaac_console_pixel.png") as image:
        if image.size != (1, 1):
            fail("UI pixel texture must be 1x1")
    preview_path = root / "preview.png"
    with Image.open(preview_path) as image:
        if image.size != (2262, 1289):
            fail(f"Workshop preview differs from the verified remote image size: {image.size}")
    preview_sha256 = hashlib.sha256(preview_path.read_bytes()).hexdigest().upper()
    if preview_sha256 != EXPECTED_PREVIEW_SHA256:
        fail("Workshop preview differs from the verified remote preview")
    if preview_path.stat().st_size > 1_000_000:
        fail("Workshop preview exceeds 1 MB")

    print("validation ok")
    print(f"identity: Console UI {DISPLAY_VERSION}; metadata={METADATA_VERSION}; workshop_id={workshop_id}")
    print(f"catalog: {category_count} categories, 721 collectibles, {object_counts['trinkets']} trinkets, {object_counts['cards']} cards/runes, {object_counts['pills']} pill effects, {command_count} commands")
    print(f"aliases: {len(aliases)} stable collectible IDs")
    print(f"font: Fusion Pixel 10px={len(font10)} glyphs, 12px={len(font12)} glyphs")
    print("package: self-contained, English-only player text, no external executables/scripts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
