-- Integration harness for workshop-mod/main.lua. It executes the real Mod
-- entry point against a deterministic Isaac API mock and drives registered
-- callbacks with keyboard, mouse and controller input.

assert(type(MOD_ROOT) == "string" and MOD_ROOT ~= "", "MOD_ROOT is required")
TEST_CONFIG = TEST_CONFIG or {}
local IS_ZH = TEST_CONFIG.language == "zh"


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
  callbackLists = {},
  keyTriggers = {},
  buttonTriggers = {},
  actionTriggers = {},
  actionValues = {},
  actionPressed = {},
  buttonPressed = {},
  buttonPressedCalls = 0,
  mouseButtons = { false, false },
  mousePosition = { X = 0, Y = 0 },
  frame = 0,
  hudVisible = true,
  saveAttempts = 0,
  saveData = nil,
  executed = {},
  logs = {},
  rendered = {},
  captureGeometry = false,
  renderRecords = {},
  fontLoads = {},
  mcmAddCalls = 0,
  mcmSetting = nil,
  mcmSettings = {},
  spriteRenders = 0,
  spriteRecords = {},
  spriteColors = {},
  worldToScreenCalls = 0,
  getItemConfigCalls = 0,
  getCollectibleCalls = 0,
  getTrinketCalls = 0,
  getCardCalls = 0,
  getPillEffectCalls = 0,
  paused = false,
}

if TEST_CONFIG.scenario == "oversized" then
  TEST.saveData = "version=2.4.2\nfavorites=260,182\nhistory=" .. string.rep("x", 70000)
elseif TEST_CONFIG.scenario == "upgrade" then
  TEST.saveData = "version=2.4.2\nfavorites=260,182\nhistory=giveitem c260|spawn 5.10.1"
elseif TEST_CONFIG.initialFavorite then
  TEST.saveData = "version=2.5.4-en.2\nfavorites=c:182\nhistory="
end

REPENTANCE_PLUS = TEST_CONFIG.repPlus == true
REPENTOGON = TEST_CONFIG.repentogon == true and {} or nil

function Color(...)
  local value = { ... }
  value.__isaacColorType = "Color"
  return value
end
function KColor(...)
  local value = { ... }
  value.__isaacColorType = "KColor"
  return value
end
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
    self.lineHeight = tonumber(TEST_CONFIG.fontLineHeight)
      or (self.path:find("12", 1, true) and 12 or 10)
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
  function font:DrawStringUTF8(value, x, y, color, width, centered)
    if color ~= nil and color.__isaacColorType ~= "KColor" then
      error("Font:DrawStringUTF8 expected KColor")
    end
    local text = tostring(value or "")
    TEST.rendered[#TEST.rendered + 1] = text
    if TEST.captureGeometry then
      TEST.renderRecords[#TEST.renderRecords + 1] = {
        text = text, x = tonumber(x) or 0, y = tonumber(y) or 0,
        width = tonumber(width) or 0, centered = centered == true,
      }
    end
  end
  return font
end

function Sprite()
  local sprite = {}
  function sprite:Load() end
  function sprite:Play() end
  function sprite:Render(position)
    if self.Color ~= nil and self.Color.__isaacColorType ~= "Color" then
      error("Sprite:Render expected Color")
    end
    TEST.spriteRenders = TEST.spriteRenders + 1
    if TEST.captureGeometry then
      TEST.spriteRecords[#TEST.spriteRecords + 1] = {
        x = position and tonumber(position.X) or 0,
        y = position and tonumber(position.Y) or 0,
        width = self.Scale and tonumber(self.Scale.X) or 0,
        height = self.Scale and tonumber(self.Scale.Y) or 0,
      }
    end
    local color = self.Color or {}
    TEST.spriteColors[#TEST.spriteColors + 1] = table.concat({
      tostring(color[1]), tostring(color[2]), tostring(color[3]), tostring(color[4]),
    }, ",")
  end
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
  ACTION_RESTART = 17,
  ACTION_JOINMULTIPLAYER = 19,
}
if TEST_CONFIG.repPlus then
  ButtonAction.ACTION_MENULB = 15
  ButtonAction.ACTION_MENURB = 16
end
Controller = {
  DPAD_LEFT = 0, DPAD_RIGHT = 1, DPAD_UP = 2, DPAD_DOWN = 3,
  BUTTON_A = 4, BUTTON_B = 5, BUTTON_X = 6, BUTTON_Y = 7,
  BUMPER_LEFT = 8, TRIGGER_LEFT = 9, STICK_LEFT = 10,
  BUMPER_RIGHT = 11, TRIGGER_RIGHT = 12, STICK_RIGHT = 13,
  BUTTON_BACK = 14, BUTTON_START = 15,
}
Challenge = { NUM_CHALLENGES = 46 }

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
  TEST.buttonPressedCalls = TEST.buttonPressedCalls + 1
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
function game:GetNumPlayers()
  return type(TEST_CONFIG.playerControllerIndexes) == "table"
    and #TEST_CONFIG.playerControllerIndexes or 1
end
function Input.GetActionValue(action, controllerIndex)
  if TEST_CONFIG.actionsUnavailable then return 0 end
  local byController = TEST.actionValues[action]
  local value = type(byController) == "table" and byController[controllerIndex or 0] or 0
  return tonumber(value) or 0
end
function game:IsGreedMode() return TEST_CONFIG.greedMode == true end
function game:IsPaused() return TEST.paused end
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
function Isaac.GetPlayer(index)
  local assigned = type(TEST_CONFIG.playerControllerIndexes) == "table"
    and TEST_CONFIG.playerControllerIndexes[(index or 0) + 1] or nil
  return { ControllerIndex = assigned or TEST_CONFIG.controllerIndex or 0 }
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
  EID.descriptions.zh_cn = EID.descriptions.en_us
  EID.ItemNames.zh_cn = EID.ItemNames.en_us
else
  EID = nil
end

