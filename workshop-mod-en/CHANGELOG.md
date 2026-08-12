# Changelog

## 2.5.4-en.3

- Fixed Toasts, including the startup key hint, potentially remaining visible for a long time after entering a Rerun following The Lamb.
- Replaced absolute game-frame Toast deadlines with a Mod-owned update-frame countdown while preserving all existing durations.
- Clear prior-run Toasts and unfinished command queues when the game frame counter moves backward, covering frame reset before, after, or without the ordinary new-game callback sequence.

## 2.5.4-en.2

- Fixed the first menu open of a process appearing unresponsive to the D-pad when Featured was empty; the menu now opens on the first Collectibles entry in that case.
- Kept a non-empty Featured view as the initial view. The automatic redirect runs once per process, does not repeat after an R restart, and does not override later user navigation.
- Made directional controller input prefer runtime `ACTION_MENUUP/DOWN/LEFT/RIGHT` actions with raw D-pad fallback, without double-moving when both sources report in the same frame.
- Added the Chinese and English Workshop sources and controller regression tests to the user-owned source repository.

## 2.5.4-en.1

- Unified controller input around logical confirm, back, and favorite roles, with isolated raw fallbacks and same-frame conflict arbitration across Repentance, Repentance+, and REPENTOGON.
- Fixed REPENTOGON controller A/X collisions so A confirms or starts the hold-to-remove action while X favorites.
- Added an optional MCM controller favorite binding. Automatic remains the default, and confirm/back actions outrank conflicting custom bindings.
- Added a persistent MCM startup key-hint toggle. Existing saves default to enabled; the first-process hint now lasts about 3 seconds.
- Added Ctrl+A full-query selection only while the search box is focused.
- Changed unspecified Toast duration to about 2 seconds while preserving every existing explicit warning and result duration.

## 2.5.2-en.2

- Kept version, category paging, category summaries, and search help complete at the game's 455x256 logical render size.
- Replaced duplicated official-object name records with the same compact string data.
- Losslessly optimized packaged PNG files without changing their pixels or dimensions.

## 2.5.2-en.1

- Added official trinket, card/rune, and pill-effect catalogs alongside the complete collectible catalog.
- Added type-safe favorites for `c/t/k/p` objects and migrated legacy numeric favorites without losing history.
- Changed Featured into an empty, user-built favorites list.
- Added optional Mod Config Menu support for changing the keyboard open key.
- Kept trinket removal available while cards, runes, and pill effects remain single-grant actions.
- Hardened bundled-font path discovery for alternate Steam Workshop directory names.
- Preserved the independent English Workshop ID `3779128726` and Console UI SaveData identity.

## 2.4.20-en.1

- Created an independent English Workshop edition named Console UI.
- Preserved the 12 categories, 74 curated collectibles, 68 commands, safe stage lists, repeat queue, favorites, history, measured layout, and input behavior from the v2.4.20 Chinese publication baseline.
- Rewrote all interface, catalog, help, diagnostic, and Workshop copy in natural English using official Isaac names.
- Added stable ID-keyed English aliases and normalized punctuation-insensitive search; removed Chinese and pinyin search data.
- Switched optional EID enrichment to `en_us`, with `ItemConfig` fallback.
- Made both Repentance and Repentance+ use the self-contained Fusion Pixel 10/12px font pair.
- Isolated the Mod identity, directory, SaveData, package, and future Workshop ID from Isaac Chinese Console.

