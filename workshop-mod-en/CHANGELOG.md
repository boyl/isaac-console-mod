# Changelog

## 2.5.4-en.6

- Added centralized command specifications plus Run Control and Command Reference categories. Built-in commands now have explicit direct, parameter-template, lifecycle, native-console-only, or blocked contracts shared by both languages.
- Parameter references explain their syntax on A/Enter and open an unselected tail-positioned template on C. Unknown or third-party commands require an explicit second confirmation and are always single-run.
- Routed `restart/reseed/seed/challenge/goto/stage` through a one-shot render-phase lifecycle channel that closes the overlay and releases input before execution, avoids touching invalidated player objects afterward, and settles history only in a later stable callback.
- `rewind` now appends a one-shot final Render dispatcher so no existing Mod Render callback can access invalidated player objects later in the same frame; command state settles only after two stable updates.
- Native-console-output commands and Lua, exit, achievement, profiling, macro, and repeat commands now show explicit blocked reasons and never enter the execution queue.
- Added independent command-domain, lifecycle, unknown-confirmation, and cross-language semantic regressions without changing favorites, SaveData, input roles, or Workshop identity.

## 2.5.4-en.5

- Added focus-aware controller paging: LT/RT pages categories while the sidebar owns focus and pages entries while the grid owns focus; search and command editors ignore the triggers.
- Identify physical triggers through named `Controller.TRIGGER_LEFT/RIGHT` values; ambiguous `ACTION_MENULT/MENURT` menu-tab actions are not treated as triggers, preventing LB/RB from being misclassified as paging.
- The active pager shows LT/RT while the inactive pager retains ordinary arrows, using the same measured render and mouse-hit geometry.
- LB/RB repeat counts, D-pad automatic cross-page navigation, A/B/X/L3, favorites, commands, pause behavior, and SaveData remain unchanged.
- Hardened closed-overlay input isolation: with no release lease, the input hook fully yields to the game and performs no extra physical-key polling during native player/controller construction.
- Keyboard characters, deletion, and Ctrl+A in search or command editors now switch help back to keyboard prompts instead of retaining stale A/B controller hints.

## 2.5.4-en.4

- Hide the Mod overlay and release input while the native pause menu is open, then restore the prior page and input state without allowing the resume A/Enter press to execute an entry.
- Turned manual commands into a clickable editor with prefilled selection, Ctrl+A, Backspace/Delete, Enter, Esc, and Up/Down recall for the latest eight commands and repeat counts.
- Non-empty search fields now show only the query. Long search and command input keeps the tail and cursor visible.
- Added LB/RB repeat-count controls in the normal menu and command editor while preserving physical bumper identity through named `Controller.BUMPER_LEFT/RIGHT` values across Repentance, Repentance+, and REPENTOGON.
- Fixed text keys such as Space being reported as menu confirm and prematurely submitting manual commands. Text input now wins in search and command fields; only Enter or a real controller confirm submits.
- Always show the LB/RB repeat-count hint and use compact category and command help so low-resolution layouts remain understandable.
- Kept the header for category title, search, and pagination, while a single priority-based footer context now follows search, command, category, entry, and empty focus without competing for space.
- Changed the detail shortcut to `Manual command (C)` and separately measured the label, command value, and action hint. Short commands remain complete, long commands retain their tail, and successful-command feedback now lasts about two seconds while failures and safety warnings keep their existing durations.
- Added deliberate short descriptions for all 15 categories. Low-resolution layouts choose a complete short description only when the complete long description does not fit, rather than mechanically truncating it.
- Fixed controller-disconnect recovery input leaking beyond the native prompt and creating a second player after the overlay closes. The disconnect prompt receives all input needed to reconnect.
- Controller input is now resolved only from controllers assigned to existing players. A unified input lease holds residual Enter, Esc, F6, mouse, A, B, and L3 close/execute input until physical release, preventing an unintended second player, pause, or gameplay action.
- Native-pause recovery now skips only the Mod's first input-processing frame and never gates game input. `ACTION_RESTART` passes through outside text editors and releases transient Mod input before player reconstruction; the callback gap after frame rollback also yields all input. R restart, Rewind, Rerun, and callback-less rollback clear stale pause, input-lease, and controller-ownership state so native reassignment can proceed immediately, while search and command editors retain the letter R without restarting.
- Removed an unused resume-frame state. No resources, dependencies, persisted fields, Workshop identities, or SaveData formats changed.

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