local registeredMod = nil
function RegisterMod(name, apiVersion)
  local mod = { name = name, apiVersion = apiVersion }
  function mod:AddCallback(callbackId, callback)
    local callbacks = TEST.callbackLists[callbackId] or {}
    callbacks[#callbacks + 1] = callback
    TEST.callbackLists[callbackId] = callbacks
    if TEST.callbacks[callbackId] == nil then TEST.callbacks[callbackId] = callback end
  end
  function mod:RemoveCallback(callbackId, callback)
    local callbacks = TEST.callbackLists[callbackId] or {}
    for index = #callbacks, 1, -1 do
      if callbacks[index] == callback then table.remove(callbacks, index) end
    end
    TEST.callbacks[callbackId] = callbacks[1]
  end
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

local function runCallbacks(callbackId)
  local callbacks = TEST.callbackLists[callbackId] or {}
  local snapshot = {}
  for index, callback in ipairs(callbacks) do snapshot[index] = callback end
  for _, callback in ipairs(snapshot) do callback() end
end

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
local beginCommandInput = findUpvalue(onRender, "beginCommandInput")
local showToast = findUpvalue(onStarted, "showToast")
local drawToast = findUpvalue(onRender, "drawToast")
local removalCommand = findUpvalue(onRender, "removalCommand")
local toggleFavorite = findUpvalue(onRender, "toggleFavorite")
local saveState = findUpvalue(onRender, "saveState")
local allEntries = findUpvalue(onRender, "allEntries")
local runtimeCatalog = findUpvalue(visibleEntries, "Catalog")
assertTrue(type(state) == "table", "state upvalue unavailable")
assertTrue(type(visibleEntries) == "function", "visibleEntries upvalue unavailable")
assertTrue(type(computeLayout) == "function", "computeLayout upvalue unavailable")
assertTrue(type(drawFavoriteStar) == "function", "drawFavoriteStar upvalue unavailable")
assertTrue(type(queueCommand) == "function", "queueCommand upvalue unavailable")
assertTrue(type(removalCommand) == "function", "removalCommand upvalue unavailable")
assertTrue(type(beginCommandInput) == "function", "beginCommandInput upvalue unavailable")
assertTrue(type(showToast) == "function", "showToast upvalue unavailable")
assertTrue(type(drawToast) == "function", "drawToast upvalue unavailable")
assertTrue(type(toggleFavorite) == "function", "toggleFavorite upvalue unavailable")
assertTrue(type(saveState) == "function", "saveState upvalue unavailable")

local function clearInput()
  TEST.keyTriggers = {}
  TEST.buttonTriggers = {}
  TEST.actionTriggers = {}
end

local function renderFrame()
  TEST.frame = TEST.frame + 1
  runCallbacks(ModCallbacks.MC_POST_RENDER)
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
  local foundExpected = false
  for _, path in ipairs(TEST.fontLoads) do
    if IS_ZH then
      if contains(path, ".zh/font/") then foundExpected = true end
    else
      if contains(path, "fusion/10.fnt") or contains(path, "fusion/12.fnt") then
        foundExpected = true
      end
      assertTrue(not contains(path, ".zh/font/"), "English edition loaded a locale-specific game font")
    end
  end
  assertTrue(foundExpected, IS_ZH and "official Chinese font was not loaded"
    or "self-contained Fusion Pixel font was not loaded")
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
  assertEqual(state.closeAfterRegularCommand, true,
    "legacy save did not preserve the default close-after-command behavior")
  assertTrue(state.favorites["c:260"] == true, "v2.4.2 dynamic favorite did not migrate")
  assertTrue(state.favorites["c:182"] == true, "v2.4.2 curated favorite did not migrate")
  assertEqual(#state.history, 2, "v2.4.2 history did not load")
  openMenu()
  state.search = ""
  state.categoryIndex = 1
  visibleEntries()
  assertEqual(state.favoriteOrder[1], "c:182", "legacy favorites did not keep catalog order")
  assertEqual(state.favoriteOrder[2], "c:260", "legacy dynamic favorite migration order differs")
  assertTrue(contains(TEST.saveData, "favoriteOrder=recent\n"),
    "legacy favorite order migration was not marked complete")
  assertTrue(contains(TEST.saveData, "closeAfterRegularCommand=1\n"),
    "legacy save migration did not persist the command-close default")
  enterSearch("260")
  pressKey(Keyboard.KEY_F)
  assertTrue(state.favorites["c:260"] == nil, "upgrade favorite mutation failed")
  assertTrue(contains(TEST.saveData, "version=" .. TEST_CONFIG.expectedVersion .. "\n"), "upgrade save version missing")
  assertTrue(contains(TEST.saveData, "favorites=c:182\n"), "upgrade did not preserve curated favorite")
  assertTrue(contains(TEST.saveData, "history=giveitem c260|spawn 5.10.1"), "upgrade changed history text format")
end

local function testSaveFailureRollback()
  onStarted()
  enterSearch("260")
  pressKey(Keyboard.KEY_F)
  assertTrue(state.favorites["c:260"] == nil, "failed save did not roll favorite back")
  assertEqual(#state.favoriteOrder, 0, "failed save did not roll recent favorite order back")
  assertTrue(state.toast and contains(state.toast.message, IS_ZH and "已撤销" or "reverted"),
    "save failure toast is misleading")
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
  assertTrue(state.toast and contains(state.toast.message, IS_ZH and "安全白名单" or "safe list"),
    "blocked nonexistent stage gave no explanation")
  assertEqual(#TEST.executed, executedBefore, "blocked nonexistent stage executed")

  assertTrue(TEST_CONFIG.greedMode == true, "stage safety scenario must run in Greed mode")
  assertEqual(queueCommand("stage 1c", 1), false, "Greed mode stage command was accepted")
  assertTrue(state.queue == nil, "Greed mode stage command entered queue")
  assertTrue(state.toast and contains(state.toast.message, IS_ZH and "贪婪模式安全白名单" or "Greed-mode safe list"),
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
  assertTrue(state.lifecycleRequest ~= nil and state.queue == nil,
    "stage did not enter the Render lifecycle channel")
  runCallbacks(ModCallbacks.MC_POST_RENDER)
  onUpdate()
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
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE), 0.0,
    "controller close release leaked back to the game")
  renderFrame()
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE), nil,
    "controller release guard remained active after release")

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
    if contains(value, IS_ZH and "A执行" or "A: run") then sawExecuteHint = true end
    if IS_ZH and contains(value, "长按") and contains(value, "移除")
        or not IS_ZH and contains(value, "Hold A") and contains(value, "remove") then
      sawRemoveHint = true
    end
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
  assertTrue(state.toast and contains(state.toast.message, IS_ZH and "立即增加资源" or "grants resources immediately"),
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
  assertTrue(state.toast
      and contains(state.toast.message, IS_ZH and "立即增加资源" or "grants resources immediately")
      and (IS_ZH or contains(state.toast.message, "ItemConfig") == false),
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
  assertTrue(state.toast and contains(state.toast.message, IS_ZH and "没有可移除道具" or "no removable item"),
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
  state.queue.total = 2
  state.queue.done = 235
  state.open = true
  state.inputMode = nil
  TEST.rendered = {}
  renderFrame()
  local renderedTogether = table.concat(TEST.rendered, "")
  local showedClampedProgress = false
  for _, value in ipairs(TEST.rendered) do
    assertTrue(not contains(value, "235/2"), "queue renderer exposed progress beyond total")
  end
  showedClampedProgress = contains(renderedTogether,
    (IS_ZH and "正在执行 " or "Running ") .. "2/2")
  assertTrue(showedClampedProgress, "queue renderer did not clamp corrupted progress")
  assertEqual(TEST.rendered[#TEST.rendered],
    (IS_ZH and "正在执行 " or "Running ") .. "2/2",
    "queue progress was not the final visible footer text")
  local executedBefore = #TEST.executed
  onUpdate()
  assertEqual(#TEST.executed, executedBefore,
    "already-complete corrupted queue executed an extra command")
  assertEqual(state.queue, nil, "corrupted completed queue was not finalized")
end

local function findCatalogCommand(commandId, action)
  for _, entry in ipairs(runtimeCatalog.commands) do
    if entry.commandId == commandId and (not action or entry.catalogAction == action) then
      return entry
    end
  end
  return nil
end

local function testCommandContracts()
  onStarted()
  local specs = include("scripts.command_specs")
  local expectedOfficial = {
    "spawn", "goto", "stage", "gridspawn", "debug", "giveitem", "remove",
    "costumetest", "restart", "listcollectibles", "repeat", "clearseeds",
    "seed", "challenge", "combo", "macro", "playsfx", "curse", "reseed",
    "copy", "clear", "lua", "luarun", "luamod", "luamem", "metro",
    "delirious", "restock", "rewind", "testbosspool", "reloadwisps",
  }
  for _, verb in ipairs(expectedOfficial) do
    assertTrue(specs.byVerb[verb] ~= nil, "official command missing from contract: " .. verb)
  end
  for alias, commandId in pairs({ g = "giveitem", r = "remove", m = "macro", l = "lua" }) do
    assertEqual(specs.byVerb[alias].id, commandId, "command alias contract differs: " .. alias)
  end
  assertEqual(#runtimeCatalog.categories, 17, "command categories were not appended exactly once")
  assertTrue(findCatalogCommand("goto", "manual") ~= nil, "goto reference entry missing")
  assertTrue(findCatalogCommand("listcollectibles", "disabled") ~= nil,
    "native-output entry is not visibly disabled")
  local lifecycleDescriptions = IS_ZH and {
    rewind = "回到上一个房间状态。",
    restart = "以当前角色重新开始一局。",
    reseed = "重新生成当前楼层。",
  } or {
    rewind = "Returns to the previous room state.",
    restart = "Restarts with the current character.",
    reseed = "Regenerates the current floor.",
  }
  for commandId, description in pairs(lifecycleDescriptions) do
    local entry = findCatalogCommand(commandId)
    assertTrue(entry ~= nil, commandId .. " lifecycle entry is missing")
    assertEqual(entry.desc, description,
      commandId .. " description exposes implementation details or differs from the user-facing contract")
  end

  for _, command in ipairs({
      "listcollectibles", "copy", "clear", "luamem", "testbosspool",
      "lua x", "l x", "luarun x", "luamod x", "achievement 1", "prof",
      "fullrestart", "quit", "macro x", "repeat 2",
    }) do
    assertEqual(queueCommand(command, 1), false, "disabled command was accepted: " .. command)
    assertTrue(state.queue == nil and state.lifecycleRequest == nil,
      "disabled command entered an execution channel: " .. command)
  end
  for _, spec in ipairs(specs.list) do
    if spec.mode == "output" or spec.mode == "disabled" then
      local entry = findCatalogCommand(spec.id, "disabled")
      assertTrue(entry ~= nil, "disabled command has no visible catalog entry: " .. spec.id)
      assertEqual(queueEntry(entry, 1), false,
        "A/Enter queued a disabled catalog entry: " .. spec.id)
      assertEqual(beginCommandInput(entry), false,
        "C opened a disabled catalog entry: " .. spec.id)
      assertTrue(state.queue == nil and state.lifecycleRequest == nil,
        "disabled entry reached an execution channel: " .. spec.id)
    end
  end
  for _, command in ipairs({ "restart 41", "challenge 46", "curse 256", "seed abcd efgh" }) do
    assertEqual(queueCommand(command, 1), false, "invalid parameter bypassed validation: " .. command)
  end

  local gotoEntry = findCatalogCommand("goto", "manual")
  assertEqual(queueEntry(gotoEntry, 1), false, "parameter reference executed from A/Enter")
  assertTrue(state.toast ~= nil, "parameter reference guidance was not shown")
  TEST.renderRecords = {}
  TEST.spriteRecords = {}
  TEST.captureGeometry = true
  drawToast(TEST_CONFIG.screenWidth or 1280, TEST_CONFIG.screenHeight or 720)
  assertEqual(#TEST.renderRecords, 1,
    "parameter reference guidance must render as one Toast line")
  TEST.captureGeometry = false
  assertTrue(beginCommandInput(gotoEntry), "C could not open a parameter template")
  assertEqual(state.manualCommand, "goto ", "parameter template did not retain its trailing input position")
  assertEqual(state.commandSelectAll, false, "parameter template was incorrectly selected")
  local outputEntry = findCatalogCommand("listcollectibles", "disabled")
  assertEqual(beginCommandInput(outputEntry), false, "C opened a disabled output command")
end

local function testLifecycleCommandChannel()
  onStarted()
  if TEST_CONFIG.repentogon then
    assertTrue(REPENTOGON ~= nil and REPENTANCE_PLUS,
      "REPENTOGON lifecycle scenario did not expose its runtime capability")
  end
  local commands = { "rewind", "restart", "reseed", "seed T1MM AY48", "challenge 20", "goto d.10", "stage 1" }
  for _ = 2, 20 do commands[#commands + 1] = "rewind" end
  for _, command in ipairs(commands) do
    openMenu()
    local executedBefore = #TEST.executed
    local laterRenderRanBeforeDispatch = false
    local function laterRenderCallback()
      laterRenderRanBeforeDispatch = #TEST.executed == executedBefore
    end
    registeredMod:AddCallback(ModCallbacks.MC_POST_RENDER, laterRenderCallback)
    assertTrue(queueCommand(command, 9), "lifecycle command was rejected: " .. command)
    assertTrue(state.queue == nil and state.lifecycleRequest ~= nil,
      "lifecycle command entered MC_POST_UPDATE queue: " .. command)
    assertEqual(state.open, false, "lifecycle command did not release the overlay: " .. command)
    runCallbacks(ModCallbacks.MC_POST_RENDER)
    registeredMod:RemoveCallback(ModCallbacks.MC_POST_RENDER, laterRenderCallback)
    assertTrue(laterRenderRanBeforeDispatch,
      "lifecycle command did not run after an existing render callback: " .. command)
    assertEqual(#TEST.executed, executedBefore + 1, "Render dispatch count differs: " .. command)
    assertEqual(TEST.executed[#TEST.executed], command, "Render dispatched wrong command")
    assertTrue(state.lifecycleRequest == nil and state.lifecycleReceipt ~= nil,
      "Render dispatch touched post-command engine state")
    onUpdate()
    assertTrue(state.lifecycleReceipt ~= nil,
      "lifecycle receipt settled before the stable update window: " .. command)
    onUpdate()
    assertEqual(state.lifecycleReceipt, nil, "stable callback did not settle lifecycle receipt")
    assertEqual(state.history[1], command, "lifecycle history settled incorrectly")
    assertEqual(state.repeatCount, 1, "lifecycle command retained a repeat count")
    assertTrue(state.toast ~= nil and state.toast.inlineAction == true,
      "lifecycle success did not use the one-line command result")
    assertEqual(state.toast.action, command,
      "lifecycle success omitted the executed command")
  end

  openMenu()
  local executedBeforeBoundary = #TEST.executed
  assertTrue(queueCommand("rewind", 1), "boundary cancellation setup failed")
  onStarted()
  runCallbacks(ModCallbacks.MC_POST_RENDER)
  assertEqual(#TEST.executed, executedBeforeBoundary,
    "new-run cleanup left a one-shot lifecycle dispatcher armed")
end

local function testUnknownCommandConfirmation()
  onStarted()
  openMenu()
  state.inputMode = "command"
  state.manualCommand = "thirdparty_test value"
  assertEqual(queueCommand(state.manualCommand, 99), false,
    "unknown command executed without a first confirmation")
  assertEqual(state.unknownCommandConfirmation, state.manualCommand,
    "unknown command did not expose persistent confirmation state")
  assertTrue(state.open and state.queue == nil, "first unknown confirmation changed execution state")
  assertTrue(queueCommand(state.manualCommand, 99), "confirmed unknown command was rejected")
  assertEqual(state.queue.total, 1, "unknown command was allowed to batch")
  onUpdate()
  assertEqual(TEST.executed[#TEST.executed], "thirdparty_test value",
    "confirmed unknown command did not execute once")

  openMenu()
  state.inputMode = "command"
  state.manualCommand = "another_thirdparty"
  assertEqual(queueCommand(state.manualCommand, 1), false, "confirmation setup failed")
  pressKey(keyForCharacter("x"))
  assertEqual(state.unknownCommandConfirmation, nil, "editing did not cancel unknown confirmation")
  state.manualCommand = "another_thirdparty"
  assertEqual(queueCommand(state.manualCommand, 1), false, "Escape confirmation setup failed")
  pressKey(Keyboard.KEY_ESCAPE)
  assertEqual(state.inputMode, "command", "first Esc left the editor instead of cancelling confirmation")
  assertEqual(state.unknownCommandConfirmation, nil, "Esc retained unknown confirmation")
  pressKey(Keyboard.KEY_ESCAPE)
  assertEqual(state.inputMode, nil, "second Esc did not leave command editing")
end

local function testCommandFeedbackDurations()
  onStarted()
  state.startupHintShown = true

  local function finishSingle(command)
    assertTrue(queueCommand(command, 1), "command feedback setup was rejected: " .. command)
    onUpdate()
    assertEqual(state.queue, nil, "single command did not finish immediately")
  end

  local function assertExpiresAfter(expectedFrames, label)
    assertEqual(state.toastFramesRemaining, expectedFrames, label .. " duration differs")
    for _ = 1, expectedFrames - 1 do
      TEST.frame = TEST.frame + 1
      onUpdate()
      assertTrue(state.toast ~= nil, label .. " expired early")
    end
    TEST.frame = TEST.frame + 1
    onUpdate()
    assertEqual(state.toast, nil, label .. " did not expire on its boundary")
  end

  state.toast = nil
  state.toastFramesRemaining = 0
  assertTrue(queueCommand("giveitem c1", 1), "single-command flash setup was rejected")
  TEST.renderRecords = {}
  TEST.spriteRecords = {}
  TEST.captureGeometry = true
  drawToast(TEST_CONFIG.screenWidth or 1280, TEST_CONFIG.screenHeight or 720)
  assertEqual(#TEST.renderRecords, 0,
    "single-command queue flashed execution text before completion")
  assertEqual(#TEST.spriteRecords, 0,
    "single-command queue flashed a progress background before completion")
  TEST.captureGeometry = false
  onUpdate()
  assertEqual(state.queue, nil, "single command did not finish immediately")
  assertTrue(contains(state.toast.message, IS_ZH and "执行完成" or "Completed"),
    "single-command success feedback differs")
  assertEqual(state.toast.action, "giveitem c1",
    "single-command success omitted the executed command")
  assertEqual(state.toast.inlineAction, true,
    "single-command success did not use the one-line command result")
  TEST.renderRecords = {}
  TEST.spriteRecords = {}
  TEST.captureGeometry = true
  local hostedFooter = { x = 20, y = 200, width = 400, height = 48 }
  drawToast(TEST_CONFIG.screenWidth or 1280, TEST_CONFIG.screenHeight or 720, hostedFooter)
  assertEqual(#TEST.renderRecords, 1, "hosted success Toast was not one line")
  assertEqual(TEST.spriteRecords[1].width, hostedFooter.width,
    "open-menu Toast background did not occupy the complete footer")
  TEST.captureGeometry = false
  assertExpiresAfter(30, "single-command success Toast")

  assertTrue(queueCommand("giveitem c2", 2), "batch success setup was rejected")
  onUpdate()
  TEST.renderRecords = {}
  TEST.spriteRecords = {}
  TEST.captureGeometry = true
  drawToast(TEST_CONFIG.screenWidth or 1280, TEST_CONFIG.screenHeight or 720, hostedFooter)
  assertEqual(#TEST.renderRecords, 1, "batch progress did not use one footer line")
  assertTrue(not contains(TEST.renderRecords[1].text, "giveitem c2"),
    "batch progress redundantly rendered the full command")
  assertEqual(TEST.spriteRecords[1].width, hostedFooter.width,
    "batch progress did not occupy the complete footer")
  TEST.captureGeometry = false
  TEST.frame = TEST.frame + 7
  onUpdate()
  assertEqual(state.queue, nil, "batch command did not finish")
  assertTrue(contains(state.toast.message, IS_ZH and "×2" or "x2"),
    "batch success feedback omitted its count")
  assertEqual(state.toast.action, "giveitem c2",
    "batch success omitted the executed command")
  assertEqual(state.toast.inlineAction, true,
    "batch success did not use the one-line command result")
  assertExpiresAfter(30, "batch success Toast")

  showToast(IS_ZH and "成功时长契约" or "Success duration contract", "success", 999)
  assertEqual(state.toastFramesRemaining, 30,
    "success Toast accepted a caller-specific duration")
  showToast(IS_ZH and "警告时长契约" or "Warning duration contract", "warning", 75)
  assertEqual(state.toastFramesRemaining, 75,
    "warning Toast no longer respects its explicit duration")

  TEST_CONFIG.executeFail = true
  finishSingle("giveitem c3")
  TEST_CONFIG.executeFail = false
  assertEqual(state.toastFramesRemaining, 180, "execution-failure Toast duration changed")

  assertTrue(queueCommand("giveitem c4", 2), "partial-failure setup was rejected")
  onUpdate()
  TEST_CONFIG.executeFail = true
  TEST.frame = TEST.frame + 7
  onUpdate()
  TEST_CONFIG.executeFail = false
  assertTrue(contains(state.toast.message, IS_ZH and "部分完成 1/2" or "Partially completed 1/2"),
    "partial-failure feedback differs")
  assertEqual(state.toastFramesRemaining, 180, "partial-failure Toast duration changed")

  TEST_CONFIG.saveFail = true
  finishSingle("giveitem c5")
  TEST_CONFIG.saveFail = false
  assertTrue(contains(IS_ZH and state.toast.message or string.lower(state.toast.message),
      IS_ZH and "历史保存失败" or "history could not be saved"),
    "history-save failure feedback differs")
  assertEqual(state.toastFramesRemaining, 180, "history-save failure Toast duration changed")

  assertEqual(queueCommand("lua error('blocked')", 1), false,
    "unsafe command was accepted during feedback testing")
  assertEqual(state.toastFramesRemaining, 120, "safety-warning Toast duration changed")
end

local function testMeasuredFooterAndStars()
  onStarted()
  openMenu()
  state.sidebarFocus = true
  TEST.rendered = {}
  renderFrame()
  local exactVersion, exactGroup, exactSummary, exactCategoryDesc = false, false, false, false
  for _, value in ipairs(TEST.rendered) do
    if value == (IS_ZH and "纯 Lua v" or "v") .. TEST_CONFIG.expectedVersion then exactVersion = true end
    if value == (IS_ZH and "分类 1/3" or "1/3") then exactGroup = true end
    if IS_ZH then
      if value == "全部收藏品" then exactSummary = true end
      if value == "当前版本的全部收藏品" then exactCategoryDesc = true end
    elseif value == "Collectibles" then
      exactSummary = true
    end
    if not IS_ZH and (value == "All collectibles in the current game version."
        or value == "All official collectibles." or value == "COLLECTIBLES") then
      exactCategoryDesc = true
    end
  end
  assertTrue(exactVersion, "low-resolution version label was truncated")
  assertTrue(exactGroup, "low-resolution category page label was truncated")
  assertTrue(exactSummary, "low-resolution category summary was truncated")
  assertTrue(exactCategoryDesc, "low-resolution category description was truncated")

  state.inputMode = "search"
  state.search = ""
  TEST.rendered = {}
  renderFrame()
  local exactSearchHelp, exactSearchKeys = false, false
  for _, value in ipairs(TEST.rendered) do
    if IS_ZH and (value == "搜索：_" or value == "全部物品可输入全拼、首字母、英文、命令或 ID"
        or value == "支持拼音、英文、命令或 ID") then exactSearchHelp = true end
    if not IS_ZH and (value == "Search: _" or value == "Name / alias / command / ID"
        or value == "Name / alias / ID") then exactSearchHelp = true end
    if contains(value, "Ctrl+A") and contains(value, "Esc") then exactSearchKeys = true end
  end
  assertTrue(exactSearchHelp, "low-resolution search help was truncated")
  assertTrue(exactSearchKeys, "low-resolution search key help was truncated")

  state.inputMode = "command"
  state.manualCommand = "spawn 5.10.1"
  state.commandSelectAll = false
  TEST.rendered = {}
  renderFrame()
  local commandLabel, commandText, commandKeys, repeatKeys = false, false, false, false
  for _, value in ipairs(TEST.rendered) do
    if value == (IS_ZH and "命令：" or "Cmd: ") then commandLabel = true end
    if value == "spawn 5.10.1_" then commandText = true end
    if contains(value, "Ctrl+A") and contains(value, "Enter") and contains(value, "Esc")
        and not contains(value, "...") then commandKeys = true end
    if value == (IS_ZH and "次数" or "Repeat") then repeatKeys = true end
  end
  assertTrue(commandLabel, "low-resolution command label was truncated")
  assertTrue(commandText, "short command was unnecessarily tail-truncated")
  assertTrue(commandKeys, "low-resolution command key help was truncated")
  assertTrue(repeatKeys, "keyboard repeat label was missing or exposed controller buttons")

  state.manualCommand = string.rep("spawn 5.10.1 ", 12)
  TEST.rendered = {}
  renderFrame()
  local longCommandTail = false
  for _, value in ipairs(TEST.rendered) do
    if value:sub(1, 3) == "..." and value:sub(-1) == "_" then
      longCommandTail = true
    end
  end
  if TEST_CONFIG.screenWidth <= 455 then
    assertTrue(longCommandTail, "genuinely long command did not adapt from the tail at minimum resolution")
  end
  state.inputMode = nil

  state.sidebarFocus = false
  enterSearch("182")
  TEST.rendered = {}
  TEST.renderRecords = {}
  TEST.captureGeometry = true
  renderFrame()
  TEST.captureGeometry = false
  local exactTitle = false
  local exactCommandLabel = false
  local exactCommandValue = false
  local completeHint = false
  local visibleRemoveButton = false
  for _, value in ipairs(TEST.rendered) do
    if value == (IS_ZH and "圣心 / Sacred Heart" or "Sacred Heart") then exactTitle = true end
    if value == (IS_ZH and "手动命令(C)：" or "Manual command (C): ") then exactCommandLabel = true end
    if value == "giveitem c182" then exactCommandValue = true end
    if contains(value, IS_ZH and "F收藏" or "F: favorite") and not contains(value, "...") then completeHint = true end
    if value == (IS_ZH and "移除" or "Remove") then visibleRemoveButton = true end
  end
  assertTrue(exactTitle, "detail title was truncated or duplicated")
  assertTrue(exactCommandLabel, "detail command label was truncated")
  assertTrue(exactCommandValue, "short detail command was truncated; rendered="
    .. table.concat(TEST.rendered, " | "))
  if IS_ZH then
    assertTrue(completeHint, "footer action hint was truncated")
  end
  if (TEST_CONFIG.screenWidth or 1280) > 455 then
    local layout = computeLayout(TEST_CONFIG.screenWidth or 1280, TEST_CONFIG.screenHeight or 720)
    local actionHintY = nil
    for _, record in ipairs(TEST.renderRecords) do
      if IS_ZH and contains(record.text, "F收藏")
          or not IS_ZH and contains(string.lower(record.text), "favorite") then
        actionHintY = record.y
        break
      end
    end
    assertEqual(actionHintY, layout.footerY + layout.pad,
      "keyboard entry help did not share the controller top action row")
  end
  assertEqual(visibleRemoveButton, false, "cards still render the redundant remove text column")

  local selected = visibleEntries()[1]
  local originalCommand = selected.cmd
  selected.cmd = string.rep("spawn 5.10.1 ", 12)
  TEST.rendered = {}
  renderFrame()
  local detailLongCommandTail = false
  for _, value in ipairs(TEST.rendered) do
    if value:sub(1, 3) == "..." and contains(value, "5.10.1") then
      detailLongCommandTail = true
    end
  end
  selected.cmd = originalCommand
  if TEST_CONFIG.screenWidth <= 455 then
    assertTrue(detailLongCommandTail, "long detail command did not adapt from the tail at minimum resolution")
  end

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
    if contains(value, IS_ZH and "A给予" or "A: give")
        or contains(value, IS_ZH and "X取消收藏" or "X: unfavorite") then
      controllerHint = true
    end
    if IS_ZH and contains(value, "长按") and contains(value, "移除")
        or not IS_ZH and ((contains(string.lower(value), "hold") and contains(string.lower(value), "remove"))
          or contains(value, "HoldA:rm")) then
      controllerRemoveHint = true
    end
    if contains(value, "R3") then legacyR3Hint = true end
    if contains(value, "LMB") or contains(value, "RMB") then mouseHint = true end
  end
  assertEqual(fontStar, false, "favorite marker still depends on a missing font glyph")
  assertTrue(controllerHint, "controller mode did not render controller-specific help")
  if (TEST_CONFIG.screenWidth or 1280) > 455 then
    assertTrue(controllerRemoveHint, "controller mode did not render long-A remove help: "
      .. table.concat(TEST.rendered, " | "))
  end
  assertEqual(legacyR3Hint, false, "controller help still advertises R3 removal")
  assertEqual(mouseHint, false, "controller mode still rendered mouse-only help")
  TEST.spriteColors = {}
  local rendersBeforeStar = TEST.spriteRenders
  drawFavoriteStar(0, 0, 20, 20, false)
  local hollowStarRenders = TEST.spriteRenders - rendersBeforeStar
  assertTrue(hollowStarRenders > 0, "hollow favorite pixel star rendered no geometry")
  local hollowColors = table.concat(TEST.spriteColors, "|")
  TEST.spriteColors = {}
  drawFavoriteStar(0, 0, 20, 20, true)
  local filledColors = table.concat(TEST.spriteColors, "|")
  assertTrue(filledColors ~= hollowColors, "filled favorite star is not visually distinct from the hollow state")

  state.search = ""
  state.categoryIndex = 1
  state.controlMode = "keyboard"
  TEST.rendered = {}
  renderFrame()
  local featuredCancelHint = false
  for _, value in ipairs(TEST.rendered) do
    if contains(value, IS_ZH and "F取消收藏" or "F: unfavorite")
        or contains(value, "/F") then featuredCancelHint = true end
  end
  assertTrue(featuredCancelHint, "featured view did not expose favorite cancellation")

  pressKey(Keyboard.KEY_F)
  TEST.rendered = {}
  renderFrame()
  local emptyTitle, emptyHint = false, false
  for _, value in ipairs(TEST.rendered) do
    if value == (IS_ZH and "暂无收藏" or "No favorites yet") then emptyTitle = true end
    if value == (IS_ZH and "请在其他分类按 F 添加"
        or "Press F in another category to add entries") then emptyHint = true end
  end
  assertTrue(emptyTitle and emptyHint, "empty featured guidance was not rendered")
end

local function testFontFallback()
  assertTrue(TEST_CONFIG.repPlus, "fallback scenario must use Repentance+")
  assertTrue(#TEST.fontLoads >= 2, "bundled font pair was not attempted")
  local foundExpected = false
  for _, path in ipairs(TEST.fontLoads) do
    if IS_ZH then
      if contains(path, ".zh/font/") then foundExpected = true end
    else
      if contains(path, "fusion/10.fnt") or contains(path, "fusion/12.fnt") then
        foundExpected = true
      end
      assertTrue(not contains(path, ".zh/font/"), "English edition tried a locale-specific font")
    end
  end
  assertTrue(foundExpected, IS_ZH and "official Chinese font was not loaded"
    or "bundled Fusion Pixel font was not loaded")
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
  assertEqual(TEST.mcmAddCalls, 4, "MCM settings were not registered exactly once each")
  assertEqual(TEST.mcmCategory, IS_ZH and "Isaac Chinese Console" or "Console UI", "MCM category changed")
  assertEqual(TEST.mcmSubcategory, IS_ZH and "设置" or "Settings", "MCM subcategory changed")
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
  assertEqual(TEST.mcmAddCalls, 4, "rewind duplicated the MCM settings")
end

local function testEidOverlayIsolation()
  assertTrue(TEST_CONFIG.eid, "EID overlay scenario requires EID")
  if IS_ZH then
    EID.isHidden = false
    openMenu()
    assertEqual(EID.isHidden, false, "Chinese edition unexpectedly changed EID visibility")
    pressKey(Keyboard.KEY_F6)
    assertEqual(EID.isHidden, false, "Chinese edition changed EID on close")
    EID.isHidden = true
    openMenu()
    pressKey(Keyboard.KEY_ESCAPE)
    assertEqual(EID.isHidden, true, "Chinese edition changed a hidden EID")
    return
  end
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

local function testRunBoundaryControllerLifecycle()
  onStarted()
  state.startupHintShown = true

  -- A closed overlay must be completely transparent during native player and
  -- controller construction. In particular, MC_INPUT_ACTION must not probe
  -- raw input merely because the engine queries JOIN.
  TEST.buttonPressed[Keyboard.KEY_R] = { [0] = true }
  local closedInputPolls = TEST.buttonPressedCalls
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_JOINMULTIPLAYER), nil,
    "closed overlay intercepted native player assignment")
  assertEqual(TEST.buttonPressedCalls, closedInputPolls,
    "closed overlay polled physical input during native player assignment")
  TEST.buttonPressed[Keyboard.KEY_R] = nil

  local function dirtyTransientInputState(label)
    openMenu()
    state.nativePauseSuspended = true
    state.inputLease = {
      kind = "action", index = 1, value = ButtonAction.ACTION_MENUCONFIRM,
    }
    state.controllerIndex = 1
    state.controllerConfirmCommand = "giveitem c1"
    state.inputMode = "search"
    state.searchSelectAll = true
    TEST.paused = true
    assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
      ButtonAction.ACTION_JOINMULTIPLAYER), nil,
      label .. " blocked native controller recovery before the run boundary")
  end

  local function assertCleared(label)
    assertEqual(state.open, false, label .. " retained the open overlay")
    assertEqual(state.nativePauseSuspended, false, label .. " retained pause suspension")
    assertEqual(state.inputLease, nil, label .. " retained the input lease")
    assertEqual(state.controllerIndex, nil, label .. " retained the old controller assignment")
    assertEqual(state.controllerConfirmCommand, nil, label .. " retained controller confirmation")
    assertEqual(state.inputMode, nil, label .. " retained input focus")
    assertEqual(state.searchSelectAll, false, label .. " retained selection state")
    TEST.paused = false
    assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
      ButtonAction.ACTION_JOINMULTIPLAYER), nil,
      label .. " blocked game input after the boundary completed")
  end

  -- R restart: frame reset is visible before the new-game callback.
  TEST.frame = 120
  state.lastGameFrame = TEST.frame
  dirtyTransientInputState("R restart")
  TEST.paused = false
  state.inputMode = nil
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_RESTART), nil,
    "R restart action was intercepted before the run boundary")
  TEST.actionPressed[ButtonAction.ACTION_RESTART] = { [1] = true }
  renderFrame()
  TEST.actionPressed[ButtonAction.ACTION_RESTART] = nil
  assertEqual(state.open, false,
    "R restart did not close the overlay before player reconstruction")
  assertEqual(state.inputLease, nil,
    "R restart retained an input lease before player reconstruction")
  dirtyTransientInputState("R restart callback gap")
  TEST.paused = false
  TEST.frame = 0
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_JOINMULTIPLAYER), nil,
    "R restart callback gap blocked native controller reassignment")
  onStarted()
  assertCleared("R restart")

  -- Editable fields own alphabetic R. Restart must remain blocked there so a
  -- command or search query cannot restart the run.
  openMenu()
  state.inputMode = "command"
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_RESTART), 0.0,
    "command input leaked R to the game restart action")
  state.inputMode = "search"
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_RESTART), 0.0,
    "search input leaked R to the game restart action")
  pressKey(Keyboard.KEY_ESCAPE)
  pressKey(Keyboard.KEY_F6)
  assertEqual(state.open, false, "restart editor isolation setup did not close the overlay")

  -- Rewind may deliver a new-game callback without first exposing a lower frame.
  TEST.frame = 180
  state.lastGameFrame = TEST.frame
  dirtyTransientInputState("Rewind")
  TEST.paused = false
  TEST.frame = 0
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_JOINMULTIPLAYER), nil,
    "Rewind callback gap blocked native controller reassignment")
  onStarted()
  assertCleared("Rewind")

  -- Rerun can reset the frame after the new-game callback.
  TEST.frame = 240
  state.lastGameFrame = TEST.frame
  dirtyTransientInputState("Rerun callback-first")
  TEST.paused = false
  state.inputMode = nil
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_RESTART), nil,
    "Rerun restart action was intercepted before the callback")
  onStarted()
  assertCleared("Rerun callback-first")
  TEST.frame = 0
  onUpdate()
  assertCleared("Rerun callback-first frame reset")

  -- Some runtimes expose only the frame rollback; that fallback must match.
  TEST.frame = 360
  state.lastGameFrame = TEST.frame
  dirtyTransientInputState("callback-less frame rollback")
  TEST.paused = false
  TEST.frame = 0
  onUpdate()
  assertCleared("callback-less frame rollback")
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
  TEST.rendered = {}
  renderFrame()
  local exactFocusedSearch, prefixedFocusedSearch = false, false
  for _, value in ipairs(TEST.rendered) do
    if value == "d_" then exactFocusedSearch = true end
    if value == "Search: d_" or value == "搜索：d_" then
      prefixedFocusedSearch = true
    end
  end
  assertTrue(exactFocusedSearch and not prefixedFocusedSearch, "non-empty search retained its placeholder prefix")

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
  assertEqual(state.manualCommand, "giveitem c182", "command Ctrl+A changed text")
  assertEqual(state.commandSelectAll, true, "command Ctrl+A did not select its own text")
  assertEqual(state.searchSelectAll, false, "manual command Ctrl+A leaked search selection state")
  pressKey(Keyboard.KEY_D)
  assertEqual(state.manualCommand, "d", "command typing did not replace selected text")
  assertEqual(state.commandSelectAll, false, "command replacement retained selection")

  pressKey(Keyboard.KEY_F6)
  TEST.buttonPressed[Keyboard.KEY_LEFT_CONTROL] = { [0] = true }
  TEST.keyTriggers[Keyboard.KEY_A] = true
  renderFrame()
  TEST.buttonPressed[Keyboard.KEY_LEFT_CONTROL] = { [0] = false }
  assertEqual(state.open, false, "Ctrl+A opened or changed a closed menu")
