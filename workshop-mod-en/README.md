# Console UI

Console UI is a self-contained in-game command menu for *The Binding of Isaac: Rebirth*. It supports Repentance, Repentance+, and REPENTOGON without opening the native debug console or running external programs.

## Quick start

1. Subscribe and enable Console UI in the MODS menu.
2. Start a run.
3. Press `F6`, or hold the left stick button (`L3`) for about 0.5 seconds.
4. Navigate with the arrow keys, mouse, or D-pad.
5. Press `Enter`, left-click, or tap controller `A` to execute the selected entry.

## Controls

- `F6` or hold `L3`: open the menu; Mod Config Menu can change the keyboard key, toggle the first-run key hint, and choose whether regular commands close the menu.
- Arrow keys / D-pad: move through categories and cards, crossing pages automatically.
- Controller `LT` / `RT`: page the focused category list or entry grid.
- Mouse: select categories, cards, hollow/filled favorite stars, search, repeat count, paging, and close controls.
- `Enter`, left mouse button, or tap `A`: execute the selected entry.
- Right mouse button or hold `A` for about 0.5 seconds: remove a removable collectible.
- `F` or controller `X`: add or remove the current entry from Featured. MCM can optionally bind a different controller favorite button.
- `/`: search by official English name, common alias, command, or numeric ID.
- `Ctrl+A` while the search box is focused: select the full query; the next character replaces it, while Backspace/Delete clears it.
- `C`: edit the current command with ASCII input.
- `D`: page through a long effect description.
- `-` / `+`: set a repeat count from 1 to 99.
- Controller `LB` / `RB`: decrease or increase the repeat count.

Only `giveitem` and `spawn` can repeat. Debug flags, stage warps, `kill`, and other one-shot commands are forced to a single execution.

Regular commands close the menu by default for backward compatibility. With optional MCM, this can be turned off to keep the current category, page, selection, and manual-command text visible. Run-changing lifecycle commands still close the menu before execution.

## Catalog and EID

The menu includes 721 collectibles, 188 trinkets, 97 cards/runes, 50 pill effects, and 106 command or command-reference entries across 17 categories. Official object catalogs are loaded lazily from the current game's `ItemConfig` when the menu first opens. All 1,162 right-side entries can be favorited, and Featured shows the most recently favorited entry first. Favoriting a blocked or reference-only command never changes its execution permission.

Commands are classified by runtime safety. Lifecycle-changing commands use a one-shot final Render dispatcher, commands whose output requires the native console remain reference-only, and dangerous commands are blocked with an explicit reason. `rewind` is single-use and waits for a stable lifecycle receipt before the interface can submit another command.

External Item Descriptions is optional. When EID is enabled, Console UI reads its public `en_us` tables to enrich descriptions. If EID is missing or incompatible, official game data remains available and all commands continue to work.

## Removal semantics

`remove cID` removes the collectible itself. It does not promise to reverse coins, keys, bombs, health, spawned entities, room state, or one-shot scripted effects granted when the item was picked up. Entries with official immediate resource grants therefore do not advertise removal as an undo action.

## Language versions

Console UI and Isaac Chinese Console both use `F6` and `L3`. You may subscribe to both, but enable only one language version at a time.

## Safety and privacy

Console UI changes the current run and is intended for local entertainment, build testing, and captures. Do not use it in Daily Challenges or online multiplayer. Back up important saves before testing.

The Mod does not access the network, start external programs, inject keys, or read files outside its own game-managed data.

## Troubleshooting

When reporting an issue, include:

- Repentance, Repentance+, or REPENTOGON and the exact game version;
- whether EID is enabled;
- keyboard, mouse, and controller model/path used;
- other enabled Mods;
- relevant `[Console UI]` lines from `log.txt`.
