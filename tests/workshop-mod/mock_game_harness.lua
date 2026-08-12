-- Integration harness for workshop-mod/main.lua. It executes the real Mod
-- entry point against a deterministic Isaac API mock and drives registered
-- callbacks with keyboard, mouse and controller input.

assert(type(MOD_ROOT) == "string" and MOD_ROOT ~= "", "MOD_ROOT is required")
TEST_CONFIG = TEST_CONFIG or {}

local function fail(message)
  error("[mock game] " .. tostring(message), 2)
end

local function assertTrue(value, message)
  if not value then fail(message or "expected true") end
end

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    fail((message or "values differ") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
  end
end

local function contains(value, needle)
  return tostring(value or ""):find(tostring(needle), 1, true) ~= nil
end

local TEST = {
  callbacks = {},
  keyTriggers = {},
  buttonTriggers = {},
  actionTriggers = {},
  actionPressed = {},
  buttonPressed = {},
  mouseButtons = { false, false },
  mousePosition = { X = 0, Y = 0 },
  frame = 0,
  hudVisible = true,
  saveAttempts = 0,
  saveData = nil,
  executed = {},
  logs = {},
  rendered = {},
  fontLoads = {},
  mcmAddCalls = 0,
  mcmSetting = nil,
  mcmSettings = {},
  spriteRenders = 0,
  worldToScreenCalls = 0,
  getItemConfigCalls = 0,
  getCollectibleCalls = 0,
  getTrinketCalls = 0,
  getCardCalls = 0,
  getPillEffectCalls = 0,
}

if TEST_CONFIG.scenario == "oversized" then
  TEST.saveData = "version=2.4.2\nfavorites=260,182\nhistory=" .. string.rep("x", 70000)
elseif TEST_CONFIG.scenario == "upgrade" then
  TEST.saveData = "version=2.4.2\nfavorites=260,182\nhistory=giveitem c260|spawn 5.10.1"
elseif TEST_CONFIG.initialFavorite then
  TEST.saveData = "version=2.5.4-en.2\nfavorites=c:182\nhistory="
end

REPENTANCE_PLUS = TEST_CONFIG.repPlus == true

function Color(...) return { ... } end
function KColor(...) return { ... } end
function Vector(x, y) return { X = x or 0, Y = y or 0 } end

local function utf8Length(value)
  local count = 0
  local index = 1
  value = tostring(value or "")
  while index <= #value do
    local byte = value:byte(index)
    if byte < 0x80 then index = index + 1
    elseif byte < 0xE0 then index = index + 2
    elseif byte < 0xF0 then index = index + 3
    else index = index + 4 end
    count = count + 1
  end
  return count
end

function Font()
  local font = { loaded = false, lineHeight = 10, path = "" }
  function font:Load(path)
    self.path = tostring(path or "")
    self.lineHeight = self.path:find("12", 1, true) and 12 or 10
    TEST.fontLoads[#TEST.fontLoads + 1] = self.path
    if TEST_CONFIG.fontMode == "all_fail" then
      self.loaded = false
    else
      self.loaded = true
    end
  end
  function font:IsLoaded() return self.loaded end
  function font:GetStringWidthUTF8(value)
    if not self.loaded then return 0 end
    return utf8Length(value) * 6
  end
  function font:GetLineHeight() return self.lineHeight end
  function font:DrawStringUTF8(value)
    TEST.rendered[#TEST.rendered + 1] = tostring(value or "")
  end
  return font
end

function Sprite()
  local sprite = {}
  function sprite:Load() end
  function sprite:Play() end
  function sprite:Render() TEST.spriteRenders = TEST.spriteRenders + 1 end
  return sprite
end

Keyboard = {
  KEY_0 = 48, KEY_9 = 57, KEY_A = 65, KEY_Z = 90,
  KEY_SPACE = 32, KEY_PERIOD = 46, KEY_MINUS = 45, KEY_SLASH = 47, KEY_EQUAL = 61,
  KEY_ESCAPE = 256, KEY_ENTER = 257, KEY_BACKSPACE = 259, KEY_DELETE = 261,
  KEY_F6 = 295, KEY_F7 = 296, KEY_F8 = 297, KEY_C = 67, KEY_R = 82,
  KEY_F = 70, KEY_D = 68, KEY_KP_ADD = 334, KEY_PAGE_UP = 266, KEY_PAGE_DOWN = 267,
  KEY_UP = 265, KEY_DOWN = 264, KEY_LEFT = 263, KEY_RIGHT = 262,
  KEY_LEFT_CONTROL = 341, KEY_RIGHT_CONTROL = 345,
}

ButtonAction = {
  ACTION_MENUBACK = 1, ACTION_MENUUP = 2, ACTION_MENUDOWN = 3,
  ACTION_MENULEFT = 4, ACTION_MENURIGHT = 5, ACTION_MENUCONFIRM = 6,
  ACTION_MAP = 7, ACTION_DROP = 8, ACTION_BOMB = 9, ACTION_PILLCARD = 10,
  ACTION_ITEM = 11, ACTION_MENULT = 12, ACTION_MENURT = 13, ACTION_MENUTAB = 14,
}
Controller = {
  DPAD_LEFT = 0, DPAD_RIGHT = 1, DPAD_UP = 2, DPAD_DOWN = 3,
  BUTTON_A = 4, BUTTON_B = 5, BUTTON_X = 6, BUTTON_Y = 7,
  BUMPER_LEFT = 8, TRIGGER_LEFT = 9, STICK_LEFT = 10,
  BUMPER_RIGHT = 11, TRIGGER_RIGHT = 12, STICK_RIGHT = 13,
  BUTTON_BACK = 14, BUTTON_START = 15,
}

if TEST_CONFIG.mcm then
  ModConfigMenu = {
    OptionType = { BOOLEAN = 1, KEYBIND_KEYBOARD = 6, KEYBIND_CONTROLLER = 7 },
    PopupGfx = { WIDE_SMALL = "wide-small" },
  }
  function ModConfigMenu.AddSetting(category, subcategory, setting)
    TEST.mcmAddCalls = TEST.mcmAddCalls + 1
    TEST.mcmCategory = category
    TEST.mcmSubcategory = subcategory
    TEST.mcmSettings[#TEST.mcmSettings + 1] = setting
    if setting.Type == ModConfigMenu.OptionType.KEYBIND_KEYBOARD then
      TEST.mcmSetting = setting
    end
  end
else
  ModConfigMenu = nil
end

InputHook = { GET_ACTION_VALUE = 1 }
ModCallbacks = {
  MC_POST_RENDER = 1,
  MC_POST_UPDATE = 2,
  MC_INPUT_ACTION = 3,
  MC_POST_GAME_STARTED = 4,
  MC_PRE_GAME_EXIT = 5,
}

Input = {}
function Input.IsButtonTriggered(key, controllerIndex)
  local byController = TEST.buttonTriggers[key]
  local index = controllerIndex or 0
  if TEST.keyTriggers[key] == true
      or (type(byController) == "table" and byController[index] == true) then
    return true
  end
  return false
end
function Input.IsButtonPressed(button, controllerIndex)
  local byController = TEST.buttonPressed[button]
  return type(byController) == "table" and byController[controllerIndex or 0] == true
end
function Input.IsActionTriggered(action, controllerIndex)
  if TEST_CONFIG.actionsUnavailable then return false end
  if TEST_CONFIG.menuTabActionUnavailable and action == ButtonAction.ACTION_MENUTAB then return false end
  local byController = TEST.actionTriggers[action]
  return type(byController) == "table" and byController[controllerIndex or 0] == true
end
function Input.IsActionPressed(action, controllerIndex)
  if TEST_CONFIG.actionsUnavailable then return false end
  local byController = TEST.actionPressed[action]
  return type(byController) == "table" and byController[controllerIndex or 0] == true
end
function Input.IsMouseBtnPressed(button) return TEST.mouseButtons[button + 1] == true end
function Input.GetMousePosition() return Vector(TEST.mousePosition.X, TEST.mousePosition.Y) end

local hud = {}
function hud:IsVisible() return TEST.hudVisible end
function hud:SetVisible(value) TEST.hudVisible = value == true end

local game = {}
function game:GetHUD() return hud end
function game:GetFrameCount() return TEST.frame end
function game:GetNumPlayers() return 1 end
function game:IsGreedMode() return TEST_CONFIG.greedMode == true end
function Game() return game end

CollectibleType = { NUM_COLLECTIBLES = 733 }
TrinketType = { NUM_TRINKETS = 190 }
Card = { NUM_CARDS = 98 }
PillEffect = { NUM_PILL_EFFECTS = 50 }
local invalidCollectibles = {
  [43] = true, [61] = true, [235] = true, [587] = true, [613] = true,
  [620] = true, [630] = true, [648] = true, [662] = true, [666] = true, [718] = true,
}
local itemConfig = {}
function itemConfig:GetCollectible(id)
  TEST.getCollectibleCalls = TEST.getCollectibleCalls + 1
  if id < 1 or id >= CollectibleType.NUM_COLLECTIBLES or invalidCollectibles[id] then return nil end
  local config = {
    Name = "#ITEM_NAME_" .. tostring(id),
    Description = "#ITEM_DESCRIPTION_" .. tostring(id),
    Quality = id % 5,
  }
  if id == 18 then config.AddCoins = 99 end
  if id == 17 then config.AddKeys = 99 end
  if id == 190 then config.AddBombs = 99 end
  return config
end
function itemConfig:GetTrinket(id)
  TEST.getTrinketCalls = TEST.getTrinketCalls + 1
  if id < 1 or id >= TrinketType.NUM_TRINKETS or id == 47 then return nil end
  return { Name = "#TRINKET_NAME_" .. tostring(id), Description = "Trinket " .. tostring(id) }
end
function itemConfig:GetCard(id)
  TEST.getCardCalls = TEST.getCardCalls + 1
  if id < 1 or id >= Card.NUM_CARDS then return nil end
  return { Name = "#CARD_NAME_" .. tostring(id), Description = "Card " .. tostring(id) }
end
function itemConfig:GetPillEffect(id)
  TEST.getPillEffectCalls = TEST.getPillEffectCalls + 1
  if id < 0 or id >= PillEffect.NUM_PILL_EFFECTS then return nil end
  return { Name = "#PILL_NAME_" .. tostring(id), Description = "Pill " .. tostring(id) }
end

Isaac = {}
function Isaac.GetPlayer()
  return { ControllerIndex = TEST_CONFIG.controllerIndex or 0 }
end
function Isaac.DebugString(message) TEST.logs[#TEST.logs + 1] = tostring(message) end
function Isaac.GetItemConfig()
  TEST.getItemConfigCalls = TEST.getItemConfigCalls + 1
  return itemConfig
end
function Isaac.GetScreenWidth() return TEST_CONFIG.screenWidth or 1280 end
function Isaac.GetScreenHeight() return TEST_CONFIG.screenHeight or 720 end
function Isaac.WorldToScreen(value)
  TEST.worldToScreenCalls = TEST.worldToScreenCalls + 1
  return Vector(value.X, value.Y)
end
function Isaac.ExecuteCommand(command)
  if TEST_CONFIG.executeFail then error("forced execute failure") end
  TEST.executed[#TEST.executed + 1] = tostring(command)
end
function Isaac.RenderText(value) TEST.rendered[#TEST.rendered + 1] = tostring(value or "") end

if TEST_CONFIG.eid then
  local longDescription = string.rep("A deliberately long English effect description used to verify measured paging. ", 40)
  EID = {
    isHidden = TEST_CONFIG.eidInitiallyHidden == true,
    descriptions = { en_us = {
      collectibles = {
        [260] = { "5.100.260", "Black Candle", longDescription },
      },
      trinkets = {
        [1] = { "1", "Swallowed Penny", "Spawns 1 coin when Isaac is hit" },
      },
      cards = {
        [1] = { "1", "0 - The Fool", "Teleports Isaac to the starting room" },
      },
      pills = {
        [1] = { "0", "Bad Gas", "Poisons nearby enemies" },
        [2] = { "1", "Bad Trip", "Deals one heart of damage to Isaac" },
      },
    } },
    ItemNames = { en_us = { ["5.100.260"] = "Black Candle" } },
  }
else
  EID = nil
end

local registeredMod = nil
function RegisterMod(name, apiVersion)
  local mod = { name = name, apiVersion = apiVersion }
  function mod:AddCallback(callbackId, callback) TEST.callbacks[callbackId] = callback end
  function mod:HasData()
    if TEST_CONFIG.hasDataFail then error("forced HasData failure") end
    if TEST_CONFIG.loadFail then return true end
    return TEST.saveData ~= nil
  end
  function mod:LoadData()
    if TEST_CONFIG.loadFail then error("forced LoadData failure") end
    return TEST.saveData
  end
  function mod:SaveData(payload)
    TEST.saveAttempts = TEST.saveAttempts + 1
    if TEST_CONFIG.saveFail then error("forced SaveData failure") end
    TEST.saveData = tostring(payload)
  end
  registeredMod = mod
  return mod
end

function include(path)
  local relative = tostring(path):gsub("%.", "/")
  local chunk, err = loadfile(MOD_ROOT .. "/" .. relative .. ".lua")
  if not chunk then error(err) end
  return chunk()
end

local mainChunk, mainError = loadfile(MOD_ROOT .. "/main.lua")
if not mainChunk then error(mainError) end
mainChunk()

assertTrue(registeredMod ~= nil, "RegisterMod was not called")
assertEqual(registeredMod.name, TEST_CONFIG.expectedModName or "Console UI", "RegisterMod name changed")
assertEqual(registeredMod.apiVersion, 1, "RegisterMod API version changed")

for _, callbackId in pairs(ModCallbacks) do
  assertTrue(type(TEST.callbacks[callbackId]) == "function", "callback missing: " .. tostring(callbackId))
end

local onRender = TEST.callbacks[ModCallbacks.MC_POST_RENDER]
local onUpdate = TEST.callbacks[ModCallbacks.MC_POST_UPDATE]
local onInput = TEST.callbacks[ModCallbacks.MC_INPUT_ACTION]
local onStarted = TEST.callbacks[ModCallbacks.MC_POST_GAME_STARTED]
local onExit = TEST.callbacks[ModCallbacks.MC_PRE_GAME_EXIT]

local function findUpvalue(rootFunction, targetName, seen)
  if type(rootFunction) ~= "function" then return nil end
  seen = seen or {}
  if seen[rootFunction] then return nil end
  seen[rootFunction] = true
  local index = 1
  while true do
    local name, value = debug.getupvalue(rootFunction, index)
    if not name then break end
    if name == targetName then return value end
    if type(value) == "function" then
      local nested = findUpvalue(value, targetName, seen)
      if nested ~= nil then return nested end
    end
    index = index + 1
  end
  return nil
end

local state = findUpvalue(onRender, "state")
local visibleEntries = findUpvalue(onRender, "visibleEntries")
local computeLayout = findUpvalue(onRender, "computeLayout")
local drawFavoriteStar = findUpvalue(onRender, "drawFavoriteStar")
local queueCommand = findUpvalue(onRender, "queueCommand")
local queueEntry = findUpvalue(onRender, "queueEntry")
local removalCommand = findUpvalue(onRender, "removalCommand")
local allEntries = findUpvalue(onRender, "allEntries")
local runtimeCatalog = findUpvalue(visibleEntries, "Catalog")
assertTrue(type(state) == "table", "state upvalue unavailable")
assertTrue(type(visibleEntries) == "function", "visibleEntries upvalue unavailable")
assertTrue(type(computeLayout) == "function", "computeLayout upvalue unavailable")
assertTrue(type(drawFavoriteStar) == "function", "drawFavoriteStar upvalue unavailable")
assertTrue(type(queueCommand) == "function", "queueCommand upvalue unavailable")
assertTrue(type(removalCommand) == "function", "removalCommand upvalue unavailable")

local function clearInput()
  TEST.keyTriggers = {}
  TEST.buttonTriggers = {}
  TEST.actionTriggers = {}
end

local function renderFrame()
  TEST.frame = TEST.frame + 1
  onRender()
  clearInput()
end

local function pressKey(key)
  TEST.keyTriggers[key] = true
  renderFrame()
end

local function pressButton(button, controllerIndex)
  controllerIndex = controllerIndex or TEST_CONFIG.controllerIndex or 0
  TEST.buttonTriggers[button] = { [controllerIndex] = true }
  TEST.buttonPressed[button] = { [controllerIndex] = true }
  if button == (TEST_CONFIG.physicalBackButton or Controller.BUTTON_B) then
    TEST.actionTriggers[ButtonAction.ACTION_MENUBACK] = { [controllerIndex] = true }
    TEST.actionPressed[ButtonAction.ACTION_MENUBACK] = { [controllerIndex] = true }
  elseif button == (TEST_CONFIG.physicalConfirmButton or Controller.BUTTON_A) then
    TEST.actionTriggers[ButtonAction.ACTION_MENUCONFIRM] = { [controllerIndex] = true }
    TEST.actionPressed[ButtonAction.ACTION_MENUCONFIRM] = { [controllerIndex] = true }
  elseif button == (TEST_CONFIG.physicalFavoriteButton or Controller.BUTTON_X) then
    TEST.actionTriggers[ButtonAction.ACTION_MENUTAB] = { [controllerIndex] = true }
    TEST.actionPressed[ButtonAction.ACTION_MENUTAB] = { [controllerIndex] = true }
  end
  renderFrame()
  TEST.buttonPressed[button] = { [controllerIndex] = false }
  TEST.actionPressed[ButtonAction.ACTION_MENUCONFIRM] = { [controllerIndex] = false }
  TEST.actionPressed[ButtonAction.ACTION_MENUTAB] = { [controllerIndex] = false }
  TEST.actionPressed[ButtonAction.ACTION_MENUBACK] = { [controllerIndex] = false }
end

local function pressDirection(action, button, controllerIndex, includeRaw)
  controllerIndex = controllerIndex or TEST_CONFIG.controllerIndex or 0
  TEST.actionTriggers[action] = { [controllerIndex] = true }
  if includeRaw then TEST.buttonTriggers[button] = { [controllerIndex] = true } end
  renderFrame()
end

local function startHeldButton(button, controllerIndex)
  controllerIndex = controllerIndex or TEST_CONFIG.controllerIndex or 0
  TEST.buttonPressed[button] = { [controllerIndex] = true }
  if button == (TEST_CONFIG.physicalConfirmButton or Controller.BUTTON_A) then
    TEST.actionPressed[ButtonAction.ACTION_MENUCONFIRM] = { [controllerIndex] = true }
    TEST.actionTriggers[ButtonAction.ACTION_MENUCONFIRM] = { [controllerIndex] = true }
  end
  TEST.buttonTriggers[button] = { [controllerIndex] = true }
  renderFrame()
end

local function holdButton(button, frames, controllerIndex)
  controllerIndex = controllerIndex or TEST_CONFIG.controllerIndex or 0
  TEST.buttonPressed[button] = { [controllerIndex] = true }
  if button == (TEST_CONFIG.physicalConfirmButton or Controller.BUTTON_A) then
    TEST.actionPressed[ButtonAction.ACTION_MENUCONFIRM] = { [controllerIndex] = true }
  end
  for _ = 1, frames do renderFrame() end
end

local function releaseButton(button, controllerIndex)
  controllerIndex = controllerIndex or TEST_CONFIG.controllerIndex or 0
  TEST.buttonPressed[button] = { [controllerIndex] = false }
  if button == (TEST_CONFIG.physicalConfirmButton or Controller.BUTTON_A) then
    TEST.actionPressed[ButtonAction.ACTION_MENUCONFIRM] = { [controllerIndex] = false }
  end
  renderFrame()
end

local function clickMouse(x, y, button)
  button = button or 0
  TEST.mousePosition = Vector(x, y)
  TEST.mouseButtons[button + 1] = true
  renderFrame()
  TEST.mouseButtons[button + 1] = false
  renderFrame()
end

local function keyForCharacter(character)
  if character:match("%d") then return character:byte() end
  return character:upper():byte()
end

local function openMenu()
  if not state.open then pressKey(state.openKey or Keyboard.KEY_F6) end
  assertTrue(state.open, "configured key did not open menu")
  assertEqual(TEST.hudVisible, false, "opening menu did not hide HUD")
end

local function enterSearch(query)
  openMenu()
  state.search = ""
  pressKey(Keyboard.KEY_SLASH)
  assertEqual(state.inputMode, "search", "slash did not enter search mode")
  for index = 1, #query do pressKey(keyForCharacter(query:sub(index, index))) end
  assertEqual(state.search, query, "typed search query differs")
  pressKey(Keyboard.KEY_ENTER)
  assertEqual(state.inputMode, nil, "Enter did not finish search input")
end

local function executeSearchResult(query, expectedCommand)
  enterSearch(query)
  pressKey(Keyboard.KEY_ENTER)
  assertEqual(state.open, false, "executing result did not close menu")
  onUpdate()
  assertEqual(TEST.executed[#TEST.executed], expectedCommand, "wrong search result executed")
end

local function assertFontRoute()
  assertTrue(#TEST.fontLoads >= 2, "font pair was not attempted")
  local foundFusion = false
  for _, path in ipairs(TEST.fontLoads) do
    if contains(path, "fusion/10.fnt") or contains(path, "fusion/12.fnt") then foundFusion = true end
    assertTrue(not contains(path, ".zh/font/"), "English edition loaded a locale-specific game font")
  end
  assertTrue(foundFusion, "self-contained Fusion Pixel font was not loaded")
end

local function testSearch()
  onStarted()
  assertFontRoute()
  executeSearchResult(TEST_CONFIG.query, TEST_CONFIG.expectedCommand)
  assertTrue(#state.history <= 8, "history exceeded eight after search execution")
  if TEST_CONFIG.eid then
    assertTrue(state.history[1] == TEST_CONFIG.expectedCommand, "EID-on history differs")
  end
end

local function findEntry(entries, itemId)
  for index, entry in ipairs(entries) do
    if entry.id == itemId then return index, entry end
  end
  return nil, nil
end

local function testFavorite()
  onStarted()
  enterSearch("182")
  pressKey(Keyboard.KEY_F)
  assertTrue(state.favorites["c:182"] == true, "curated collectible could not be favorited")
  pressKey(Keyboard.KEY_F)
  assertTrue(state.favorites["c:182"] == nil, "curated collectible could not be unfavorited")

  enterSearch("260")
  pressKey(Keyboard.KEY_F)
  assertTrue(state.favorites["c:260"] == true, "F did not add dynamic favorite")
  assertTrue(contains(TEST.saveData, "favorites=c:260"), "favorite was not immediately saved")
  state.search = ""
  state.categoryIndex = 1
  local index = findEntry(visibleEntries(), 260)
  assertTrue(index ~= nil, "dynamic favorite missing from featured entries")
  state.page = math.floor((index - 1) / 8) + 1
  state.selection = ((index - 1) % 8) + 1
  pressKey(Keyboard.KEY_F)
  assertTrue(state.favorites["c:260"] == nil, "featured view did not remove favorite")
  state.search = "260"
  pressKey(Keyboard.KEY_F)
  assertTrue(state.favorites["c:260"] == true, "favorite was not restored for persistence test")
  local savesBeforeExit = TEST.saveAttempts
  onExit()
  assertEqual(TEST.saveAttempts, savesBeforeExit, "exit serialized state again")
  assertEqual(state.open, false, "exit did not close menu")
  assertEqual(TEST.hudVisible, true, "exit did not restore HUD")

  onStarted()
  assertTrue(state.favorites["c:260"] == true, "favorite did not survive restart")
  enterSearch("260")
  local removalEntries = visibleEntries()
  local removalEntry = removalEntries[(state.page - 1) * 8 + state.selection]
  assertTrue(removalEntry and removalEntry.id == 260,
    "unique ID search did not select item 260 before removal")
  pressKey(Keyboard.KEY_F)
  assertTrue(state.favorites["c:260"] == nil, "F did not remove favorite")
  state.search = ""
  state.categoryIndex = 1
  local removedIndex = findEntry(visibleEntries(), 260)
  assertTrue(removedIndex == nil, "removed dynamic favorite remains in featured entries")
end

local function testIdleRestarts()
  state.categoryIndex = 2
  state.search = "260"
  for gameIndex = 1, 20 do
    onStarted()
    for _ = 1, 5 do renderFrame() end
    local savesBeforeExit = TEST.saveAttempts
    onExit()
    assertEqual(TEST.saveAttempts, savesBeforeExit,
      "idle R restart saved on exit " .. gameIndex)
  end
  assertEqual(TEST.getItemConfigCalls, 0,
    "idle R restart eagerly built the complete catalog")
  assertEqual(TEST.worldToScreenCalls, 0,
    "closed menu entered layout/mouse rendering during idle R restart")
  assertTrue(#state.history <= 8, "idle R restart grew history")
end

local function testHistoryTwentyGames()
  local memorySamples = {}
  local payloadSizes = {}
  for gameIndex = 1, 20 do
    onStarted()
    assertTrue(#state.history <= 8, "history exceeded eight on load " .. gameIndex)
    executeSearchResult(tostring(680 + gameIndex), "giveitem c" .. tostring(680 + gameIndex))
    assertTrue(#state.history <= 8, "history exceeded eight after command " .. gameIndex)
    local savesBeforeExit = TEST.saveAttempts
    onExit()
    assertEqual(TEST.saveAttempts, savesBeforeExit, "exit save repeated in game " .. gameIndex)
    payloadSizes[#payloadSizes + 1] = #(TEST.saveData or "")
    collectgarbage("collect")
    memorySamples[#memorySamples + 1] = collectgarbage("count")
  end
  assertEqual(TEST.saveAttempts, 20, "history should save exactly once per completed command")
  assertEqual(#state.history, 8, "final history length differs")
  assertTrue(#TEST.saveData < 4096, "bounded history produced an unexpectedly large save")
  local minMemory, maxMemory = memorySamples[11], memorySamples[11]
  for index = 11, #memorySamples do
    minMemory = math.min(minMemory, memorySamples[index])
    maxMemory = math.max(maxMemory, memorySamples[index])
  end
  assertTrue(maxMemory - minMemory < 256, "Lua live memory did not stabilize across final ten games")
  local minPayload, maxPayload = payloadSizes[11], payloadSizes[11]
  for index = 11, #payloadSizes do
    minPayload = math.min(minPayload, payloadSizes[index])
    maxPayload = math.max(maxPayload, payloadSizes[index])
  end
  assertTrue(maxPayload - minPayload < 256, "save payload size did not stabilize")
end

local function testOversizedSave()
  onStarted()
  assertTrue(state.favorites["c:260"] == true, "bounded parser lost dynamic favorite")
  assertTrue(state.favorites["c:182"] == true, "bounded parser lost curated favorite")
  assertEqual(#state.history, 0, "oversized save history should be discarded")
  assertEqual(TEST.saveAttempts, 1, "oversized save was not compacted exactly once")
  assertTrue(#TEST.saveData < 65536, "compacted save remains oversized")
end

local function testUpgradeSave()
  onStarted()
  assertTrue(state.favorites["c:260"] == true, "v2.4.2 dynamic favorite did not migrate")
  assertTrue(state.favorites["c:182"] == true, "v2.4.2 curated favorite did not migrate")
  assertEqual(#state.history, 2, "v2.4.2 history did not load")
  enterSearch("260")
  pressKey(Keyboard.KEY_F)
  assertTrue(state.favorites["c:260"] == nil, "upgrade favorite mutation failed")
  assertTrue(contains(TEST.saveData, "version=2.5.4-en.3\n"), "upgrade save version missing")
  assertTrue(contains(TEST.saveData, "favorites=c:182\n"), "upgrade did not preserve curated favorite")
  assertTrue(contains(TEST.saveData, "history=giveitem c260|spawn 5.10.1"), "upgrade changed history text format")
end

local function testSaveFailureRollback()
  onStarted()
  enterSearch("260")
  pressKey(Keyboard.KEY_F)
  assertTrue(state.favorites["c:260"] == nil, "failed save did not roll favorite back")
  assertTrue(state.toast and contains(state.toast.message, "reverted"), "save failure toast is misleading")
  assertEqual(TEST.saveAttempts, 1, "save failure attempt count differs")
end

local function testLoadFailure()
  onStarted()
  assertEqual(#state.history, 0, "failed load left history behind")
  assertTrue(next(state.favorites) == nil, "failed load left favorites behind")
  assertTrue(#TEST.logs > 0, "failed load produced no diagnostic log")
end

local function testInteractions()
  onStarted()
  assertEqual(TEST.getItemConfigCalls, 0, "catalog was not deferred until the menu opened")
  openMenu()
  assertEqual(TEST.getItemConfigCalls, 1, "first menu open did not build catalog exactly once")
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE), 0.0,
    "open menu did not zero action value")
  assertEqual(onInput(registeredMod, 0, 999), false, "open menu did not block input")

  local layouts = {
    computeLayout(640, 360),
    computeLayout(1280, 720),
    computeLayout(2560, 1080),
  }
  for index, layout in ipairs(layouts) do
    assertTrue(layout.cardW > 0 and layout.cardH > 0, "invalid card size at layout " .. index)
    assertTrue(layout.gridY + layout.gridH <= layout.footerY,
      "grid overlaps footer at layout " .. index)
    assertTrue(layout.contentX + layout.contentW <= layout.panelX + layout.panelW,
      "content exceeds panel at layout " .. index)
  end

  local stageEntries
  for categoryIndex = 1, #runtimeCatalog.categories do
    state.categoryIndex = categoryIndex
    state.search = ""
    local candidates = visibleEntries()
    if candidates[1] and tostring(candidates[1].cmd or ""):match("^stage ") then
      stageEntries = candidates
      break
    end
  end
  assertTrue(stageEntries ~= nil, "stage category is missing")
  assertEqual(#stageEntries, 45, "stage category does not expose the complete normal-mode whitelist")
  local stageCommands = {}
  for _, entry in ipairs(stageEntries) do stageCommands[entry.cmd] = true end
  local expectedStages = {
    "1", "1a", "1b", "1c", "1d", "2", "2a", "2b", "2c", "2d",
    "3", "3a", "3b", "3c", "3d", "4", "4a", "4b", "4c", "4d",
    "5", "5a", "5b", "5c", "5d", "6", "6a", "6b", "6c", "6d",
    "7", "7a", "7b", "7c", "8", "8a", "8b", "8c",
    "9", "10", "10a", "11", "11a", "12", "13",
  }
  for _, stage in ipairs(expectedStages) do
    assertTrue(stageCommands["stage " .. stage] == true, "missing floor command stage " .. stage)
  end

  state.categoryIndex = 2
  state.page = 1
  state.search = ""
  pressKey(Keyboard.KEY_PAGE_DOWN)
  assertEqual(state.page, 2, "keyboard PageDown did not paginate")
  state.page = 1
  state.selection = 1
  pressButton(Controller.DPAD_DOWN)
  assertEqual(state.selection, 3, "controller down did not follow two-column grid")
  enterSearch("260")
  local oldDetailPage = state.detailPage
  pressKey(Keyboard.KEY_D)
  assertEqual(state.detailPage, oldDetailPage + 1, "D did not advance description page")

  state.search = ""
  state.categoryIndex = 2
  state.page = 1
  local layout = computeLayout(Isaac.GetScreenWidth(), Isaac.GetScreenHeight())
  clickMouse(layout.searchX + 4, layout.searchY + 4)
  assertEqual(state.inputMode, "search", "mouse click missed measured search rectangle")
  assertTrue(TEST.worldToScreenCalls > 0, "mouse position was not converted with WorldToScreen")
  pressKey(Keyboard.KEY_ESCAPE)
  state.categoryIndex = 2
  state.page = 1
  local nextPageX = layout.contentX + layout.contentW - 2
  local nextPageY = layout.panelY + layout.titleH + layout.pad * 2
  clickMouse(nextPageX, nextPageY)
  assertEqual(state.page, 2, "mouse click missed measured next-page rectangle")

  state.search = "260"
  state.categoryIndex = 2
  state.page = 1
  state.selection = 1
  clickMouse(layout.contentX + 8, layout.gridY + 8, 1)
  assertEqual(state.open, false, "right-click remove did not queue and close the menu")
  onUpdate()
  assertEqual(TEST.executed[#TEST.executed], "remove c260", "right-click remove command differs")
  openMenu()

  pressButton(Controller.BUTTON_B)
  assertEqual(state.open, false, "controller back did not close menu")
  assertEqual(TEST.hudVisible, true, "controller close did not restore HUD")
end

local function testStageSafety()
  onStarted()
  local executedBefore = #TEST.executed
  assertEqual(queueCommand("stage 14", 1), false, "nonexistent stage bypassed whitelist")
  assertTrue(state.queue == nil, "blocked nonexistent stage entered queue")
  assertTrue(state.toast and contains(state.toast.message, "safe list"),
    "blocked nonexistent stage gave no explanation")
  assertEqual(#TEST.executed, executedBefore, "blocked nonexistent stage executed")

  assertTrue(TEST_CONFIG.greedMode == true, "stage safety scenario must run in Greed mode")
  assertEqual(queueCommand("stage 1c", 1), false, "Greed mode stage command was accepted")
  assertTrue(state.queue == nil, "Greed mode stage command entered queue")
  assertTrue(state.toast and contains(state.toast.message, "Greed-mode safe list"),
    "Greed mode stage block gave no explanation")
  assertEqual(#TEST.executed, executedBefore, "Greed mode stage command executed")

  local greedStageEntries
  for categoryIndex = 1, #runtimeCatalog.categories do
    state.categoryIndex = categoryIndex
    state.search = ""
    local candidates = visibleEntries()
    if candidates[1] and candidates[1].stageMode == "greed" then
      greedStageEntries = candidates
      break
    end
  end
  assertTrue(greedStageEntries ~= nil, "Greed stage category is missing")
  assertEqual(#greedStageEntries, 7, "Greed mode must expose exactly seven documented stages")
  for index, entry in ipairs(greedStageEntries) do
    assertEqual(entry.cmd, "stage " .. index, "Greed stage order or command mismatch")
    assertEqual(entry.stageMode, "greed", "normal-mode stage leaked into Greed list")
  end

  assertEqual(queueCommand("stage 1", 1), true, "documented Greed stage was blocked")
  onUpdate()
  assertEqual(TEST.executed[#TEST.executed], "stage 1", "documented Greed stage failed")

  assertEqual(queueCommand("giveitem c182", 1), true, "Greed mode blocked a non-stage command")
  onUpdate()
  assertEqual(TEST.executed[#TEST.executed], "giveitem c182", "Greed mode non-stage command failed")
end

local function testController()
  onStarted()
  assertEqual(TEST.getItemConfigCalls, 0, "controller scenario eagerly built catalog")
  assertTrue((TEST_CONFIG.controllerIndex or 0) > 0,
    "controller scenario must verify a non-zero controller index")
  local physicalConfirm = TEST_CONFIG.physicalConfirmButton or Controller.BUTTON_A
  local physicalFavorite = TEST_CONFIG.physicalFavoriteButton or Controller.BUTTON_X
  local physicalBack = TEST_CONFIG.physicalBackButton or Controller.BUTTON_B
  holdButton(Controller.STICK_LEFT, 29)
  assertEqual(state.open, false, "L3 hold opened before the 30-frame threshold")
  holdButton(Controller.STICK_LEFT, 1)
  assertEqual(state.open, true, "30-frame L3 hold did not open the menu")
  assertEqual(state.controllerIndex, TEST_CONFIG.controllerIndex,
    "controller opener did not capture the active controller index")
  assertEqual(TEST.getItemConfigCalls, 1, "controller open did not lazy-load catalog")
  holdButton(Controller.STICK_LEFT, 2)
  assertEqual(state.open, true, "held L3 was misread as a second trigger after opening")
  releaseButton(Controller.STICK_LEFT)

  state.categoryIndex = 2
  state.page = 1
  state.search = ""
  state.selection = 1
  local layout = computeLayout(Isaac.GetScreenWidth(), Isaac.GetScreenHeight())
  TEST.mousePosition = Vector(layout.contentX + 8, layout.gridY + 8)
  renderFrame()
  assertEqual(state.selection, 1, "mouse hover did not select its card")
  pressButton(Controller.DPAD_DOWN)
  assertEqual(state.selection, 3, "controller direction did not move the selection")
  renderFrame()
  assertEqual(state.selection, 3, "stationary mouse cursor stole controller focus")
  assertEqual(state.controlMode, "controller", "controller input did not switch the help mode")
  state.page = 1
  state.selection = 7
  pressButton(Controller.DPAD_DOWN)
  assertEqual(state.page, 2, "D-pad did not automatically cross to the next page")
  assertEqual(state.selection, 1, "automatic page crossing selected the wrong card")

  enterSearch("260")
  local executedBeforeFavorite = #TEST.executed
  pressButton(physicalFavorite)
  assertTrue(state.favorites["c:260"] == true, "controller favorite action failed")
  assertEqual(#TEST.executed, executedBeforeFavorite,
    "controller favorite was misrouted to command execution")

  startHeldButton(physicalConfirm)
  holdButton(physicalConfirm, 29)
  assertEqual(state.open, true, "controller long-A removed before the 30-frame threshold")
  holdButton(physicalConfirm, 1)
  assertEqual(state.open, false, "controller long-A did not close menu for queued remove")
  releaseButton(physicalConfirm)
  local executedBeforeRemove = #TEST.executed
  onUpdate()
  assertEqual(TEST.executed[#TEST.executed], "remove c260", "controller remove command differs")
  for _ = 1, 300 do
    TEST.frame = TEST.frame + 1
    onUpdate()
  end
  assertEqual(#TEST.executed, executedBeforeRemove + 1,
    "single remove repeated after its 1/1 queue completed")
  assertEqual(state.queue, nil, "completed remove queue remained active")

  openMenu()
  local executedBeforeConfirm = #TEST.executed
  startHeldButton(physicalConfirm)
  assertEqual(state.open, true, "controller short-A executed before release")
  releaseButton(physicalConfirm)
  assertEqual(state.open, false, "controller short-A did not queue the selected command on release")
  onUpdate()
  assertEqual(#TEST.executed, executedBeforeConfirm + 1, "controller confirm did not execute once")
  assertEqual(TEST.executed[#TEST.executed], "giveitem c260", "controller confirm executed wrong command")

  openMenu()
  pressButton(physicalBack)
  assertEqual(state.open, false, "controller back did not close menu")
  assertEqual(TEST.hudVisible, true, "controller back did not restore HUD")

  openMenu()
  pressButton(Controller.STICK_LEFT)
  assertEqual(state.open, false, "L3 did not close an open menu")
end

local function testColdStartControllerFocus()
  onStarted()
  local controllerIndex = TEST_CONFIG.controllerIndex or 0
  if TEST_CONFIG.openWithController then
    holdButton(Controller.STICK_LEFT, 30, controllerIndex)
    releaseButton(Controller.STICK_LEFT, controllerIndex)
  else
    openMenu()
  end

  if TEST_CONFIG.initialFavorite then
    local entries = visibleEntries()
    local entry = entries[(state.page - 1) * 8 + state.selection]
    assertEqual(state.categoryIndex, 1, "non-empty Featured did not remain the initial view")
    assertEqual(entry and entry.objectKey, "c:182", "saved favorite was not selected on first open")
    return
  end

  assertEqual(state.categoryIndex, 2, "empty Featured did not advance to Collectibles on first open")
  assertEqual(state.selection, 1, "first Collectibles entry was not selected")
  assertEqual(state.sidebarFocus, false, "non-empty Collectibles opened with sidebar focus")

  state.selection = 1
  pressDirection(ButtonAction.ACTION_MENUDOWN, Controller.DPAD_DOWN, controllerIndex, true)
  assertEqual(state.selection, 3, "logical/raw duplicate direction moved more than once")
  assertEqual(state.controllerIndex, controllerIndex, "logical direction did not capture controller index")
  assertEqual(state.controlMode, "controller", "logical direction did not activate controller mode")

  pressDirection(ButtonAction.ACTION_MENUUP, Controller.DPAD_UP, controllerIndex, false)
  assertEqual(state.selection, 1, "logical menu up did not move the grid selection")
  pressDirection(ButtonAction.ACTION_MENULEFT, Controller.DPAD_LEFT, controllerIndex, false)
  assertEqual(state.sidebarFocus, true, "logical menu left did not enter the sidebar")
  pressDirection(ButtonAction.ACTION_MENUDOWN, Controller.DPAD_DOWN, controllerIndex, false)
  assertEqual(state.categoryIndex, 3, "logical menu down did not navigate the sidebar")
  pressDirection(ButtonAction.ACTION_MENURIGHT, Controller.DPAD_RIGHT, controllerIndex, false)
  assertEqual(state.sidebarFocus, false, "logical menu right did not leave the sidebar")

  pressKey(Keyboard.KEY_F6)
  state.categoryIndex = 1
  state.search = ""
  onStarted()
  pressKey(Keyboard.KEY_F6)
  assertEqual(state.categoryIndex, 1, "empty Featured was forced away after the process-first open")
end

local function testOfficialImmediateGrant()
  onStarted()
  openMenu()
  local physicalConfirm = TEST_CONFIG.physicalConfirmButton or Controller.BUTTON_A

  local function selectCommand(command, categoryId)
    state.search = ""
    for categoryIndex = 1, #runtimeCatalog.categories do
      state.categoryIndex = categoryIndex
      local candidates = visibleEntries()
      for entryIndex, entry in ipairs(candidates) do
        if entry.cmd == command and (categoryId == nil or entry.cat == categoryId) then
          state.page = math.floor((entryIndex - 1) / 8) + 1
          state.selection = ((entryIndex - 1) % 8) + 1
          state.sidebarFocus = false
          return entry, candidates
        end
      end
    end
    fail("command entry was not found: " .. tostring(command))
  end

  local dollar = selectCommand("giveitem c18", "supply")
  assertEqual(dollar.reversible, nil, "one-time coin supply still uses a manual reversibility flag")
  assertEqual(removalCommand(dollar), nil,
    "ItemConfig AddCoins grant still generates a misleading remove c18 action")
  state.controlMode = "controller"
  TEST.rendered = {}
  renderFrame()
  local sawExecuteHint, sawRemoveHint = false, false
  for _, value in ipairs(TEST.rendered) do
    if contains(value, "A: run") then sawExecuteHint = true end
    if contains(value, "Hold A") and contains(value, "remove") then sawRemoveHint = true end
  end
  assertTrue(sawExecuteHint, "official immediate grant does not show the A execute hint")
  assertEqual(sawRemoveHint, false, "official immediate grant still advertises long-A removal")

  local executedBeforeTap = #TEST.executed
  startHeldButton(physicalConfirm)
  releaseButton(physicalConfirm)
  onUpdate()
  assertEqual(#TEST.executed, executedBeforeTap + 1,
    "short-A did not execute the official immediate grant once")
  assertEqual(TEST.executed[#TEST.executed], "giveitem c18",
    "short-A executed the wrong official immediate grant command")

  openMenu()
  selectCommand("giveitem c18", "supply")
  local executedBeforeHold = #TEST.executed
  startHeldButton(physicalConfirm)
  holdButton(physicalConfirm, 29)
  assertEqual(state.open, true, "official immediate grant closed before the hold threshold")
  holdButton(physicalConfirm, 1)
  assertEqual(state.open, true, "official immediate grant long hold closed the menu")
  assertTrue(state.toast and contains(state.toast.message, "grants resources immediately"),
    "official immediate grant long hold gave no ItemConfig-based warning")
  releaseButton(physicalConfirm)
  onUpdate()
  assertEqual(#TEST.executed, executedBeforeHold,
    "official immediate grant long hold executed a give/remove command")
  assertEqual(state.queue, nil, "official immediate grant long hold left a queue")

  local _, supplyEntries = selectCommand("giveitem c18", "supply")
  local layout = computeLayout(Isaac.GetScreenWidth(), Isaac.GetScreenHeight())
  local localIndex = state.selection
  local column = (localIndex - 1) % 2
  local row = math.floor((localIndex - 1) / 2)
  clickMouse(layout.contentX + column * (layout.cardW + layout.gap) + 5,
    layout.gridY + row * (layout.cardH + layout.gap) + 5, 1)
  assertEqual(state.open, true, "right-click on official immediate grant closed the menu")
  assertEqual(state.queue, nil, "right-click on official immediate grant queued a command")
  assertTrue(state.toast and contains(state.toast.message, "ItemConfig") == false
      and contains(state.toast.message, "grants resources immediately"),
    "right-click on official immediate grant gave no user-facing resource warning")
  assertTrue(#supplyEntries > 0, "supply category unexpectedly empty")

  selectCommand("spawn 5.10.3", "supply")
  local executedBeforeSpawnHold = #TEST.executed
  startHeldButton(physicalConfirm)
  holdButton(physicalConfirm, 30)
  releaseButton(physicalConfirm)
  onUpdate()
  assertEqual(#TEST.executed, executedBeforeSpawnHold,
    "long-A executed a spawn command without an inverse")
  assertTrue(state.toast and contains(state.toast.message, "no removable item"),
    "long-A spawn rejection gave no removal warning")

  local normalItem = selectCommand("giveitem c260")
  assertEqual(removalCommand(normalItem), "remove c260",
    "ordinary collectible lost its remove command")
end

local function testQueueInvariant()
  onStarted()
  enterSearch("331")
  startHeldButton(Controller.BUTTON_A)
  holdButton(Controller.BUTTON_A, 30)
  assertTrue(state.queue ~= nil, "remove queue was not created")
  state.queue.done = 235
  TEST.rendered = {}
  renderFrame()
  local showedClampedProgress = false
  for _, value in ipairs(TEST.rendered) do
    if contains(value, "Running 1/1  remove c331") then showedClampedProgress = true end
    assertTrue(not contains(value, "235/1"), "queue renderer exposed progress beyond total")
  end
  assertTrue(showedClampedProgress, "queue renderer did not clamp corrupted progress")
  local executedBefore = #TEST.executed
  onUpdate()
  assertEqual(#TEST.executed, executedBefore,
    "already-complete corrupted queue executed an extra command")
  assertEqual(state.queue, nil, "corrupted completed queue was not finalized")
end

local function testMeasuredFooterAndStars()
  onStarted()
  openMenu()
  TEST.rendered = {}
  renderFrame()
  local exactVersion, exactGroup, exactSummary = false, false, false
  for _, value in ipairs(TEST.rendered) do
    if value == "v2.5.4-en.3" then exactVersion = true end
    if value == "1/3" then exactGroup = true end
    if value == "The complete collectible catalog from the current game version, with high-quality items first."
        or value == "All official collectibles." or value == "COLLECTIBLES" then exactSummary = true end
  end
  assertTrue(exactVersion, "low-resolution version label was truncated")
  assertTrue(exactGroup, "low-resolution category page label was truncated")
  assertTrue(exactSummary, "low-resolution category summary was truncated")

  state.inputMode = "search"
  state.search = ""
  TEST.rendered = {}
  renderFrame()
  local exactSearchHelp, exactSearchKeys = false, false
  for _, value in ipairs(TEST.rendered) do
    if value == "Name / alias / ID" then exactSearchHelp = true end
    if value == "Ctrl+A · Enter · Esc" then exactSearchKeys = true end
  end
  assertTrue(exactSearchHelp, "low-resolution search help was truncated")
  assertTrue(exactSearchKeys, "low-resolution search key help was truncated")
  state.inputMode = nil

  enterSearch("182")
  TEST.rendered = {}
  renderFrame()
  local exactTitle = false
  local exactCommand = false
  local completeHint = false
  local emptyStar = false
  local hoverFavoriteText = false
  local visibleRemoveButton = false
  for _, value in ipairs(TEST.rendered) do
    if value == "Sacred Heart" then exactTitle = true end
    if value == "Command: giveitem c182" then exactCommand = true end
    if contains(value, "F: favorite") and not contains(value, "...") then completeHint = true end
    if value == "☆" then emptyStar = true end
    if value == "Favorite" then hoverFavoriteText = true end
    if value == "Remove" then visibleRemoveButton = true end
  end
  assertTrue(exactTitle, "English detail title was truncated or duplicated")
  assertTrue(exactCommand, "detail command was truncated")
  assertTrue(completeHint, "footer action hint was truncated")
  assertEqual(emptyStar, false, "unfavorited cards still render an empty star")
  assertEqual(hoverFavoriteText, false, "unfavorited cards render a favorite text action")
  assertEqual(visibleRemoveButton, false, "cards still render the redundant remove text column")

  state.search = "260"
  state.page = 1
  state.selection = 1
  pressKey(Keyboard.KEY_F)
  state.categoryIndex = 2
  state.search = "260"
  state.controlMode = "controller"
  TEST.rendered = {}
  renderFrame()
  local fontStar = false
  local controllerHint = false
  local controllerRemoveHint = false
  local legacyR3Hint = false
  local mouseHint = false
  for _, value in ipairs(TEST.rendered) do
    if value == "★" then fontStar = true end
    if contains(value, "X: unfavorite") or contains(value, "X:-fav") then controllerHint = true end
    if (contains(value, "Hold A") and contains(value, "remove")) or contains(value, "HoldA:rm") then
      controllerRemoveHint = true
    end
    if contains(value, "R3") then legacyR3Hint = true end
    if contains(value, "LMB") or contains(value, "RMB") then mouseHint = true end
  end
  assertEqual(fontStar, false, "favorite marker still depends on a missing font glyph")
  assertTrue(controllerHint, "controller mode did not render controller-specific help")
  assertTrue(controllerRemoveHint, "controller mode did not render long-A remove help")
  assertEqual(legacyR3Hint, false, "controller help still advertises R3 removal")
  assertEqual(mouseHint, false, "controller mode still rendered mouse-only help")
  local rendersBeforeStar = TEST.spriteRenders
  drawFavoriteStar(0, 0, 20, 20)
  assertTrue(TEST.spriteRenders > rendersBeforeStar, "favorite pixel star rendered no geometry")

  state.search = ""
  state.categoryIndex = 1
  state.controlMode = "keyboard"
  TEST.rendered = {}
  renderFrame()
  local featuredCancelHint = false
  for _, value in ipairs(TEST.rendered) do
    if contains(value, "F: unfavorite") or contains(value, "F:-fav") then featuredCancelHint = true end
  end
  assertTrue(featuredCancelHint, "featured view did not expose favorite cancellation")

  pressKey(Keyboard.KEY_F)
  TEST.rendered = {}
  renderFrame()
  local emptyTitle, emptyHint = false, false
  for _, value in ipairs(TEST.rendered) do
    if value == "No favorites yet" then emptyTitle = true end
    if value == "Press F / X in another category to add one" then emptyHint = true end
  end
  assertTrue(emptyTitle and emptyHint, "empty featured guidance was not rendered")
end

local function testFontFallback()
  assertTrue(TEST_CONFIG.repPlus, "fallback scenario must use Repentance+")
  assertTrue(#TEST.fontLoads >= 2, "bundled font pair was not attempted")
  local foundFusion = false
  for _, path in ipairs(TEST.fontLoads) do
    if contains(path, "fusion/10.fnt") or contains(path, "fusion/12.fnt") then foundFusion = true end
    assertTrue(not contains(path, ".zh/font/"), "English edition tried a locale-specific font")
  end
  assertTrue(foundFusion, "bundled Fusion Pixel font was not loaded")
  onStarted()
  openMenu()
  renderFrame()
end

local function testFontFailurePage()
  onStarted()
  openMenu()
  renderFrame()
  local foundFailure = false
  for _, text in ipairs(TEST.rendered) do
    if contains(text, "FONT LOAD FAILED - MENU DISABLED") then foundFailure = true end
  end
  assertTrue(foundFailure, "all-font failure did not render English diagnostic page")
end

local function testMcmKeybind()
  assertTrue(TEST_CONFIG.mcm, "MCM keybind scenario requires optional MCM")
  onStarted()
  assertEqual(TEST.mcmAddCalls, 3, "MCM settings were not registered exactly once each")
  assertEqual(TEST.mcmCategory, "Console UI", "MCM category changed")
  assertEqual(TEST.mcmSubcategory, "Settings", "MCM subcategory changed")
  assertTrue(type(TEST.mcmSetting) == "table", "MCM keybind setting missing")
  assertEqual(TEST.mcmSetting.CurrentSetting(), Keyboard.KEY_F6, "MCM default key differs")

  TEST.mcmSetting.OnChange(Keyboard.KEY_F7)
  assertEqual(state.openKey, Keyboard.KEY_F7, "valid MCM key was not applied")
  assertTrue(contains(TEST.saveData, "openKey=296\n"), "custom open key was not persisted")
  pressKey(Keyboard.KEY_F6)
  assertEqual(state.open, false, "F6 remained active after replacement")
  pressKey(Keyboard.KEY_F7)
  assertEqual(state.open, true, "custom key did not open menu")
  pressKey(Keyboard.KEY_F7)
  assertEqual(state.open, false, "custom key did not close menu")

  local attempts = TEST.saveAttempts
  TEST.mcmSetting.OnChange(Keyboard.KEY_R)
  assertEqual(state.openKey, Keyboard.KEY_F7, "reserved key replaced the valid binding")
  assertEqual(TEST.saveAttempts, attempts, "reserved key attempted persistence")

  TEST_CONFIG.saveFail = true
  TEST.mcmSetting.OnChange(Keyboard.KEY_F8)
  assertEqual(state.openKey, Keyboard.KEY_F7, "failed keybind save did not roll back")
  TEST_CONFIG.saveFail = false

  state.loaded = false
  onStarted()
  assertEqual(state.openKey, Keyboard.KEY_F7, "persisted custom key did not reload")
  assertEqual(TEST.mcmAddCalls, 3, "rewind duplicated the MCM settings")
end

local function testEidOverlayIsolation()
  assertTrue(TEST_CONFIG.eid, "EID overlay scenario requires EID")
  onStarted()
  EID.isHidden = false
  openMenu()
  assertEqual(EID.isHidden, true, "opening Console UI did not hide EID")
  EID.isHidden = false
  renderFrame()
  assertEqual(EID.isHidden, true, "open Console UI did not keep EID hidden")
  pressKey(Keyboard.KEY_F6)
  assertEqual(EID.isHidden, false, "closing Console UI did not restore visible EID")

  EID.isHidden = true
  openMenu()
  assertEqual(EID.isHidden, true, "opening changed an already hidden EID")
  pressKey(Keyboard.KEY_ESCAPE)
  assertEqual(EID.isHidden, true, "closing changed the user's hidden EID state")

  EID.isHidden = false
  openMenu()
  onExit()
  assertEqual(EID.isHidden, false, "game exit did not restore EID visibility")
end
local function testToastRestartLifecycle()
  onStarted()
  state.startupHintShown = true

  -- Normal R restart: the game frame resets before MC_POST_GAME_STARTED.
  TEST.frame = 120
  state.lastGameFrame = TEST.frame
  state.toast = { message = "previous toast", color = Color(1, 1, 1, 1) }
  state.toastFramesRemaining = 60
  TEST.frame = 0
  onStarted()
  assertEqual(state.toast, nil, "R restart retained the previous toast")
  assertEqual(state.toastFramesRemaining, 0, "R restart retained the previous toast countdown")
  TEST.rendered = {}
  renderFrame()
  for _, value in ipairs(TEST.rendered) do
    assertTrue(value ~= "previous toast", "previous toast rendered after R restart")
  end


  -- Rerun can reset the game frame after MC_POST_GAME_STARTED. The first
  -- update must discard any Toast created against the pre-reset run.
  TEST.frame = 240
  state.startupHintShown = false
  onStarted()
  assertTrue(state.toast ~= nil, "pre-reset Rerun setup did not create a startup Toast")
  TEST.frame = 0
  onUpdate()
  assertEqual(state.toast, nil, "post-callback Rerun frame reset retained a Toast")
  assertEqual(state.toastFramesRemaining, 0, "post-callback Rerun retained the Toast countdown")

  -- Also protect runtimes that reset the frame without the normal new-game
  -- callback sequence.
  state.startupHintShown = true
  TEST.frame = 360
  state.lastGameFrame = TEST.frame
  state.toast = { message = "rerun toast", color = Color(1, 1, 1, 1) }
  state.toastFramesRemaining = 60
  state.queue = { command = "giveitem c1", total = 2, done = 0, nextFrame = 360 }
  TEST.frame = 0
  onUpdate()
  assertEqual(state.toast, nil, "callback-less Rerun retained a Toast")
  assertEqual(state.queue, nil, "callback-less Rerun retained an execution queue")

  -- Ordinary Toast duration remains measured in game update frames.
  state.toast = { message = "short toast", color = Color(1, 1, 1, 1) }
  state.toastFramesRemaining = 3
  state.lastGameFrame = 0
  for frame = 1, 2 do
    TEST.frame = frame
    onUpdate()
    assertTrue(state.toast ~= nil, "Toast expired before its requested duration")
  end
  TEST.frame = 3
  onUpdate()
  assertEqual(state.toast, nil, "Toast did not expire after its requested duration")
end
local function testCtrlAIsolation()
  onStarted()
  openMenu()
  pressKey(Keyboard.KEY_SLASH)
  pressKey(Keyboard.KEY_A)
  pressKey(Keyboard.KEY_A + 1)
  pressKey(Keyboard.KEY_A + 2)
  assertEqual(state.search, "abc", "search setup failed")

  TEST.buttonPressed[Keyboard.KEY_LEFT_CONTROL] = { [0] = true }
  TEST.keyTriggers[Keyboard.KEY_A] = true
  renderFrame()
  TEST.buttonPressed[Keyboard.KEY_LEFT_CONTROL] = { [0] = false }
  assertEqual(state.search, "abc", "Ctrl+A appended a character")
  assertEqual(state.searchSelectAll, true, "Ctrl+A did not select the search text")
  pressKey(Keyboard.KEY_D)
  assertEqual(state.search, "d", "typing did not replace the selected search text")
  assertEqual(state.searchSelectAll, false, "replacement did not clear selection state")

  TEST.buttonPressed[Keyboard.KEY_RIGHT_CONTROL] = { [0] = true }
  TEST.keyTriggers[Keyboard.KEY_A] = true
  renderFrame()
  TEST.buttonPressed[Keyboard.KEY_RIGHT_CONTROL] = { [0] = false }
  pressKey(Keyboard.KEY_DELETE)
  assertEqual(state.search, "", "Delete did not clear selected search text")

  state.search = "260"
  state.inputMode = "search"
  TEST.buttonPressed[Keyboard.KEY_LEFT_CONTROL] = { [0] = true }
  TEST.keyTriggers[Keyboard.KEY_A] = true
  renderFrame()
  TEST.buttonPressed[Keyboard.KEY_LEFT_CONTROL] = { [0] = false }
  pressKey(Keyboard.KEY_ENTER)
  assertEqual(state.search, "260", "Enter changed selected search text")
  assertEqual(state.searchSelectAll, false, "Enter did not reset selection state")

  state.manualCommand = "giveitem c182"
  state.inputMode = "command"
  TEST.buttonPressed[Keyboard.KEY_LEFT_CONTROL] = { [0] = true }
  TEST.keyTriggers[Keyboard.KEY_A] = true
  renderFrame()
  TEST.buttonPressed[Keyboard.KEY_LEFT_CONTROL] = { [0] = false }
  assertEqual(state.manualCommand, "giveitem c182", "Ctrl+A affected the manual command field")
  assertEqual(state.searchSelectAll, false, "manual command Ctrl+A leaked search selection state")

  pressKey(Keyboard.KEY_F6)
  TEST.buttonPressed[Keyboard.KEY_LEFT_CONTROL] = { [0] = true }
  TEST.keyTriggers[Keyboard.KEY_A] = true
  renderFrame()
  TEST.buttonPressed[Keyboard.KEY_LEFT_CONTROL] = { [0] = false }
  assertEqual(state.open, false, "Ctrl+A opened or changed a closed menu")
end

local function testMcmSettings254()
  assertTrue(TEST_CONFIG.mcm, "MCM 2.5.4 scenario requires optional MCM")
  onStarted()
  assertEqual(TEST.mcmAddCalls, 3, "MCM did not register all three settings")
  local favoriteSetting, startupSetting
  for _, setting in ipairs(TEST.mcmSettings) do
    if setting.Type == ModConfigMenu.OptionType.KEYBIND_CONTROLLER then favoriteSetting = setting end
    if setting.Type == ModConfigMenu.OptionType.BOOLEAN then startupSetting = setting end
  end
  assertTrue(type(favoriteSetting) == "table", "controller favorite setting missing")
  assertTrue(type(startupSetting) == "table", "startup hint setting missing")
  assertEqual(favoriteSetting.CurrentSetting(), -1, "controller favorite default is not Automatic")
  assertEqual(startupSetting.CurrentSetting(), true, "startup hint default is not enabled")

  startupSetting.OnChange(false)
  assertEqual(state.startupHintEnabled, false, "startup hint setting did not turn off")
  assertTrue(contains(TEST.saveData, "startupHintEnabled=0\n"), "startup hint setting was not persisted")
  favoriteSetting.OnChange(9)
  assertEqual(state.controllerFavoriteButton, 9, "custom favorite button was not applied")
  assertTrue(contains(TEST.saveData, "controllerFavoriteButton=9\n"), "custom favorite button was not persisted")
  favoriteSetting.OnChange(32)
  assertEqual(state.controllerFavoriteButton, 9, "invalid favorite button replaced the binding")

  TEST_CONFIG.saveFail = true
  startupSetting.OnChange(true)
  assertEqual(state.startupHintEnabled, false, "failed startup setting save did not roll back")
  favoriteSetting.OnChange(10)
  assertEqual(state.controllerFavoriteButton, 9, "failed favorite setting save did not roll back")
  TEST_CONFIG.saveFail = false

  state.loaded = false
  onStarted()
  assertEqual(state.startupHintEnabled, false, "startup hint setting did not reload")
  assertEqual(state.controllerFavoriteButton, 9, "favorite button setting did not reload")
end
local function findObject(key)
  for _, entry in ipairs(allEntries) do
    if entry.objectKey == key then return entry end
  end
  return nil
end

local function searchContains(query, key)
  state.search = query
  for _, entry in ipairs(visibleEntries()) do
    if entry.objectKey == key then return true end
  end
  return false
end

local function selectSearchObject(query, key)
  state.search = query
  state.page = 1
  state.selection = 1
  local entries = visibleEntries()
  for index, entry in ipairs(entries) do
    if entry.objectKey == key then
      state.page = math.floor((index - 1) / 8) + 1
      state.selection = ((index - 1) % 8) + 1
      return
    end
  end
  fail("search object missing: " .. tostring(query) .. " -> " .. tostring(key))
end

local function testOfficialObjects()
  onStarted()
  assertEqual(TEST.getItemConfigCalls, 0, "official objects loaded before opening menu")
  openMenu()

  local counts = { c = 0, t = 0, k = 0, p = 0 }
  for _, entry in ipairs(allEntries) do
    if counts[entry.objectType] ~= nil then counts[entry.objectType] = counts[entry.objectType] + 1 end
  end
  assertEqual(counts.c, 721, "valid collectible count differs")
  assertEqual(counts.t, 188, "valid trinket count differs")
  assertEqual(counts.k, 97, "valid card/rune count differs")
  assertEqual(counts.p, 50, "valid pill-effect count differs")
  assertTrue(findObject("t:47") == nil, "empty official trinket ID 47 was generated")

  if TEST_CONFIG.eid then
    assertEqual(findObject("t:1").desc, "Spawns 1 coin when Isaac is hit", "trinket EID description missing")
    assertEqual(findObject("k:1").desc, "Teleports Isaac to the starting room", "card EID description missing")
    assertEqual(findObject("p:1").desc, "Deals one heart of damage to Isaac", "pill EID description missing")
  end

  for _, query in ipairs({ "giveitem k1", "k1", "The Fool", "the fool" }) do
    assertTrue(searchContains(query:lower(), "k:1"), "The Fool search failed: " .. query)
  end
  assertTrue(not searchContains("g k1", "k:1"), "short-command normalization changed search behavior")

  for _, spec in ipairs({
      { "giveitem c1", "c:1" }, { "giveitem t1", "t:1" },
      { "giveitem k1", "k:1" }, { "giveitem p1", "p:1" },
    }) do
    selectSearchObject(spec[1], spec[2])
    pressKey(Keyboard.KEY_F)
    assertTrue(state.favorites[spec[2]] == true, "typed favorite failed: " .. spec[2])
    assertTrue(contains(TEST.saveData, spec[2]), "typed favorite was not persisted: " .. spec[2])
  end

  state.search = ""
  state.categoryIndex = 1
  local featuredKeys = {}
  for _, entry in ipairs(visibleEntries()) do featuredKeys[entry.objectKey] = true end
  for _, key in ipairs({ "c:1", "t:1", "k:1", "p:1" }) do
    assertTrue(featuredKeys[key] == true, "typed favorite missing from featured: " .. key)
  end

  assertEqual(removalCommand(findObject("t:1")), "remove t1", "trinket removal command differs")
  assertEqual(removalCommand(findObject("k:1")), nil, "card unexpectedly exposes removal")
  assertEqual(removalCommand(findObject("p:1")), nil, "pill unexpectedly exposes removal")

  local executedBefore = #TEST.executed
  assertTrue(queueEntry(findObject("k:1"), 99), "card queue rejected")
  assertEqual(state.queue.total, 1, "card entry inherited batch execution")
  onUpdate()
  assertEqual(#TEST.executed, executedBefore + 1, "card entry executed an unexpected count")
  assertEqual(TEST.executed[#TEST.executed], "giveitem k1", "card command differs")

  onStarted()
  for _, key in ipairs({ "c:1", "t:1", "k:1", "p:1" }) do
    assertTrue(state.favorites[key] == true, "typed favorite did not survive restart: " .. key)
  end
end

local scenarios = {
  search = testSearch,
  favorite = testFavorite,
  idle_restarts = testIdleRestarts,
  history20 = testHistoryTwentyGames,
  oversized = testOversizedSave,
  upgrade = testUpgradeSave,
  save_failure = testSaveFailureRollback,
  load_failure = testLoadFailure,
  interactions = testInteractions,
  stage_safety = testStageSafety,
  controller = testController,
  cold_start_focus = testColdStartControllerFocus,
  official_immediate_grant = testOfficialImmediateGrant,
  queue_invariant = testQueueInvariant,
  measured_footer_stars = testMeasuredFooterAndStars,
  font_fallback = testFontFallback,
  font_failure = testFontFailurePage,
  mcm_keybind = testMcmKeybind,
  eid_overlay = testEidOverlayIsolation,
  toast_restart = testToastRestartLifecycle,
  ctrl_a_isolation = testCtrlAIsolation,
  mcm_settings_254 = testMcmSettings254,
  official_objects = testOfficialObjects,
}

local scenario = scenarios[TEST_CONFIG.scenario]
assertTrue(type(scenario) == "function", "unknown scenario: " .. tostring(TEST_CONFIG.scenario))
scenario()
print("MOCK PASS " .. tostring(TEST_CONFIG.label or TEST_CONFIG.scenario))