end

local function testCommandEditorAndHistory()
  onStarted()
  openMenu()
  state.history = { "spawn 5.10.1 ×4", "giveitem c182" }
  state.repeatCount = 3
  pressKey(Keyboard.KEY_C)
  assertEqual(state.inputMode, "command", "C did not enter manual command mode")
  assertEqual(state.commandSelectAll, true, "prefilled command was not selected")
  state.controlMode = "controller"
  TEST.rendered = {}
  pressKey(keyForCharacter("s"))
  assertEqual(state.manualCommand, "s", "typing did not replace prefilled command")
  assertEqual(state.controlMode, "keyboard", "command typing retained stale controller ownership")
  local sawKeyboardHint, sawControllerHint = false, false
  for _, text in ipairs(TEST.rendered) do
    if contains(text, IS_ZH and "Enter执行" or "Enter")
        and contains(text, IS_ZH and "Esc退出" or "Esc") then
      sawKeyboardHint = true
    end
    if contains(text, IS_ZH and "A执行" or "A: run") then sawControllerHint = true end
  end
  assertTrue(sawKeyboardHint, "keyboard command input did not render keyboard help")
  assertEqual(sawControllerHint, false, "keyboard command input retained controller help")
  pressKey(Keyboard.KEY_UP)
  assertEqual(state.manualCommand, "spawn 5.10.1", "Up did not recall newest command")
  assertEqual(state.repeatCount, 4, "history did not restore repeat count")
  pressKey(Keyboard.KEY_UP)
  assertEqual(state.manualCommand, "giveitem c182", "second Up did not recall older command")
  assertEqual(state.repeatCount, 1, "single history entry restored wrong count")
  pressKey(Keyboard.KEY_DOWN)
  assertEqual(state.manualCommand, "spawn 5.10.1", "Down did not move toward newest command")
  pressKey(Keyboard.KEY_DOWN)
  assertEqual(state.manualCommand, "s", "Down past newest did not restore draft")
  assertEqual(state.repeatCount, 3, "draft repeat count was not restored")
  TEST.buttonPressed[Keyboard.KEY_RIGHT_CONTROL] = { [0] = true }
  TEST.keyTriggers[Keyboard.KEY_A] = true
  renderFrame()
  TEST.buttonPressed[Keyboard.KEY_RIGHT_CONTROL] = { [0] = false }
  pressKey(Keyboard.KEY_DELETE)
  assertEqual(state.manualCommand, "", "Delete did not clear selected command")
  assertEqual(state.commandSelectAll, false, "Delete retained command selection")
  pressKey(Keyboard.KEY_ESCAPE)
  assertEqual(state.inputMode, nil, "Esc did not leave command input")
  local layout = computeLayout(Isaac.GetScreenWidth(), Isaac.GetScreenHeight())
  clickMouse(layout.contentX + layout.pad + 1,
    layout.footerY + layout.pad + layout.line10 * 3 + 1)
  assertEqual(state.inputMode, "command", "clicking the command row did not enter command input")
  assertEqual(state.commandSelectAll, true, "clicked command was not selected")
  pressKey(Keyboard.KEY_ESCAPE)
  assertEqual(state.inputMode, nil, "Esc did not leave clicked command input")

