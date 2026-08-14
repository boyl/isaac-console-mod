-- Language-neutral command contracts. UI text belongs in command_catalog.lua.
local specs = {
  { id = "spawn", verbs = { "spawn" }, syntax = "spawn <type.variant.subtype.champion>", template = "spawn ", mode = "direct", phase = "update", repeatMax = 99 },
  { id = "goto", verbs = { "goto" }, syntax = "goto <room>", template = "goto ", mode = "lifecycle", phase = "render", repeatMax = 1 },
  { id = "stage", verbs = { "stage" }, syntax = "stage <1-13[a-d]>", template = "stage ", mode = "lifecycle", phase = "render", repeatMax = 1, validator = "stage" },
  { id = "gridspawn", verbs = { "gridspawn" }, syntax = "gridspawn <grid-id>", template = "gridspawn ", mode = "direct", phase = "update", repeatMax = 1 },
  { id = "debug", verbs = { "debug" }, syntax = "debug <flag>", template = "debug ", mode = "direct", phase = "update", repeatMax = 1 },
  { id = "giveitem", verbs = { "giveitem", "g" }, syntax = "giveitem <item>", template = "giveitem ", mode = "direct", phase = "update", repeatMax = 99 },
  { id = "remove", verbs = { "remove", "r" }, syntax = "remove <item>", template = "remove ", mode = "direct", phase = "update", repeatMax = 1 },
  { id = "kill", verbs = { "kill" }, syntax = "kill", template = "kill", mode = "direct", phase = "update", repeatMax = 1 },
  { id = "costumetest", verbs = { "costumetest" }, syntax = "costumetest [count]", template = "costumetest", mode = "direct", phase = "update", repeatMax = 1 },
  { id = "restart", verbs = { "restart" }, syntax = "restart [0-40]", template = "restart", mode = "lifecycle", phase = "render", repeatMax = 1, validator = "restart" },
  { id = "clearseeds", verbs = { "clearseeds" }, syntax = "clearseeds", template = "clearseeds", mode = "direct", phase = "update", repeatMax = 1 },
  { id = "seed", verbs = { "seed" }, syntax = "seed XXXX XXXX", template = "seed ", mode = "lifecycle", phase = "render", repeatMax = 1, validator = "seed" },
  { id = "challenge", verbs = { "challenge" }, syntax = "challenge <id>", template = "challenge ", mode = "lifecycle", phase = "render", repeatMax = 1, validator = "challenge" },
  { id = "combo", verbs = { "combo" }, syntax = "combo <pool.count>", template = "combo ", mode = "direct", phase = "update", repeatMax = 1 },
  { id = "playsfx", verbs = { "playsfx" }, syntax = "playsfx <sound-id>", template = "playsfx ", mode = "direct", phase = "update", repeatMax = 1 },
  { id = "curse", verbs = { "curse" }, syntax = "curse <0-255>", template = "curse ", mode = "direct", phase = "update", repeatMax = 1, validator = "curse" },
  { id = "reseed", verbs = { "reseed" }, syntax = "reseed", template = "reseed", mode = "lifecycle", phase = "render", repeatMax = 1 },
  { id = "metro", verbs = { "metro" }, syntax = "metro <value>", template = "metro ", mode = "direct", phase = "update", repeatMax = 1 },
  { id = "delirious", verbs = { "delirious" }, syntax = "delirious <boss-id>", template = "delirious ", mode = "direct", phase = "update", repeatMax = 1 },
  { id = "restock", verbs = { "restock" }, syntax = "restock", template = "restock", mode = "direct", phase = "update", repeatMax = 1 },
  { id = "rewind", verbs = { "rewind" }, syntax = "rewind", template = "rewind", mode = "lifecycle", phase = "render", repeatMax = 1 },
  { id = "reloadwisps", verbs = { "reloadwisps" }, syntax = "reloadwisps", template = "reloadwisps", mode = "direct", phase = "update", repeatMax = 1 },
  { id = "listcollectibles", verbs = { "listcollectibles" }, syntax = "listcollectibles", template = "listcollectibles", mode = "output", phase = "native", repeatMax = 1 },
  { id = "copy", verbs = { "copy" }, syntax = "copy", template = "copy", mode = "output", phase = "native", repeatMax = 1 },
  { id = "clear", verbs = { "clear" }, syntax = "clear", template = "clear", mode = "output", phase = "native", repeatMax = 1 },
  { id = "luamem", verbs = { "luamem" }, syntax = "luamem", template = "luamem", mode = "output", phase = "native", repeatMax = 1 },
  { id = "testbosspool", verbs = { "testbosspool" }, syntax = "testbosspool", template = "testbosspool", mode = "output", phase = "native", repeatMax = 1 },
  { id = "lua", verbs = { "lua", "l" }, syntax = "lua <code>", template = "lua ", mode = "disabled", phase = "none", repeatMax = 1, reason = "code" },
  { id = "luarun", verbs = { "luarun" }, syntax = "luarun <file>", template = "luarun ", mode = "disabled", phase = "none", repeatMax = 1, reason = "code" },
  { id = "luamod", verbs = { "luamod" }, syntax = "luamod <mod>", template = "luamod ", mode = "disabled", phase = "none", repeatMax = 1, reason = "code" },
  { id = "achievement", verbs = { "achievement" }, syntax = "achievement <id>", template = "achievement ", mode = "disabled", phase = "none", repeatMax = 1, reason = "save" },
  { id = "prof", verbs = { "prof" }, syntax = "prof", template = "prof", mode = "disabled", phase = "none", repeatMax = 1, reason = "process" },
  { id = "fullrestart", verbs = { "fullrestart" }, syntax = "fullrestart", template = "fullrestart", mode = "disabled", phase = "none", repeatMax = 1, reason = "process" },
  { id = "quit", verbs = { "quit" }, syntax = "quit", template = "quit", mode = "disabled", phase = "none", repeatMax = 1, reason = "process" },
  { id = "macro", verbs = { "macro", "m" }, syntax = "macro <name>", template = "macro ", mode = "disabled", phase = "none", repeatMax = 1, reason = "indirect" },
  { id = "repeat", verbs = { "repeat" }, syntax = "repeat <count>", template = "repeat ", mode = "disabled", phase = "none", repeatMax = 1, reason = "indirect" },
}
local byId, byVerb = {}, {}
for _, spec in ipairs(specs) do
  assert(not byId[spec.id], "duplicate command spec id: " .. spec.id)
  byId[spec.id] = spec
  for _, verb in ipairs(spec.verbs) do
    assert(not byVerb[verb], "duplicate command verb: " .. verb)
    byVerb[verb] = spec
  end
end
return { list = specs, byId = byId, byVerb = byVerb }
