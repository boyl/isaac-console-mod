# Console UI — Workshop copy

Use the description embedded in `metadata.xml` as the canonical Workshop page text.

## Current Workshop description

# Console UI

**A self-contained in-game command menu with no required Mods, external downloads, PowerShell, or native debug console.**

Subscribe, enable the Mod, start a run, and press **F6** or hold the left stick button (L3) for about 0.5 seconds.

## Core Features

- 18 categories covering 721 collectibles, 188 trinkets, 97 cards/runes, 50 pill effects, 106 official command/reference entries, and Custom Commands;
- all 1,162 built-in object and command entries can be favorited; Featured shows recent favorites first without changing command permissions;
- Custom Commands support optional names, creation, search, favorites, editing, deletion, and history recall with no artificial item-count limit; the complete SaveData retains its 64 KiB safety gate;
- all 1,056 valid official objects include stable IDs and English-name indexing for cross-category search;
- mode-aware stage lists provide 45 Normal/Hard and 7 Greed/Greedier destinations; lifecycle commands use a separate safe path;
- collectibles and safe supplies can repeat 1–99 times; entries unsuitable for repetition remain single-run;
- keyboard, mouse, and controller support includes focus navigation, favorites, removal, repeat counts, list paging, and multi-page descriptions;
- measured layout adapts to the screen and bundled font metrics, including low resolutions;
- the game HUD hides while the menu is open; the overlay yields to the native pause menu and restores after resuming;
- no key injection, native console popup, or stray backtick.

## Controls

1. Press F6, or hold L3 for about 0.5 seconds, to open or close the menu.
2. Use the arrow keys, mouse, or D-pad to navigate.
3. Press Enter, left-click, or tap A to execute.
4. Right-click or hold A for about 0.5 seconds to remove a removable collectible or trinket.
5. Press F, controller X, or a card's star to favorite; use LT/RT to page the focused area, LB/RB to change the repeat count, and D, the description area, or controller Y to page long descriptions.
6. Press C to edit a complete command; use Up/Down in the input field to recall command history.

**Removing an item is not a full undo.** Coins, keys, bombs, health, spawned entities, room state, and scripted pickup effects may remain after the item itself is removed.

## Optional Mod Integrations — Not Required

**Without these Mods, the catalog, search, execution, favorites, and Custom Commands remain fully usable.**

- **External Item Descriptions (EID)**: can supplement names and descriptions for additional objects; Console UI does not copy or modify EID files;
- **Mod Config Menu (MCM)**: can configure the keyboard open key, controller favorite key, startup hint, and whether regular commands close the menu; defaults remain active when MCM is absent.

## Compatibility and Language Versions

One subscription supports Repentance, Repentance+, and REPENTOGON without a second runtime-specific edition.

Console UI and Isaac Chinese Console use the same F6 and L3 shortcuts. You may subscribe to both, but enable only one language version at a time.

## Safety and Usage Limits

This is a local entertainment, build-testing, and screenshot tool that changes the current run. Do not use it in Daily Challenges or online multiplayer. Back up important saves before testing.

This Mod does not access the network or launch external programs. When reporting a problem, include the game version, DLC/runtime, enabled Mod list, and relevant `log.txt` lines.

## 2.5.4-en.12 update note

Added Custom Commands with optional names, search, favorites, editing, confirmed deletion, and Up/Down recall of recently executed commands. Stable IDs preserve favorites through edits. This advanced raw-command passthrough accepts unknown, third-party, output, high-risk, and otherwise unvalidated commands at the user's own risk; recognized lifecycle commands still use the safe Render path. Capacity remains protected by the 120-byte command and 64 KiB transactional SaveData gates.

## 2.5.4-en.11 update note

Fixed Steam Input carrying one LB/RB press into later frames as a same-side LT/RT analog signal. Bumpers now retain their repeat-count role until fully released, while real triggers continue to page the focused list.

## 2.5.4-en.10 update note

Steam Deck and Steam Input shoulder controls now support semantic actions plus named physical fallbacks. LB/RB remain repeat-count controls, LT/RT remain focus-aware paging controls, and held analog triggers page only once until released.

## 2.5.4-en.9 update note

Contextual help now reflects the active keyboard, mouse, or controller path. Controller Y pages multi-page descriptions without affecting execution, favorites, repeat count, or list pages. Measured one- or two-line Toasts stay within their background and preserve the cause plus next action for critical messages.

## 2.5.4-en.8 update note

Optional MCM can now keep the menu open after regular commands, retaining the current category, page, selection, and command text for repeated testing. The default remains to close, and lifecycle commands that change the run always close and release input first. User-facing command descriptions now focus on effects and restrictions rather than implementation details.

## 2.5.4-en.7 update note

All 1,162 right-side entries can now be added to Featured with F, controller X, or each card's hollow/filled star. Featured is ordered by most recent favorite, while old saves migrate in their existing catalog order. Command favorites remain references to their original execution contracts and never bypass manual, lifecycle, native-console-only, or blocked safety rules.

## 2.5.4-en.3 update note

Fixed Toasts potentially remaining visible throughout a Rerun after The Lamb. Toast timing no longer depends on an absolute game-frame deadline, and prior-run transient UI state is cleared when the frame counter resets.

## 2.5.4-en.2 update note

Fixed first-open D-pad navigation when Featured is empty; an empty first-process view now starts on the first Collectibles entry, while saved favorites stay in Featured. Directional input prefers runtime menu actions with raw D-pad fallback and does not double-move when both sources report together.

## Publication checklist

- Title: `Console UI`
- Workshop ID: `3779128726`
- In-game version: `2.5.4-en.12`
- Metadata version: `2.5.4.12`
- Visibility: Public
- Tags: Lua, Tweaks
- Required items: none; EID is optional
- Confirm the uploader targets `3779128726`, not the Chinese item `3776882944`
- Confirm the preview includes `CONSOLE UI` and `EN`; compare it with the current remote preview before uploading, because development copies may be stale