end

local function renderedContainsExact(candidates)
  for _, rendered in ipairs(TEST.rendered) do
    for _, candidate in ipairs(candidates) do
      if rendered == candidate then return true end
    end
  end
  return false
end

local function testCategoryDescriptionMatrix()
  onStarted()
  openMenu()
  local expected = IS_ZH and {
    featured = { "最近收藏的条目优先显示。", "最近收藏的条目" },
    all_items = { "当前版本的全部收藏品", "当前版本全部收藏品" },
    trinkets = { "官方基础饰品；给予后可移除饰品本体。", "给予和移除饰品" },
    cards = { "官方卡牌、符文、逆位牌和魂石；只支持单次给予。", "单次给予卡牌和符文" },
    pills = { "官方基础胶囊效果；只支持单次给予。", "单次给予胶囊效果" },
    damage = { "伤害、射击方式与高强度叠加核心。", "伤害与射击强化" },
    defense = { "护盾、减伤与免疫道具", "护盾、减伤与免疫" },
    economy = { "商店、掉落与资源成长道具。", "商店、掉落与资源" },
    explore = { "地图显示、隐藏房与房间移动工具。", "地图、隐藏房与移动" },
    active = { "重随、回溯、重开与改变流程的强力主动道具。", "改变流程的主动道具" },
    familiar = { "输出、格挡与续航型跟班。", "输出与辅助跟班" },
    fun = { "适合测试构筑与制造夸张联动。", "测试构筑与趣味联动" },
    debug = { "无敌、高伤、无限充能与信息显示开关。再次点击同一 debug 命令可关闭。", "切换调试能力" },
    supply = { "生成资源、回复与当前房间辅助。", "生成资源与房间辅助" },
    stage = { "按当前模式显示安全楼层：正常模式 45 项，贪婪模式 7 项。", "按模式显示安全楼层" },
    run_control = { "执行调试开关、刷新、回溯、重开和楼层重置等运行命令。", "调试、刷新与运行控制" },
    command_reference = { "官方命令语法参考；参数命令需按 C 补全，禁用项只供查阅。", "官方语法与安全状态" },
  } or {
    featured = { "Your most recently favorited entries appear first.", "Recent favorite entries." },
    all_items = { "All collectibles in the current game version.", "All official collectibles." },
    trinkets = { "Official base trinkets. Granted trinkets can also be removed.", "Give and remove trinkets." },
    cards = { "Official cards, runes, reversed cards, and soul stones. Grants are single-use commands.", "Give cards and runes once." },
    pills = { "Official base pill effects. Grants are single-use commands.", "Give pill effects once." },
    damage = { "Damage upgrades, tear replacements, and powerful build-defining synergies.", "Damage and tear upgrades." },
    defense = { "Shields, damage reduction, and immunity.", "Shields and survival items." },
    economy = { "Shop value, pickup generation, and long-term resource growth.", "Shops, pickups, and resources." },
    explore = { "Map information, secret-room access, and room-navigation tools.", "Maps, secrets, and movement." },
    active = { "Rerolls, rewinds, restarts, and other run-changing active items.", "Run-changing active items." },
    familiar = { "Familiars for damage, projectile blocking, and sustain.", "Damage and support familiars." },
    fun = { "Experimental picks for testing builds and creating wild synergies.", "Experimental build tools." },
    debug = { "Invincibility, extreme damage, unlimited charge, and diagnostic overlays. Run the same debug command again to turn it off.", "Toggle debug flags." },
    supply = { "Spawn pickups, restore resources, and control the current room.", "Spawn pickups and resources." },
    stage = { "Shows the safe route for the current mode: 45 Normal/Hard destinations or 7 Greed destinations.", "Warp along the safe route." },
    run_control = { "Run debug toggles, refresh actions, rewinds, restarts, and floor resets.", "Debug, refresh, and run control" },
    command_reference = { "Official syntax reference. Press C to complete parameter commands; disabled entries are reference-only.", "Official syntax and safety status" },
  }

  for index, category in ipairs(runtimeCatalog.categories) do
    assertTrue(type(category.shortDesc) == "string" and category.shortDesc ~= "",
      "category is missing a deliberate short description: " .. category.id)
    state.categoryIndex = index
    state.categoryPage = math.floor((index - 1) / 5) + 1
    state.search = ""
    state.inputMode = nil
    state.page = 1
    state.selection = 1
    state.sidebarFocus = true
    TEST.rendered = {}
    renderFrame()
    assertTrue(expected[category.id] ~= nil, "category matrix is missing " .. category.id)
    assertTrue(renderedContainsExact({ category.name }),
      "category title is not complete and readable: " .. category.id)
    assertTrue(renderedContainsExact(expected[category.id]),
      "category description is not complete and readable: " .. category.id)
  end

  state.search = "sacred"
  state.inputMode = "search"
  TEST.rendered = {}
  renderFrame()
  local searchCandidates = IS_ZH
    and { "全部物品可输入全拼、首字母、英文、命令或 ID", "支持拼音、英文、命令或 ID" }
    or { "Name / alias / command / ID", "Name / alias / ID" }
  assertTrue(renderedContainsExact(searchCandidates), "search description is not complete and readable")
  local searchCategory = runtimeCatalog.categories[state.categoryIndex]
  assertTrue(not renderedContainsExact(expected[searchCategory.id]),
    "category footer overrode higher-priority search context")

  state.inputMode = "command"
  state.manualCommand = "spawn 5.10.1"
  state.commandSelectAll = false
  TEST.rendered = {}
  renderFrame()
  assertTrue(renderedContainsExact({ "spawn 5.10.1_" }),
    "command footer did not render the complete short command")
  assertTrue(not renderedContainsExact(expected[searchCategory.id]),
    "category footer overrode higher-priority command context")

  state.inputMode = nil
  TEST.rendered = {}
  renderFrame()
  local focusedCategory = runtimeCatalog.categories[state.categoryIndex]
  assertTrue(renderedContainsExact(expected[focusedCategory.id]),
    "search exit did not restore category-focused footer")

  TEST_CONFIG.greedMode = true
  state.search = ""
  state.inputMode = nil
  state.sidebarFocus = true
  for index, category in ipairs(runtimeCatalog.categories) do
    if category.id == "stage" then state.categoryIndex = index break end
  end
  TEST.rendered = {}
  renderFrame()
  local greedCandidates = IS_ZH
    and { "贪婪模式安全楼层：stage 1–7；隐藏楼层与后缀组合不开放",
      "贪婪模式安全楼层：stage 1–7", "贪婪楼层 stage 1–7" }
    or { "Greed safe route: stage 1-7; hidden floors and suffix combinations are blocked",
      "Greed route: stages 1-7.", "Greed stages 1-7." }
  assertTrue(renderedContainsExact(greedCandidates), "Greed description is not complete and readable")

  local category = runtimeCatalog.categories[state.categoryIndex]
  state.sidebarFocus = false
  TEST.rendered = {}
  renderFrame()
  assertTrue(not renderedContainsExact(expected[category.id]),
    "category description remained visible after grid regained focus")
  local sawEntryDetail = false
  for _, value in ipairs(TEST.rendered) do
    if contains(value, IS_ZH and "说明 " or "Details ") then sawEntryDetail = true end
  end
  assertTrue(sawEntryDetail, "grid focus did not restore entry details")
