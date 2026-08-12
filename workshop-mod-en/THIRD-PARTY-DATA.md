# Third-party data interfaces

Console UI does not bundle the External Item Descriptions effect-description database or runtime code.

If EID is installed and enabled, Console UI reads its public `en_us` description tables at runtime and converts EID markup into plain text for the detail panel. Missing, disabled, incompatible, or unavailable EID data falls back to the game's `ItemConfig` and never blocks the core catalog, search, commands, paging, or favorites.

`scripts/english_aliases.lua` contains a small hand-maintained set of common English search terms keyed only by stable numeric collectible ID. It does not copy EID descriptions.

`scripts/official_objects.lua` contains only the English official names needed for the trinket, card/rune, and base pill-effect catalogs. It was mechanically generated from EID's official `en_us` name lists and contains no EID effect descriptions, icons, code, or marked variants.

- Project: External Item Descriptions
- Author: Wofsauge and contributors
- Source: <https://github.com/wofsauge/External-Item-Descriptions>
- Steam Workshop: <https://steamcommunity.com/sharedfiles/filedetails/?id=836319872>
- API documentation: <https://github.com/wofsauge/External-Item-Descriptions/wiki>