end

local function triggerTextKeyWithConfirm(key)
  local index = TEST_CONFIG.controllerIndex or 0
  TEST.keyTriggers[key] = true
  TEST.actionTriggers[ButtonAction.ACTION_MENUCONFIRM] = { [index] = true }
  renderFrame()
end

local function testEditableTextConfirmCollision()
  onStarted()
  openMenu()
  state.inputMode = "command"
  state.manualCommand = ""
  state.commandSelectAll = false
  local expected = ""
  for _, spec in ipairs({
      { keyForCharacter("g"), "g" },
      { Keyboard.KEY_SPACE, " " },
      { Keyboard.KEY_PERIOD, "." },
      { Keyboard.KEY_MINUS, "-" },
      { Keyboard.KEY_SLASH, "/" },
      { Keyboard.KEY_EQUAL, "=" },
      { keyForCharacter("1"), "1" },
    }) do
    triggerTextKeyWithConfirm(spec[1])
    expected = expected .. spec[2]
    assertEqual(state.manualCommand, expected,
      "supported text key was submitted instead of inserted")
    assertEqual(state.inputMode, "command", "text key left command input")
    assertEqual(state.open, true, "text key closed the menu")
    assertTrue(state.queue == nil, "text key queued a command")
  end

  state.inputMode = "search"
  state.search = "g"
  state.searchSelectAll = false
  triggerTextKeyWithConfirm(Keyboard.KEY_SPACE)
  assertEqual(state.search, "g ", "Space submitted instead of extending search")
  assertEqual(state.inputMode, "search", "Space left search input")
  assertEqual(state.open, true, "Space closed menu from search input")

  state.inputMode = "command"
  state.manualCommand = "spawn 5.10.1"
  state.commandSelectAll = false
  TEST.buttonPressed[Keyboard.KEY_ENTER] = { [0] = true }
  renderFrame()
  assertEqual(state.open, false, "first Enter press without trigger report did not submit")
  assertTrue(state.queue ~= nil, "first Enter press did not queue command")
  local firstQueue = state.queue
  renderFrame()
  assertTrue(state.queue == firstQueue, "held Enter submitted more than once")
  TEST.buttonPressed[Keyboard.KEY_ENTER] = { [0] = false }
  renderFrame()
  onUpdate()
  openMenu()
  state.inputMode = "command"
  state.manualCommand = "spawn 5.10.1"
  state.commandSelectAll = false
  pressButton(TEST_CONFIG.physicalConfirmButton or Controller.BUTTON_A)
  assertEqual(state.open, false, "controller confirm no longer submitted command")
  assertTrue(state.queue ~= nil, "controller confirm did not queue command")
  onUpdate()
  openMenu()
  state.inputMode = "command"
  state.manualCommand = "spawn 5.10.1"
  state.commandSelectAll = false
  pressKey(Keyboard.KEY_ENTER)
  assertEqual(state.open, false, "Enter no longer submitted command")
  assertTrue(state.queue ~= nil, "Enter did not queue command")
end

local function testPauseSuspension()
  onStarted()
  openMenu()
  state.search = "giveitem"
  state.inputMode = "search"
  state.selection = 2
  TEST.rendered = {}
  TEST.paused = true
  renderFrame()
  assertEqual(#TEST.rendered, 0, "paused overlay still rendered")
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE), nil,
    "paused overlay still blocked native pause input")
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_JOINMULTIPLAYER), nil,
    "controller disconnect recovery input was blocked")
  assertEqual(state.open, true, "pause closed the overlay instead of suspending it")
  local executedBefore = #TEST.executed
  TEST_CONFIG.playerControllerIndexes = { 1 }
  TEST_CONFIG.controllerIndex = 1
  TEST.keyTriggers[Keyboard.KEY_ENTER] = true
  TEST.paused = false
  renderFrame()
  assertEqual(#TEST.executed, executedBefore, "resume input penetrated into the overlay")
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_JOINMULTIPLAYER), 0.0,
    "post-reconnect join input penetrated beyond the recovery frame")
  assertEqual(state.search, "giveitem", "resume lost the search text")
  assertEqual(state.inputMode, "search", "resume lost input focus")
  assertEqual(state.selection, 2, "resume lost selection")
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE), 0.0,
    "resumed overlay did not reclaim input")
  TEST.actionTriggers[ButtonAction.ACTION_MENUBACK] = { [1] = true }
  renderFrame()
  assertEqual(state.controllerIndex, 1,
    "reconnected controller was not reacquired from the player's current assignment")
  assertEqual(state.inputMode, nil,
    "reconnected controller did not regain ownership of the focused search field")
  pressKey(Keyboard.KEY_F6)
  assertEqual(state.open, false, "F6 did not close the resumed overlay")
  TEST.paused = true
  pressKey(Keyboard.KEY_F6)
  assertEqual(state.open, false, "F6 opened the overlay over native pause")
  holdButton(Controller.STICK_LEFT, 30)
  assertEqual(state.open, false, "L3 opened the overlay over native pause")
  TEST.paused = false
  releaseButton(Controller.STICK_LEFT)

end

local function testAssignedControllerIsolation()
  onStarted()
  openMenu()
  local assigned = TEST_CONFIG.controllerIndex or 0
  local unassigned = TEST_CONFIG.unassignedControllerIndex or 3
  assertTrue(assigned ~= unassigned, "assigned-controller scenario needs distinct indexes")

  state.categoryIndex = 2
  state.page = 1
  state.selection = 1
  TEST.actionTriggers[ButtonAction.ACTION_MENUDOWN] = { [unassigned] = true }
  TEST.buttonTriggers[Controller.DPAD_DOWN] = { [unassigned] = true }
  renderFrame()
  assertEqual(state.selection, 1, "unassigned controller moved the Mod focus")
  assertTrue(state.controllerIndex ~= unassigned,
    "unassigned controller became the active Mod controller")

  TEST.actionTriggers[ButtonAction.ACTION_MENUCONFIRM] = { [unassigned] = true }
  TEST.actionPressed[ButtonAction.ACTION_MENUCONFIRM] = { [unassigned] = true }
  TEST.buttonTriggers[Controller.BUTTON_A] = { [unassigned] = true }
  TEST.buttonPressed[Controller.BUTTON_A] = { [unassigned] = true }
  renderFrame()
  assertEqual(state.controllerConfirmCommand, nil,
    "unassigned controller started a command")
  assertEqual(state.open, true, "unassigned controller closed the menu")

  TEST.actionPressed[ButtonAction.ACTION_MENUCONFIRM] = { [unassigned] = false }
  TEST.buttonPressed[Controller.BUTTON_A] = { [unassigned] = false }
  TEST.actionTriggers[ButtonAction.ACTION_MENUDOWN] = { [assigned] = true }
  renderFrame()
  assertEqual(state.selection, 3, "assigned controller stopped navigating")
end

local function testClosingInputLease()
  local function assertGameInputBlocked(label)
    assertTrue(state.inputLease ~= nil, label .. " did not arm an input lease")
    assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
      ButtonAction.ACTION_JOINMULTIPLAYER), 0.0,
      label .. " leaked residual input to the game")
  end

  local function releaseKeyboard(key)
    TEST.buttonPressed[key] = { [0] = false }
    renderFrame()
    assertEqual(state.inputLease, nil, "keyboard input lease survived release")
    assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
      ButtonAction.ACTION_JOINMULTIPLAYER), nil,
      "released keyboard input remained blocked")
    onUpdate()
  end

  onStarted()
  openMenu()
  state.inputMode = "command"
  state.manualCommand = "spawn 5.10.3"
  state.commandSelectAll = false
  TEST.buttonPressed[Keyboard.KEY_ENTER] = { [0] = true }
  TEST.keyTriggers[Keyboard.KEY_ENTER] = true
  renderFrame()
  assertEqual(state.open, false, "manual command Enter did not close the menu")
  assertGameInputBlocked("manual command Enter")
  TEST.paused = true
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_JOINMULTIPLAYER), nil,
    "input lease blocked the native pause or reconnect dialog")
  TEST.paused = false
  releaseKeyboard(Keyboard.KEY_ENTER)

  openMenu()
  state.search = "giveitem c182"
  state.categoryIndex = 2
  state.page = 1
  state.selection = 1
  state.sidebarFocus = false
  assertTrue(#visibleEntries() > 0, "entry Enter setup has no executable entry")
  TEST.buttonPressed[Keyboard.KEY_ENTER] = { [0] = true }
  TEST.keyTriggers[Keyboard.KEY_ENTER] = true
  renderFrame()
  assertEqual(state.open, false, "entry Enter did not close the menu")
  assertGameInputBlocked("entry Enter")
  releaseKeyboard(Keyboard.KEY_ENTER)

  openMenu()
  TEST.buttonPressed[Keyboard.KEY_ESCAPE] = { [0] = true }
  TEST.keyTriggers[Keyboard.KEY_ESCAPE] = true
  renderFrame()
  assertEqual(state.open, false, "Escape did not close the menu")
  assertGameInputBlocked("Escape close")
  releaseKeyboard(Keyboard.KEY_ESCAPE)

  openMenu()
  local openKey = state.openKey or Keyboard.KEY_F6
  TEST.buttonPressed[openKey] = { [0] = true }
  TEST.keyTriggers[openKey] = true
  renderFrame()
  assertEqual(state.open, false, "open key did not close the menu")
  assertGameInputBlocked("open-key close")
  releaseKeyboard(openKey)

  openMenu()
  state.inputMode = "command"
  state.manualCommand = "spawn 5.10.3"
  pressButton(TEST_CONFIG.physicalConfirmButton or Controller.BUTTON_A)
  assertEqual(state.open, false, "controller command confirm did not close the menu")
  assertGameInputBlocked("controller command confirm")
  renderFrame()
  assertEqual(state.inputLease, nil, "controller input lease survived release")

  -- A run transition owns controller assignment. It must clear every Mod lease,
  -- even if the closing key is still physically held when the callback arrives.
  openMenu()
  state.inputMode = "command"
  state.manualCommand = "spawn 5.10.3"
  TEST.buttonPressed[Keyboard.KEY_ENTER] = { [0] = true }
  TEST.keyTriggers[Keyboard.KEY_ENTER] = true
  renderFrame()
  assertGameInputBlocked("pre-R Enter")
  onStarted()
  assertEqual(state.inputLease, nil, "R/Rewind callback retained a closing input lease")
  assertEqual(state.nativePauseSuspended, false, "R/Rewind callback retained pause suspension")
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_JOINMULTIPLAYER), nil,
    "R/Rewind callback blocked controller reassignment")
  TEST.buttonPressed[Keyboard.KEY_ENTER] = { [0] = false }

  -- Pause suspension is a Mod-render concern, never a game-input gate.
  state.nativePauseSuspended = true
  assertEqual(onInput(registeredMod, 0, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_JOINMULTIPLAYER), nil,
    "pause suspension leaked into the game input boundary")
  state.nativePauseSuspended = false
end

local function testControllerRepeat()
  onStarted()
  openMenu()
  local index = TEST_CONFIG.controllerIndex or 0
  state.repeatCount = 1
  state.page = 1
  if ButtonAction.ACTION_MENURB then
    TEST.actionTriggers[ButtonAction.ACTION_MENURB] = { [index] = true }
  end
  TEST.buttonTriggers[Controller.BUMPER_RIGHT] = { [index] = true }
  renderFrame()
  assertEqual(state.repeatCount, 2, "RB did not increase repeat exactly once")
  assertEqual(state.page, 1, "RB turned into page-next")
  if ButtonAction.ACTION_MENULB then
    TEST.actionTriggers[ButtonAction.ACTION_MENULB] = { [index] = true }
  end
  TEST.buttonTriggers[Controller.BUMPER_LEFT] = { [index] = true }
  renderFrame()
  assertEqual(state.repeatCount, 1, "LB did not decrease repeat exactly once")
  assertEqual(state.page, 1, "LB turned into page-previous")

  if ButtonAction.ACTION_MENURB and not TEST_CONFIG.actionsUnavailable then
    TEST.actionTriggers[ButtonAction.ACTION_MENURB] = { [index] = true }
    renderFrame()
    assertEqual(state.repeatCount, 2, "Steam Input semantic RB did not increase repeat")
    TEST.actionTriggers[ButtonAction.ACTION_MENULB] = { [index] = true }
    renderFrame()
    assertEqual(state.repeatCount, 1, "Steam Input semantic LB did not decrease repeat")
  end

  -- Steam Input can report one physical bumper as a bumper trigger first, then
  -- keep the same-side trigger action value high on following frames. The
  -- bumper owns that press until every same-side signal has returned to rest.
  state.page = 1
  TEST.buttonTriggers[Controller.BUMPER_RIGHT] = { [index] = true }
  TEST.buttonPressed[Controller.BUMPER_RIGHT] = { [index] = true }
  if ButtonAction.ACTION_MENURB then
    TEST.actionTriggers[ButtonAction.ACTION_MENURB] = { [index] = true }
    TEST.actionPressed[ButtonAction.ACTION_MENURB] = { [index] = true }
  end
  TEST.actionValues[ButtonAction.ACTION_MENURT] = { [index] = 0.75 }
  renderFrame()
  assertEqual(state.repeatCount, 2, "RB collision did not adjust repeat exactly once")
  assertEqual(state.page, 1, "RB collision paged on its trigger frame")
  if ButtonAction.ACTION_MENURB then TEST.actionPressed[ButtonAction.ACTION_MENURB] = nil end
  renderFrame()
  assertEqual(state.repeatCount, 2, "held RB collision repeated the count")
  assertEqual(state.page, 1, "held RB collision paged on a later frame")
  TEST.buttonPressed[Controller.BUMPER_RIGHT] = nil
  TEST.actionValues[ButtonAction.ACTION_MENURT] = { [index] = 0.2 }
  renderFrame()
  TEST.actionValues[ButtonAction.ACTION_MENURT] = nil

  state.page = 2
  TEST.buttonTriggers[Controller.BUMPER_LEFT] = { [index] = true }
  TEST.buttonPressed[Controller.BUMPER_LEFT] = { [index] = true }
  if ButtonAction.ACTION_MENULB then
    TEST.actionTriggers[ButtonAction.ACTION_MENULB] = { [index] = true }
    TEST.actionPressed[ButtonAction.ACTION_MENULB] = { [index] = true }
  end
  TEST.actionValues[ButtonAction.ACTION_MENULT] = { [index] = 0.75 }
  renderFrame()
  assertEqual(state.repeatCount, 1, "LB collision did not adjust repeat exactly once")
  assertEqual(state.page, 2, "LB collision paged on its trigger frame")
  if ButtonAction.ACTION_MENULB then TEST.actionPressed[ButtonAction.ACTION_MENULB] = nil end
  renderFrame()
  assertEqual(state.repeatCount, 1, "held LB collision repeated the count")
  assertEqual(state.page, 2, "held LB collision paged on a later frame")
  TEST.buttonPressed[Controller.BUMPER_LEFT] = nil
  TEST.actionValues[ButtonAction.ACTION_MENULT] = { [index] = 0.2 }
  renderFrame()
  TEST.actionValues[ButtonAction.ACTION_MENULT] = nil

  -- The reverse collision must also be stable: a real trigger can emit a
  -- same-side bumper semantic action under Steam Input. Analog/trigger
  -- evidence wins when the physical bumper is not held.
  state.repeatCount = 7
  if ButtonAction.ACTION_MENULB and ButtonAction.ACTION_MENURB
      and ButtonAction.ACTION_MENULT and ButtonAction.ACTION_MENURT then
    state.page = 1
    TEST.actionTriggers[ButtonAction.ACTION_MENURB] = { [index] = true }
    TEST.actionTriggers[ButtonAction.ACTION_MENURT] = { [index] = true }
    TEST.actionValues[ButtonAction.ACTION_MENURT] = { [index] = 0.75 }
    TEST.buttonTriggers[Controller.TRIGGER_RIGHT] = { [index] = true }
    TEST.buttonPressed[Controller.TRIGGER_RIGHT] = { [index] = true }
    renderFrame()
    assertEqual(state.repeatCount, 7, "RT collision changed the repeat count")
    assertEqual(state.page, 2, "RT collision did not page exactly once")
    TEST.buttonPressed[Controller.TRIGGER_RIGHT] = nil
    TEST.actionValues[ButtonAction.ACTION_MENURT] = { [index] = 0.2 }
    renderFrame()
    TEST.actionValues[ButtonAction.ACTION_MENURT] = nil

    state.page = 2
    TEST.actionTriggers[ButtonAction.ACTION_MENULB] = { [index] = true }
    TEST.actionTriggers[ButtonAction.ACTION_MENULT] = { [index] = true }
    TEST.actionValues[ButtonAction.ACTION_MENULT] = { [index] = 0.75 }
    TEST.buttonTriggers[Controller.TRIGGER_LEFT] = { [index] = true }
    TEST.buttonPressed[Controller.TRIGGER_LEFT] = { [index] = true }
    renderFrame()
    assertEqual(state.repeatCount, 7, "LT collision changed the repeat count")
    assertEqual(state.page, 1, "LT collision did not page exactly once")
    TEST.buttonPressed[Controller.TRIGGER_LEFT] = nil
    TEST.actionValues[ButtonAction.ACTION_MENULT] = { [index] = 0.2 }
    renderFrame()
    TEST.actionValues[ButtonAction.ACTION_MENULT] = nil
  end

  state.inputMode = "command"
  state.repeatCount = 1
  if ButtonAction.ACTION_MENURB then
    TEST.actionTriggers[ButtonAction.ACTION_MENURB] = { [index] = true }
  end
  TEST.buttonTriggers[Controller.BUMPER_RIGHT] = { [index] = true }
  renderFrame()
  assertEqual(state.repeatCount, 2, "RB did not change repeat in command mode")
  state.inputMode = "search"
  TEST.buttonTriggers[Controller.BUMPER_RIGHT] = { [index] = true }
  if ButtonAction.ACTION_MENURB then
    TEST.actionTriggers[ButtonAction.ACTION_MENURB] = { [index] = true }
  end
  renderFrame()
  assertEqual(state.repeatCount, 2, "RB changed repeat in search mode")
  state.inputMode = nil
  state.repeatCount = 99
  TEST.buttonTriggers[Controller.BUMPER_RIGHT] = { [index] = true }
  renderFrame()
  assertEqual(state.repeatCount, 99, "RB exceeded repeat upper bound")
end

local function renderedCount(expected)
  local count = 0
  for _, value in ipairs(TEST.rendered) do
    if value == expected then count = count + 1 end
  end
  return count
end

local function triggerControllerPage(action, button, controllerIndex)
  if action ~= nil then TEST.actionTriggers[action] = { [controllerIndex] = true } end
  TEST.buttonTriggers[button] = { [controllerIndex] = true }
  renderFrame()
end

local function testControllerPaging()
  onStarted()
  openMenu()
  local index = TEST_CONFIG.controllerIndex or 0

  state.search = ""
  state.inputMode = nil
  state.categoryIndex = 2
  state.categoryPage = 1
  state.page = 1
  state.selection = 4
  state.sidebarFocus = false
  state.repeatCount = 7
  TEST.rendered = {}
  triggerControllerPage(ButtonAction.ACTION_MENURT, Controller.TRIGGER_RIGHT, index)
  assertEqual(state.page, 2, "semantic/raw RT did not advance exactly one entry page")
  assertEqual(state.selection, 1, "entry paging did not select the first item")
  assertEqual(state.repeatCount, 7, "RT changed the repeat count")
  assertEqual(renderedCount("LT"), 1, "grid focus did not show one active LT hint")
  assertEqual(renderedCount("RT"), 1, "grid focus did not show one active RT hint")

  if not TEST_CONFIG.actionsUnavailable then
    state.page = 1
    state.selection = 1
    TEST.actionValues[ButtonAction.ACTION_MENURT] = { [index] = 0.75 }
    renderFrame()
    assertEqual(state.page, 2, "Steam Deck analog RT did not page")
    renderFrame()
    assertEqual(state.page, 2, "held analog RT repeated without release")
    TEST.actionValues[ButtonAction.ACTION_MENURT] = { [index] = 0.2 }
    renderFrame()
    assertEqual(state.page, 2, "analog RT release changed the page")
    TEST.actionValues[ButtonAction.ACTION_MENURT] = { [index] = 0.75 }
    renderFrame()
    assertEqual(state.page, 3, "analog RT did not re-arm after release")
    TEST.actionValues[ButtonAction.ACTION_MENURT] = nil
    state.page = 2
  end

  triggerControllerPage(ButtonAction.ACTION_MENULT, Controller.TRIGGER_LEFT, index)
  assertEqual(state.page, 1, "semantic/raw LT did not return one entry page")
  local entries = visibleEntries()
  local lastEntryPage = math.max(1, math.ceil(#entries / 8))
  state.page = lastEntryPage
  state.selection = 4
  triggerControllerPage(ButtonAction.ACTION_MENURT, Controller.TRIGGER_RIGHT, index)
  assertEqual(state.page, lastEntryPage, "RT wrapped past the last entry page")
  assertEqual(state.selection, 4, "last entry page boundary reset the selection")
  state.page = 1
  state.selection = 4
  triggerControllerPage(ButtonAction.ACTION_MENULT, Controller.TRIGGER_LEFT, index)
  assertEqual(state.page, 1, "LT wrapped before the first entry page")
  assertEqual(state.selection, 4, "first entry page boundary reset the selection")

  state.search = ""
  state.categoryIndex = 1
  state.categoryPage = 1
  state.page = 3
  state.selection = 4
  state.sidebarFocus = true
  TEST.rendered = {}
  triggerControllerPage(ButtonAction.ACTION_MENURT, Controller.TRIGGER_RIGHT, index)
  assertEqual(state.categoryPage, 2, "RT did not advance the focused category page")
  assertEqual(state.categoryIndex, 7, "category paging did not select the target page's first category")
  assertEqual(state.page, 1, "category paging did not reset the entry page")
  assertEqual(state.selection, 1, "category paging did not reset the entry selection")
  assertEqual(renderedCount("LT"), 1, "category focus did not show one active LT hint")
  assertEqual(renderedCount("RT"), 1, "category focus did not show one active RT hint")

  triggerControllerPage(ButtonAction.ACTION_MENULT, Controller.TRIGGER_LEFT, index)
  assertEqual(state.categoryPage, 1, "LT did not return one category page")
  assertEqual(state.categoryIndex, 1, "category previous-page target differs")
  local lastCategoryPage = math.max(1, math.ceil(#runtimeCatalog.categories / 6))
  local firstCategoryOnLastPage = (lastCategoryPage - 1) * 6 + 1
  state.categoryPage = lastCategoryPage
  state.categoryIndex = firstCategoryOnLastPage
  triggerControllerPage(ButtonAction.ACTION_MENURT, Controller.TRIGGER_RIGHT, index)
  assertEqual(state.categoryPage, lastCategoryPage, "RT wrapped past the last category page")
  assertEqual(state.categoryIndex, firstCategoryOnLastPage, "last category page boundary changed category")
  state.categoryPage = 1
  state.categoryIndex = 2
  triggerControllerPage(ButtonAction.ACTION_MENULT, Controller.TRIGGER_LEFT, index)
  assertEqual(state.categoryPage, 1, "LT wrapped before the first category page")
  assertEqual(state.categoryIndex, 2, "first category page boundary changed category")

  state.categoryIndex = 2
  state.categoryPage = 1
  state.sidebarFocus = false
  state.page = 1
  state.inputMode = "search"
  TEST.rendered = {}
  triggerControllerPage(ButtonAction.ACTION_MENURT, Controller.TRIGGER_RIGHT, index)
  assertEqual(state.page, 1, "RT paged while search input owned focus")
  assertEqual(renderedCount("LT") + renderedCount("RT"), 0,
    "search input displayed an active controller pager")
  state.inputMode = "command"
  TEST.rendered = {}
  triggerControllerPage(ButtonAction.ACTION_MENURT, Controller.TRIGGER_RIGHT, index)
  assertEqual(state.page, 1, "RT paged while command input owned focus")
  assertEqual(renderedCount("LT") + renderedCount("RT"), 0,
    "command input displayed an active controller pager")

  state.inputMode = nil
  state.search = "giveitem"
  state.page = 1
  assertTrue(#visibleEntries() > 8, "search paging setup does not have multiple pages")
  triggerControllerPage(ButtonAction.ACTION_MENURT, Controller.TRIGGER_RIGHT, index)
  assertEqual(state.page, 2, "RT did not page non-editing search results")

  state.search = ""
  state.categoryIndex = 2
  state.categoryPage = 1
  state.page = 1
  state.selection = 1
  state.sidebarFocus = false
  pressDirection(ButtonAction.ACTION_MENULEFT, Controller.DPAD_LEFT, index, true)
  assertEqual(state.sidebarFocus, true, "left from the first grid column did not focus categories")
  pressDirection(ButtonAction.ACTION_MENURIGHT, Controller.DPAD_RIGHT, index, true)
  assertEqual(state.sidebarFocus, false, "right from categories did not restore grid focus")
end

local function testMcmSettings254()
  assertTrue(TEST_CONFIG.mcm, "MCM 2.5.4 scenario requires optional MCM")
  onStarted()
  assertEqual(TEST.mcmAddCalls, 4, "MCM did not register all four settings")
  local favoriteSetting, startupSetting, closeSetting
  for _, setting in ipairs(TEST.mcmSettings) do
    if setting.Type == ModConfigMenu.OptionType.KEYBIND_CONTROLLER then favoriteSetting = setting end
    if setting.Type == ModConfigMenu.OptionType.BOOLEAN then
      local display = type(setting.Display) == "function" and tostring(setting.Display()) or ""
      if contains(display, IS_ZH and "进入游戏时显示键位提示" or "Show startup key hint") then
        startupSetting = setting
      elseif contains(display, IS_ZH and "普通命令执行后关闭界面" or "Close menu after regular commands") then
        closeSetting = setting
      end
    end
  end
  assertTrue(type(favoriteSetting) == "table", "controller favorite setting missing")
  assertTrue(type(startupSetting) == "table", "startup hint setting missing")
  assertTrue(type(closeSetting) == "table", "regular-command close setting missing")
  if IS_ZH then
    local displays = {}
    for _, setting in ipairs(TEST.mcmSettings) do
      if type(setting.Display) == "function" then displays[#displays + 1] = tostring(setting.Display()) end
    end
    local expectedDisplays = {
      "键盘呼出键: F6",
      "手柄收藏键: 自动",
      "进入游戏时显示键位提示: 开启",
      "普通命令执行后关闭界面: 开启",
    }
    for _, expected in ipairs(expectedDisplays) do
      local found = false
      for _, display in ipairs(displays) do
        if display == expected then found = true break end
      end
      assertTrue(found, "MCM display does not use a visible ASCII separator: " .. expected)
    end
  end
  assertEqual(favoriteSetting.CurrentSetting(), -1, "controller favorite default is not Automatic")
  assertEqual(startupSetting.CurrentSetting(), true, "startup hint default is not enabled")
  assertEqual(closeSetting.CurrentSetting(), true, "regular-command close default is not enabled")

  startupSetting.OnChange(false)
  assertEqual(state.startupHintEnabled, false, "startup hint setting did not turn off")
  assertTrue(contains(TEST.saveData, "startupHintEnabled=0\n"), "startup hint setting was not persisted")
  favoriteSetting.OnChange(9)
  assertEqual(state.controllerFavoriteButton, 9, "custom favorite button was not applied")
  assertTrue(contains(TEST.saveData, "controllerFavoriteButton=9\n"), "custom favorite button was not persisted")
  favoriteSetting.OnChange(32)
  assertEqual(state.controllerFavoriteButton, 9, "invalid favorite button replaced the binding")

  closeSetting.OnChange(false)
  assertEqual(state.closeAfterRegularCommand, false, "regular-command close setting did not turn off")
  assertTrue(contains(TEST.saveData, "closeAfterRegularCommand=0\n"),
    "regular-command close setting was not persisted")

  openMenu()
  state.categoryIndex = 2
  state.categoryPage = 1
  state.page = 2
  state.selection = 3
  state.sidebarFocus = false
  state.inputMode = "command"
  state.manualCommand = "giveitem c5"
  assertTrue(queueCommand(state.manualCommand, 1), "ordinary command was rejected with keep-open enabled")
  assertEqual(state.open, true, "ordinary command closed the menu despite keep-open setting")
  assertEqual(state.inputMode, nil, "ordinary command left the command editor active")
  assertEqual(state.manualCommand, "giveitem c5", "ordinary command text was not retained")
  assertEqual(state.categoryIndex, 2, "ordinary command changed the selected category")
  assertEqual(state.page, 2, "ordinary command changed the selected page")
  assertEqual(state.selection, 3, "ordinary command changed the selected entry")
  assertEqual(queueCommand("giveitem c6", 1), false, "ordinary command queue accepted concurrent work")
  onUpdate()
  assertEqual(state.queue, nil, "ordinary keep-open command did not finish")
  assertEqual(TEST.executed[#TEST.executed], "giveitem c5", "ordinary keep-open command executed incorrectly")
  assertEqual(state.open, true, "ordinary command closed the menu after queue completion")

  assertEqual(queueCommand("lua error('blocked')", 1), false, "disabled command bypassed the safety gate")
  assertEqual(state.open, true, "disabled command closed the menu")
  state.inputMode = "command"
  state.manualCommand = "thirdparty_keep_open"
  assertEqual(queueCommand(state.manualCommand, 1), false, "unknown command skipped confirmation")
  assertEqual(state.open, true, "unknown-command confirmation closed the menu")
  state.unknownCommandConfirmation = nil
  state.inputMode = nil

  assertTrue(queueCommand("rewind", 1), "lifecycle command was rejected with keep-open enabled")
  assertEqual(state.open, false, "lifecycle command did not force the menu closed")
  assertTrue(state.lifecycleRequest ~= nil, "lifecycle command did not enter the render dispatcher")
  onStarted()
  assertEqual(state.closeAfterRegularCommand, false,
    "lifecycle boundary did not retain the regular-command close setting")

  TEST_CONFIG.saveFail = true
  startupSetting.OnChange(true)
  assertEqual(state.startupHintEnabled, false, "failed startup setting save did not roll back")
  favoriteSetting.OnChange(10)
  assertEqual(state.controllerFavoriteButton, 9, "failed favorite setting save did not roll back")
  closeSetting.OnChange(true)
  assertEqual(state.closeAfterRegularCommand, false,
    "failed regular-command close setting save did not roll back")
  TEST_CONFIG.saveFail = false

  state.loaded = false
  onStarted()
  assertEqual(state.startupHintEnabled, false, "startup hint setting did not reload")
  assertEqual(state.controllerFavoriteButton, 9, "favorite button setting did not reload")
  assertEqual(state.closeAfterRegularCommand, false, "regular-command close setting did not reload")
end
local function findObject(key)
  for _, entry in ipairs(allEntries) do
    if entry.objectKey == key then return entry end
  end
  return nil
end

local function testAllEntryFavorites()
  onStarted()
  openMenu()

  local entriesByKey = {}
  local commandCount, objectCount = 0, 0
  for _, entry in ipairs(allEntries) do
    local key = entry.objectKey
    assertTrue(entry.canFavorite == true, "catalog entry is not favoriteable: " .. tostring(key))
    assertTrue(type(key) == "string" and key ~= "", "catalog entry has no stable favorite key")
    assertTrue(entriesByKey[key] == nil, "duplicate catalog favorite key: " .. key)
    entriesByKey[key] = entry
    if entry.kind == "command" then commandCount = commandCount + 1
    else objectCount = objectCount + 1 end
  end
  assertEqual(#allEntries, 1162, "complete favoriteable catalog count differs")
  assertEqual(objectCount, 1056, "official object favorite count differs")
  assertEqual(commandCount, 106, "command favorite count differs")

  local forbiddenDescriptionTerms = IS_ZH
    and { "ItemConfig", "生命周期", "回调", "派发", "运行对象" }
    or { "itemconfig", "lifecycle", "callback", "dispatcher", "dispatch", "live game objects" }
  for _, entry in ipairs(allEntries) do
    if entry.kind == "command" then
      local description = IS_ZH and tostring(entry.desc or "") or string.lower(tostring(entry.desc or ""))
      for _, term in ipairs(forbiddenDescriptionTerms) do
        assertTrue(not string.find(description, term, 1, true),
          "command description exposes implementation detail '" .. term .. "': " .. tostring(entry.commandId))
      end
    end
  end

  local expectedCommands = {
    { "m:debug:execute:any:debug%2012", "execute" },
    { "m:rewind:execute:any:rewind", "execute" },
    { "m:goto:manual:any:-", "manual" },
    { "m:lua:disabled:any:-", "disabled" },
    { "m:stage:execute:normal:stage%201", "execute" },
    { "m:stage:execute:greed:stage%201", "execute" },
  }
  for _, expected in ipairs(expectedCommands) do
    local entry = entriesByKey[expected[1]]
    assertTrue(entry ~= nil, "language-independent command favorite key missing: " .. expected[1])
    assertEqual(entry.catalogAction, expected[2], "favoriting changed command permission: " .. expected[1])
  end

  local recentSequence = {
    "m:debug:execute:any:debug%2012",
    "m:goto:manual:any:-",
    "m:lua:disabled:any:-",
    "m:rewind:execute:any:rewind",
  }
  for _, key in ipairs(recentSequence) do toggleFavorite(entriesByKey[key]) end
  for index, key in ipairs({
      "m:rewind:execute:any:rewind",
      "m:lua:disabled:any:-",
      "m:goto:manual:any:-",
      "m:debug:execute:any:debug%2012",
    }) do
    assertEqual(state.favoriteOrder[index], key, "recent favorite order differs at " .. index)
  end
  assertTrue(contains(TEST.saveData, "favoriteOrder=recent\n"), "recent favorite marker was not saved")

  local gotoEntry = entriesByKey["m:goto:manual:any:-"]
  toggleFavorite(gotoEntry)
  toggleFavorite(gotoEntry)
  assertEqual(state.favoriteOrder[1], gotoEntry.objectKey,
    "removing and re-adding a favorite did not move it to the front")

  local disabledEntry = entriesByKey["m:lua:disabled:any:-"]
  local executedBeforeDisabled = #TEST.executed
  assertEqual(queueEntry(disabledEntry, 99), false, "favorited disabled command entered the queue")
  assertEqual(#TEST.executed, executedBeforeDisabled, "favorited disabled command executed")
  assertEqual(queueEntry(gotoEntry, 99), false, "favorited parameter reference entered the execution queue")
  assertEqual(state.inputMode, nil, "favorited parameter reference bypassed the C-key editor gate")
  assertTrue(state.toast ~= nil, "favorited parameter reference did not retain its C-key guidance")

  state.search = "costumetest"
  state.page = 1
  state.selection = 1
  state.sidebarFocus = false
  local costumeResults = visibleEntries()
  assertEqual(#costumeResults, 1, "costumetest search is not unique for input favorite test")
  local costumeKey = costumeResults[1].objectKey
  pressKey(Keyboard.KEY_F)
  assertTrue(state.favorites[costumeKey] == true, "keyboard F did not favorite a command entry")
  pressButton(TEST_CONFIG.physicalFavoriteButton or Controller.BUTTON_X)
  assertTrue(state.favorites[costumeKey] == nil, "controller X did not unfavorite a command entry")
  pressButton(TEST_CONFIG.physicalFavoriteButton or Controller.BUTTON_X)
  assertTrue(state.favorites[costumeKey] == true, "controller X did not re-favorite a command entry")

  local normalStageKey = "m:stage:execute:normal:stage%201"
  local greedStageKey = "m:stage:execute:greed:stage%201"
  toggleFavorite(entriesByKey[normalStageKey])
  toggleFavorite(entriesByKey[greedStageKey])
  state.categoryIndex = 1
  state.search = ""
  TEST_CONFIG.greedMode = false
  local normalVisible = {}
  for _, entry in ipairs(visibleEntries()) do normalVisible[entry.objectKey] = true end
  assertTrue(normalVisible[normalStageKey] == true and normalVisible[greedStageKey] == nil,
    "normal mode did not filter mode-specific stage favorites")
  TEST_CONFIG.greedMode = true
  local greedVisible = {}
  for _, entry in ipairs(visibleEntries()) do greedVisible[entry.objectKey] = true end
  assertTrue(greedVisible[normalStageKey] == nil and greedVisible[greedStageKey] == true,
    "Greed mode did not filter mode-specific stage favorites")
  TEST_CONFIG.greedMode = false

  state.search = "restock"
  state.page = 1
  state.selection = 1
  state.sidebarFocus = false
  local restockResults = visibleEntries()
  assertEqual(#restockResults, 1, "restock search is not unique for mouse favorite test")
  local restockKey = restockResults[1].objectKey
  assertTrue(state.favorites[restockKey] == nil, "mouse favorite test entry was already selected")
  local layout = computeLayout(TEST_CONFIG.screenWidth or 1280, TEST_CONFIG.screenHeight or 720)
  local executedBeforeMouse = #TEST.executed
  clickMouse(layout.contentX + layout.cardW - math.floor(layout.starW / 2),
    layout.gridY + math.floor(layout.cardH / 2), 0)
  assertTrue(state.favorites[restockKey] == true, "hollow star click did not add favorite")
  assertEqual(#TEST.executed, executedBeforeMouse, "star click also executed its command entry")
  clickMouse(layout.contentX + layout.cardW - math.floor(layout.starW / 2),
    layout.gridY + math.floor(layout.cardH / 2), 0)
  assertTrue(state.favorites[restockKey] == nil, "filled star click did not remove favorite")
  assertEqual(#TEST.executed, executedBeforeMouse, "unfavorite star click executed its command entry")

  TEST.saveData = "version=" .. TEST_CONFIG.expectedVersion
    .. "\nfavoriteOrder=recent\nfavorites=m:removed:disabled:any:-,c:182\nhistory="
  state.loaded = false
  onStarted()
  assertTrue(state.favorites["m:removed:disabled:any:-"] == nil,
    "unknown command favorite key survived the load boundary")
  assertTrue(state.favorites["c:182"] == true and state.favoriteOrder[1] == "c:182",
    "unknown command favorite cleanup removed a valid favorite")
  assertTrue(not contains(TEST.saveData, "m:removed:disabled:any:-"),
    "unknown command favorite key was not removed from SaveData")

  state.favorites = {}
  state.favoriteOrder = {}
  for _, entry in ipairs(allEntries) do
    state.favorites[entry.objectKey] = true
    state.favoriteOrder[#state.favoriteOrder + 1] = entry.objectKey
  end
  local saved, saveError = saveState()
  assertTrue(saved, "complete favorite catalog did not serialize: " .. tostring(saveError))
  assertTrue(#TEST.saveData < 65536, "complete 1162-entry favorite payload exceeds 64 KiB")
  assertTrue(contains(TEST.saveData, "favorites=" .. state.favoriteOrder[1]),
    "complete favorite payload did not preserve explicit order")
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

  local mantle = findObject("c:313")
  assertTrue(mantle ~= nil, "c313 regression object is missing")
  assertEqual(removalCommand(mantle), "remove c313",
    "c313 removal stopped using one native remove command")
  local mantleExecutedBefore = #TEST.executed
  assertTrue(queueEntry(mantle, 2), "c313 two-copy grant was rejected")
  onUpdate()
  TEST.frame = TEST.frame + 7
  onUpdate()
  assertEqual(#TEST.executed, mantleExecutedBefore + 2,
    "c313 two-copy grant did not execute exactly twice")
  assertEqual(TEST.executed[#TEST.executed - 1], "giveitem c313",
    "c313 first grant command differs")
  assertEqual(TEST.executed[#TEST.executed], "giveitem c313",
    "c313 second grant command differs")
  assertTrue(queueCommand(removalCommand(mantle), 1),
    "c313 native remove command was rejected")
  onUpdate()
  assertEqual(TEST.executed[#TEST.executed], "remove c313",
    "c313 removal added non-native effect cleanup")

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

local function renderedContainsFragment(needle)
  for _, value in ipairs(TEST.rendered) do
    if contains(value, needle) then return true end
  end
  return false
end

local function testDeviceHelpContract()
  onStarted()
  enterSearch("260")
  local helpEntries = visibleEntries()
  local entry = helpEntries[(state.page - 1) * 8 + state.selection]
  assertTrue(entry ~= nil, "device help setup has no selected entry")
  entry.desc = string.rep(IS_ZH and "用于验证多页说明。" or "Measured multipage details. ", 40)
  state.detailEntryId = nil
  state.detailPage = 1

  state.controlMode = "keyboard"
  state.pointerActive = false
  TEST.rendered = {}
  renderFrame()
  assertTrue(renderedContainsFragment(IS_ZH and "Enter给予" or "Enter: give"),
    "keyboard help omitted the real execute action")
  assertTrue(renderedContainsFragment(IS_ZH and "D翻说明" or "D: details"),
    "keyboard help omitted D details paging")
  assertTrue(renderedContainsFragment(IS_ZH and "F收藏" or "F: favorite"),
    "keyboard help omitted F favorite")
  assertTrue(not renderedContainsFragment(IS_ZH and "Esc退出" or "Esc: exit"),
    "ordinary keyboard entry help retained the obvious exit shortcut")
  assertTrue(not renderedContainsFragment(IS_ZH and "左键" or "LMB"),
    "keyboard help exposed mouse-only actions")

  state.controlMode = "mouse"
  state.pointerActive = true
  TEST.rendered = {}
  renderFrame()
  assertTrue(renderedContainsFragment(IS_ZH and "左键给予" or "LMB: give"),
    "mouse help omitted left-click execution")
  assertTrue(renderedContainsFragment(IS_ZH and "点击说明翻页" or "Click details: next"),
    "mouse help omitted clickable detail paging")
  assertTrue(renderedContainsFragment(IS_ZH and "点击星标收藏" or "Click star: favorite"),
    "mouse help omitted clickable favorite action")
  assertTrue(not renderedContainsFragment(IS_ZH and "Enter给予" or "Enter: give"),
    "mouse help exposed keyboard-only execution")

  state.search = "goto"
  state.page = 1
  state.selection = 1
  local manualEntries = visibleEntries()
  local manualEntry = manualEntries[1]
  assertTrue(manualEntry ~= nil and manualEntry.catalogAction == "manual",
    "manual multipage help setup did not select a parameter reference")
  manualEntry.desc = string.rep(IS_ZH and "用于验证参数参考翻页。" or
    "Measured parameter-reference paging. ", 40)
  state.detailEntryId = nil
  state.detailPage = 1

  state.controlMode = "mouse"
  state.pointerActive = true
  TEST.rendered = {}
  renderFrame()
  assertTrue(renderedContainsFragment(IS_ZH and "点击说明翻页" or "Click details: next"),
    "mouse parameter reference hid its real detail-paging action")
  assertTrue(not renderedContainsFragment(IS_ZH and "点击卡片查看" or "Click card: help"),
    "mouse multipage parameter reference retained the ambiguous card-help action")

  state.controlMode = "keyboard"
  state.pointerActive = false
  TEST.rendered = {}
  renderFrame()
  assertTrue(renderedContainsFragment(IS_ZH and "D翻说明" or "D: details"),
    "keyboard parameter reference hid its real detail-paging action")
  assertTrue(not renderedContainsFragment(IS_ZH and "Enter查看说明" or "Enter: help"),
    "keyboard multipage parameter reference retained the ambiguous help action")
  assertTrue(not renderedContainsFragment(IS_ZH and "Esc退出" or "Esc: exit"),
    "ordinary parameter-reference help retained the obvious exit shortcut")

  state.search = "260"
  state.page = 1
  state.selection = 1
  state.detailEntryId = nil
  state.detailPage = 1

  state.controlMode = "controller"
  state.pointerActive = false
  TEST.rendered = {}
  renderFrame()
  for _, expected in ipairs(IS_ZH
      and { "A给予", "Y翻页", "X收藏" }
      or { "A: give", "Y: page", "X: favorite" }) do
    assertTrue(renderedContainsFragment(expected),
      "controller help omitted action: " .. expected)
  end
  assertTrue(not renderedContainsFragment("A/Y/X/B"),
    "controller help degraded to ambiguous raw button letters")
  assertTrue(not renderedContainsFragment(IS_ZH and "左键" or "LMB"),
    "controller help exposed mouse-only actions")

  state.controlMode = "mouse"
  state.inputMode = "search"
  TEST.rendered = {}
  renderFrame()
  for _, expected in ipairs({ "Ctrl+A", "Enter", "Esc" }) do
    assertTrue(renderedContainsFragment(expected),
      "mouse-focused search omitted text shortcut: " .. expected)
  end
  state.inputMode = "command"
  TEST.rendered = {}
  renderFrame()
  for _, expected in ipairs({ "Ctrl+A", "Enter", "Esc" }) do
    assertTrue(renderedContainsFragment(expected),
      "mouse-focused command omitted text shortcut: " .. expected)
  end
end

local function testControllerDetailsPaging()
  onStarted()
  enterSearch("260")
  local entries = visibleEntries()
  local entry = entries[(state.page - 1) * 8 + state.selection]
  assertTrue(entry ~= nil, "controller details setup has no selected entry")
  entry.desc = string.rep(IS_ZH and "用于验证手柄翻阅多页说明。" or
    "Controller details paging must remain isolated. ", 50)
  state.detailEntryId = nil
  state.detailPage = 1
  state.controlMode = "controller"
  state.pointerActive = false
  state.controllerIndex = TEST_CONFIG.controllerIndex or 0
  renderFrame()
  local pageBefore = state.page
  local selectionBefore = state.selection
  local repeatBefore = state.repeatCount
  local executedBefore = #TEST.executed
  local favoriteBefore = state.favorites[entry.objectKey]
  pressButton(Controller.BUTTON_Y, state.controllerIndex)
  assertEqual(state.detailPage, 2, "Y did not advance exactly one details page")
  assertEqual(state.page, pageBefore, "Y changed the list page")
  assertEqual(state.selection, selectionBefore, "Y changed the selected entry")
  assertEqual(state.repeatCount, repeatBefore, "Y changed repeat count")
  assertEqual(#TEST.executed, executedBefore, "Y executed the entry")
  assertEqual(state.favorites[entry.objectKey], favoriteBefore, "Y changed favorite state")
  assertEqual(state.controlMode, "controller", "Y did not retain controller mode")
  assertEqual(state.controllerIndex, TEST_CONFIG.controllerIndex or 0,
    "Y lost the active controller index")

  entry.desc = "Short."
  state.detailEntryId = nil
  state.detailPage = 1
  renderFrame()
  pressButton(Controller.BUTTON_Y, state.controllerIndex)
  assertEqual(state.detailPage, 1, "Y changed a single-page description")

  entry.desc = string.rep("Long details. ", 50)
  state.detailEntryId = nil
  state.detailPage = 1
  state.sidebarFocus = true
  pressButton(Controller.BUTTON_Y, state.controllerIndex)
  assertEqual(state.detailPage, 1, "Y changed details while category focus was active")
  state.sidebarFocus = false
  state.inputMode = "search"
  pressButton(Controller.BUTTON_Y, state.controllerIndex)
  assertEqual(state.detailPage, 1, "Y changed details while search owned focus")
  state.inputMode = "command"
  pressButton(Controller.BUTTON_Y, state.controllerIndex)
  assertEqual(state.detailPage, 1, "Y changed details while command input owned focus")
end

local function assertCapturedTextInside(rect, record)
  local measured = utf8Length(record.text) * 6
  assertTrue(record.x >= rect.x - 1, "Toast text starts outside its background")
  assertTrue(record.x + measured <= rect.x + rect.width + 1,
    "Toast text ends outside its background: " .. record.text)
  assertTrue(record.y >= rect.y - 1 and record.y + 10 <= rect.y + rect.height + 1,
    "Toast text exceeds the background vertically")
  assertTrue(record.x >= -1 and record.x + measured <= (TEST_CONFIG.screenWidth or 1280) + 1,
    "Toast text exceeds the screen horizontally")
end

local function testToastLayoutContract()
  onStarted()
  state.open = false
  state.queue = nil
  local primary = IS_ZH and ("发生什么：" .. string.rep("保存失败", 30))
    or ("What happened: " .. string.rep("save failed ", 30))
  local action = IS_ZH and ("下一步：" .. string.rep("已恢复原设置", 30))
    or ("Next step: " .. string.rep("previous setting restored ", 30))
  TEST.rendered = {}
  TEST.renderRecords = {}
  TEST.spriteRecords = {}
  TEST.captureGeometry = true
  showToast(primary, "error", 180, action)
  drawToast(TEST_CONFIG.screenWidth or 1280, TEST_CONFIG.screenHeight or 720)
  assertEqual(#TEST.renderRecords, 2, "critical Toast did not use two semantic lines")
  assertTrue(contains(TEST.renderRecords[1].text, IS_ZH and "发生什么" or "What happened"),
    "critical Toast hid what happened")
  assertTrue(contains(TEST.renderRecords[2].text, IS_ZH and "下一步" or "Next step"),
    "critical Toast hid the next action")
  local background = TEST.spriteRecords[1]
  assertTrue(background ~= nil, "Toast background was not rendered")
  for _, record in ipairs(TEST.renderRecords) do assertCapturedTextInside(background, record) end

  TEST.rendered = {}
  TEST.renderRecords = {}
  TEST.spriteRecords = {}
  showToast(IS_ZH and "已加入常用精选" or "Added to Featured", "success", 75)
  assertEqual(state.toastFramesRemaining, 30,
    "short success Toast did not use the unified one-second duration")
  drawToast(TEST_CONFIG.screenWidth or 1280, TEST_CONFIG.screenHeight or 720)
  background = TEST.spriteRecords[1]
  assertTrue(background.width <= math.min(180, (TEST_CONFIG.screenWidth or 1280) * 0.5),
    "short success Toast did not shrink to its content")
  assertTrue(background.height <= 26,
    "reported font leading inflated a one-line Toast")
  for _, record in ipairs(TEST.renderRecords) do assertCapturedTextInside(background, record) end

  TEST.rendered = {}
  TEST.renderRecords = {}
  TEST.spriteRecords = {}
  state.toast = nil
  state.queue = {
    command = "thirdparty " .. string.rep("very-long-command-", 30),
    total = 99, done = 47, nextFrame = TEST.frame + 100,
  }
  drawToast(TEST_CONFIG.screenWidth or 1280, TEST_CONFIG.screenHeight or 720)
  assertEqual(#TEST.renderRecords, 2, "progress Toast did not split status and command")
  background = TEST.spriteRecords[1]
  for _, record in ipairs(TEST.renderRecords) do assertCapturedTextInside(background, record) end
  TEST.captureGeometry = false
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
  command_contracts = testCommandContracts,
  lifecycle_command_channel = testLifecycleCommandChannel,
  unknown_command_confirmation = testUnknownCommandConfirmation,
  controller = testController,
  cold_start_focus = testColdStartControllerFocus,
  official_immediate_grant = testOfficialImmediateGrant,
  queue_invariant = testQueueInvariant,
  command_feedback_duration = testCommandFeedbackDurations,
  measured_footer_stars = testMeasuredFooterAndStars,
  category_description_matrix = testCategoryDescriptionMatrix,
  font_fallback = testFontFallback,
  font_failure = testFontFailurePage,
  mcm_keybind = testMcmKeybind,
  eid_overlay = testEidOverlayIsolation,
  toast_restart = testToastRestartLifecycle,
  run_boundary_controller = testRunBoundaryControllerLifecycle,
  ctrl_a_isolation = testCtrlAIsolation,
  mcm_settings_254 = testMcmSettings254,
  official_objects = testOfficialObjects,
  all_entry_favorites = testAllEntryFavorites,
  command_editor = testCommandEditorAndHistory,
  editable_text_confirm_collision = testEditableTextConfirmCollision,
  pause_suspension = testPauseSuspension,
  assigned_controller_isolation = testAssignedControllerIsolation,
  closing_input_lease = testClosingInputLease,
  controller_repeat = testControllerRepeat,
  controller_paging = testControllerPaging,
  device_help_contract = testDeviceHelpContract,
  controller_details = testControllerDetailsPaging,
  toast_layout = testToastLayoutContract,
}

local scenario = scenarios[TEST_CONFIG.scenario]
assertTrue(type(scenario) == "function", "unknown scenario: " .. tostring(TEST_CONFIG.scenario))
scenario()
print("MOCK PASS " .. tostring(TEST_CONFIG.label or TEST_CONFIG.scenario))
