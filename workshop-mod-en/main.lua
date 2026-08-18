local ConsoleUI = RegisterMod("Console UI", 1)
local Catalog = include("scripts.data")
local CommandSpecs = include("scripts.command_specs")
local CommandCatalog = include("scripts.command_catalog")
local EnglishAliases = include("scripts.english_aliases")
local OfficialObjects = include("scripts.official_objects")

local VERSION = "2.5.4-en.11"
local REPEAT_DELAY_FRAMES = 7
local GRID_COLUMNS = 2
local ITEMS_PER_PAGE = 8
local CATEGORIES_PER_PAGE = 6
local MAX_HISTORY = 8
local MAX_SAVE_BYTES = 64 * 1024
local MAX_FAVORITES = 2048
local MAX_CONTROLLER_BUTTON = 31
local CONTROLLER_OPEN_HOLD_FRAMES = 30
local CONTROLLER_REMOVE_HOLD_FRAMES = 30
local DEFAULT_OPEN_KEY = Keyboard.KEY_F6

local OPEN_KEY_NAMES = {}
for name, value in pairs(Keyboard) do
  if type(name) == "string" and name:match("^KEY_") and type(value) == "number"
      and OPEN_KEY_NAMES[value] == nil then
    OPEN_KEY_NAMES[value] = name:sub(5)
  end
end

local RESERVED_OPEN_KEYS = {}
local function reserveOpenKey(key)
  if type(key) == "number" then RESERVED_OPEN_KEYS[key] = true end
end
for _, key in ipairs({
    Keyboard.KEY_ESCAPE, Keyboard.KEY_ENTER, Keyboard.KEY_BACKSPACE,
    Keyboard.KEY_UP, Keyboard.KEY_DOWN, Keyboard.KEY_LEFT, Keyboard.KEY_RIGHT,
    Keyboard.KEY_PAGE_UP, Keyboard.KEY_PAGE_DOWN, Keyboard.KEY_SLASH,
    Keyboard.KEY_C, Keyboard.KEY_D, Keyboard.KEY_F, Keyboard.KEY_R,
    Keyboard.KEY_MINUS, Keyboard.KEY_EQUAL, Keyboard.KEY_KP_ADD,
  }) do reserveOpenKey(key) end

local function isValidOpenKey(key)
  key = tonumber(key)
  return key ~= nil and key == math.floor(key)
    and OPEN_KEY_NAMES[key] ~= nil and not RESERVED_OPEN_KEYS[key]
end

local function openKeyName(key)
  return OPEN_KEY_NAMES[tonumber(key)] or "F6"
end

local function controllerButton(name, fallback)
  return (type(Controller) == "table" and Controller[name]) or fallback
end

local function normalizeControllerButton(value)
  value = tonumber(value)
  if value == nil or value ~= math.floor(value)
      or value < 0 or value > MAX_CONTROLLER_BUTTON then return nil end
  return value
end

local CONTROLLER_DPAD_LEFT = controllerButton("DPAD_LEFT", 0)
local CONTROLLER_DPAD_RIGHT = controllerButton("DPAD_RIGHT", 1)
local CONTROLLER_DPAD_UP = controllerButton("DPAD_UP", 2)
local CONTROLLER_DPAD_DOWN = controllerButton("DPAD_DOWN", 3)
local CONTROLLER_CONFIRM = controllerButton("BUTTON_A", 4)
local CONTROLLER_BACK = controllerButton("BUTTON_B", 5)
local CONTROLLER_FAVORITE = controllerButton("BUTTON_X", 6)
local CONTROLLER_OPEN_BUTTON = controllerButton("STICK_LEFT", 10)
local CONTROLLER_REPEAT_DECREASE = controllerButton("BUMPER_LEFT")
local CONTROLLER_REPEAT_INCREASE = controllerButton("BUMPER_RIGHT")
local CONTROLLER_PAGE_PREVIOUS = controllerButton("TRIGGER_LEFT")
local CONTROLLER_PAGE_NEXT = controllerButton("TRIGGER_RIGHT")

local COLORS = {
  overlay = Color(0.025, 0.018, 0.025, 0.99, 0, 0, 0),
  panel = Color(0.075, 0.047, 0.066, 1.00, 0, 0, 0),
  sidebar = Color(0.105, 0.061, 0.087, 1.00, 0, 0, 0),
  card = Color(0.145, 0.083, 0.105, 1.00, 0, 0, 0),
  cardHover = Color(0.245, 0.115, 0.145, 1.00, 0, 0, 0),
  selected = Color(0.425, 0.160, 0.220, 1.00, 0, 0, 0),
  accent = Color(0.930, 0.300, 0.390, 1.00, 0, 0, 0),
  gold = Color(0.720, 0.450, 0.160, 1.00, 0, 0, 0),
  favoriteOff = Color(0.690, 0.580, 0.620, 1.00, 0, 0, 0),
  disabled = Color(0.255, 0.225, 0.235, 1.00, 0, 0, 0),
  shadow = Color(0.000, 0.000, 0.000, 0.45, 0, 0, 0),
}

local TEXT = {
  main = KColor(0.98, 0.95, 0.91, 1.00),
  muted = KColor(0.69, 0.58, 0.62, 1.00),
  accent = KColor(1.00, 0.42, 0.50, 1.00),
  gold = KColor(1.00, 0.72, 0.31, 1.00),
  green = KColor(0.42, 0.94, 0.64, 1.00),
  warning = KColor(1.00, 0.69, 0.28, 1.00),
}

local function debugLog(message)
  pcall(function() Isaac.DebugString("[Console UI] " .. tostring(message)) end)
end

-- The English edition always uses its bundled font pair. This keeps the
-- measured UI independent of the game's selected language and resource pack.
local IS_REPENTANCE_PLUS = REPENTANCE_PLUS == true
function ConsoleUI.controllerAction(name)
  local value = type(ButtonAction) == "table" and ButtonAction[name] or nil
  return type(value) == "number" and value or nil
end

local CONTROLLER_ACTION_CONFIRM = ConsoleUI.controllerAction("ACTION_MENUCONFIRM")
local CONTROLLER_ACTION_BACK = ConsoleUI.controllerAction("ACTION_MENUBACK")
local CONTROLLER_ACTION_FAVORITE = ConsoleUI.controllerAction("ACTION_MENUTAB")
local CONTROLLER_ACTION_LEFT = ConsoleUI.controllerAction("ACTION_MENULEFT")
local CONTROLLER_ACTION_RIGHT = ConsoleUI.controllerAction("ACTION_MENURIGHT")
local CONTROLLER_ACTION_UP = ConsoleUI.controllerAction("ACTION_MENUUP")
local CONTROLLER_ACTION_DOWN = ConsoleUI.controllerAction("ACTION_MENUDOWN")
local CONTROLLER_ACTION_RESTART = ConsoleUI.controllerAction("ACTION_RESTART")
-- Raw values are isolated as verified compatibility data. Logical actions
-- take priority, so runtimes with complete ButtonAction support need no
-- edition-specific branch. Repentance+ gameplay can omit MENUTAB; its
-- verified Xbox-controller X fallback is raw 4.
local CONTROLLER_INPUT_COMPATIBILITY
if IS_REPENTANCE_PLUS then
  CONTROLLER_INPUT_COMPATIBILITY = { favorite = 4 }
else
  CONTROLLER_INPUT_COMPATIBILITY = {
    confirm = CONTROLLER_CONFIRM,
    back = CONTROLLER_BACK,
    favorite = CONTROLLER_FAVORITE,
  }
end
CONTROLLER_INPUT_COMPATIBILITY.repeatDecreaseAction = ConsoleUI.controllerAction("ACTION_MENULB")
CONTROLLER_INPUT_COMPATIBILITY.repeatIncreaseAction = ConsoleUI.controllerAction("ACTION_MENURB")
CONTROLLER_INPUT_COMPATIBILITY.pagePreviousAction = ConsoleUI.controllerAction("ACTION_MENULT")
CONTROLLER_INPUT_COMPATIBILITY.pageNextAction = ConsoleUI.controllerAction("ACTION_MENURT")
CONTROLLER_INPUT_COMPATIBILITY.triggerPressThreshold = 0.55
CONTROLLER_INPUT_COMPATIBILITY.triggerReleaseThreshold = 0.35

local fontRoot = "resources/font/"
local fontKind = "bundled Fusion Pixel"
local font10, font12 = Font(), Font()
local fontLoaded = false
local fontLoadError = "no font candidates were attempted"
local attemptedRoots, loadErrors = {}, {}

local function validateFontPair(candidate10, candidate12)
  local ok, loaded10, loaded12, width10, width12 = pcall(function()
    return candidate10:IsLoaded(), candidate12:IsLoaded(),
      candidate10:GetStringWidthUTF8("CONSOLE UI ABC 123"),
      candidate12:GetStringWidthUTF8("CONSOLE UI ABC 123")
  end)
  if not ok then return false, tostring(loaded10) end
  width10, width12 = tonumber(width10) or 0, tonumber(width12) or 0
  if loaded10 ~= true then return false, "10px IsLoaded=false" end
  if loaded12 ~= true then return false, "12px IsLoaded=false" end
  if width10 <= 0 then return false, "10px UTF8 width=" .. tostring(width10) end
  if width12 <= 0 then return false, "12px UTF8 width=" .. tostring(width12) end
  return true, nil, width10, width12
end

local function tryFontPair(root, file10, file12, customFont, kind)
  attemptedRoots[#attemptedRoots + 1] = root
  local candidate10, candidate12 = Font(), Font()
  local loadOk, loadError = pcall(function()
    if customFont then
      candidate10:Load(root .. file10, "")
      candidate12:Load(root .. file12, "")
    else
      candidate10:Load(root .. file10)
      candidate12:Load(root .. file12)
    end
  end)
  if not loadOk then
    loadErrors[#loadErrors + 1] = root .. ": " .. tostring(loadError)
    return false
  end
  local valid, validationError, width10, width12 = validateFontPair(candidate10, candidate12)
  if not valid then
    loadErrors[#loadErrors + 1] = root .. ": " .. tostring(validationError)
    return false
  end
  font10, font12 = candidate10, candidate12
  fontRoot, fontKind = root, kind
  fontLoaded, fontLoadError = true, nil
  debugLog("font accepted: " .. kind .. "; root=" .. root
    .. "; widths=" .. tostring(width10) .. "/" .. tostring(width12))
  return true
end

local function normalizePath(value)
  return tostring(value or ""):gsub("\\", "/")
end

local function modRootFromRequireError(requireError)
  if type(requireError) ~= "string" then return "" end
  for candidate in requireError:gmatch("no file '([^']-%.lua)'") do
    local path = normalizePath(candidate)
    if path:sub(-5) == "/.lua" then
      local root = path:sub(1, -5)
      if root:lower():match("/mods/[^/]+/$") then return root end
    end
  end
  return ""
end

local function getCurrentModPath()
  if debug and debug.getinfo then
    local info = debug.getinfo(getCurrentModPath)
    local source = info and info.source or ""
    if source:sub(1, 1) == "@" then source = source:sub(2) end
    source = normalizePath(source)
    local root = source:match("^(.*[/])") or ""
    if root ~= "" then return root end
  end
  local _, requireError = pcall(require, "")
  return modRootFromRequireError(requireError)
end

local bundledRoots, seenRoots = {}, {}
local function addBundledRoot(root)
  root = normalizePath(root)
  if root ~= "" and not seenRoots[root] then
    bundledRoots[#bundledRoots + 1] = root
    seenRoots[root] = true
  end
end
local discoveredRoot = getCurrentModPath()
if discoveredRoot ~= "" then addBundledRoot(discoveredRoot .. "resources/font/") end
addBundledRoot("../mods/console_ui_workshop_3779128726/resources/font/")
addBundledRoot("../mods/console_ui_workshop/resources/font/")
addBundledRoot("resources/font/")
for _, candidateRoot in ipairs(bundledRoots) do
  if tryFontPair(candidateRoot,
    "fusion/10.fnt", "fusion/12.fnt", true,
    "bundled Fusion Pixel") then break end
end

if not fontLoaded then fontLoadError = table.concat(loadErrors, " | ") end
debugLog("v" .. VERSION .. "; runtime=" .. (IS_REPENTANCE_PLUS and "Repentance+" or "Repentance")
  .. "; font=" .. fontKind .. "; root=" .. fontRoot)
debugLog("font roots tried: " .. table.concat(attemptedRoots, " | "))
if not fontLoaded then debugLog("font check FAILED: " .. tostring(fontLoadError)) end
local pixel = Sprite()
pixel:Load("gfx/ui/isaac_console_pixel.anm2", true)
pixel:Play("Idle", true)

local state = {
  open = false,
  categoryIndex = 1,
  categoryPage = 1,
  selection = 1,
  page = 1,
  sidebarFocus = false,
  initialMenuFocusResolved = false,
  repeatCount = 1,
  favorites = {},
  favoriteOrder = {},
  favoriteOrderNeedsCatalogMigration = false,
  history = {},
  search = "",
  inputMode = nil,
  searchSelectAll = false,
  manualCommand = "giveitem c182",
  commandSelectAll = false,
  commandHistoryIndex = nil,
  commandHistoryDraft = nil,
  commandHistoryDraftRepeat = nil,
  mouseDown = false,
  rightMouseDown = false,
  hudWasVisible = true,
  queue = nil,
  lifecycleRequest = nil,
  lifecycleReceipt = nil,
  unknownCommandConfirmation = nil,
  toast = nil,
  toastFramesRemaining = 0,
  lastGameFrame = nil,
  startupHintShown = false,
  startupHintEnabled = true,
  closeAfterRegularCommand = true,
  loaded = false,
  layoutSignature = nil,
  detailEntryId = nil,
  detailPage = 1,
  controllerOpenHold = 0,
  controllerOpenLatched = false,
  controllerOpenIndex = nil,
  controllerIndex = nil,
  controllerConfirmHold = 0,
  controllerConfirmCommand = nil,
  controllerConfirmRemoveCommand = nil,
  controllerConfirmRemoveMessage = nil,
  controllerConfirmRepeat = 1,
  controllerConfirmRepeatMax = nil,
  controllerConfirmIndex = nil,
  controllerConfirmSource = nil,
  controllerConfirmValue = nil,
  pointerActive = false,
  lastMouseX = nil,
  lastMouseY = nil,
  controlMode = "keyboard",
  openKey = DEFAULT_OPEN_KEY,
  controllerFavoriteButton = nil,
  eidSuppressed = false,
  eidWasHidden = nil,
  nativePauseSuspended = false,
  keyboardEnterPressed = false,
  inputLease = nil,
  controllerShoulderLatch = {},
}

local Presentation = {
  toastDurations = { success = 30, default = 60 },
  toastColors = {
    info = TEXT.main,
    success = TEXT.green,
    warning = TEXT.warning,
    error = TEXT.accent,
  },
}
local lifecycleDispatcher = { registered = false }

function lifecycleDispatcher.disarm()
  if not lifecycleDispatcher.registered then return end
  ConsoleUI:RemoveCallback(ModCallbacks.MC_POST_RENDER, lifecycleDispatcher.dispatch)
  lifecycleDispatcher.registered = false
end
function lifecycleDispatcher.arm()
  if lifecycleDispatcher.registered then return end
  assert(type(lifecycleDispatcher.dispatch) == "function", "lifecycle dispatcher is not initialized")
  ConsoleUI:AddCallback(ModCallbacks.MC_POST_RENDER, lifecycleDispatcher.dispatch)
  lifecycleDispatcher.registered = true
end

local function suppressEidOverlay()
  if type(EID) ~= "table" or type(EID.isHidden) ~= "boolean" then return end
  if not state.eidSuppressed then
    state.eidSuppressed = true
    state.eidWasHidden = EID.isHidden
  end
  EID.isHidden = true
end

local function restoreEidOverlay()
  if not state.eidSuppressed then return end
  local wasHidden = state.eidWasHidden == true
  state.eidSuppressed = false
  state.eidWasHidden = nil
  if type(EID) == "table" and type(EID.isHidden) == "boolean" then
    EID.isHidden = wasHidden
  end
end
local function setMenuOpen(open)
  open = open == true
  if open == state.open then
    if open then suppressEidOverlay() else restoreEidOverlay() end
    return
  end
  local hudOk, hud = pcall(function() return Game():GetHUD() end)
  if open then
    suppressEidOverlay()
    if hudOk and hud then
      local visibleOk, visible = pcall(function() return hud:IsVisible() end)
      state.hudWasVisible = not visibleOk or visible ~= false
      pcall(function() hud:SetVisible(false) end)
    end
  else
    restoreEidOverlay()
    if hudOk and hud then
      pcall(function() hud:SetVisible(state.hudWasVisible ~= false) end)
    end
  end
  state.open = open
  if not open then
    state.inputMode = nil
    state.searchSelectAll = false
    state.commandSelectAll = false
    state.commandHistoryIndex = nil
    state.commandHistoryDraft = nil
    state.commandHistoryDraftRepeat = nil
    state.unknownCommandConfirmation = nil
    state.nativePauseSuspended = false
    state.controllerConfirmHold = 0
    state.controllerConfirmCommand = nil
    state.controllerConfirmRemoveCommand = nil
    state.controllerConfirmRemoveMessage = nil
    state.controllerConfirmRepeat = 1
    state.controllerConfirmRepeatMax = nil
    state.controllerConfirmIndex = nil
    state.controllerConfirmSource = nil
    state.controllerConfirmValue = nil
    state.controllerShoulderLatch = {}
  end
end

for _, category in ipairs(CommandCatalog.categories) do
  Catalog.categories[#Catalog.categories + 1] = category
end
for _, command in ipairs(CommandCatalog.commands) do
  Catalog.commands[#Catalog.commands + 1] = command
end

local categoryById = {}
for index, category in ipairs(Catalog.categories) do
  categoryById[category.id] = { value = category, index = index }
end

local allEntries = {}
local completeEntries = {}
local completeCatalogLoaded = false
local knownItemIds = {}
local FavoriteModel = { catalogReady = false, entryByKey = {} }
local stageCommandWhitelists = { normal = {}, greed = {} }
local officialGrantCache = {}
local sharedItemConfig = nil
local sharedItemConfigResolved = false

-- These are the resource deltas exposed by the game's ItemConfig API. They
-- identify pickup-time grants without maintaining a guessed collectible list.
local OFFICIAL_GRANT_FIELDS = {
  "AddCoins", "AddKeys", "AddBombs", "AddHearts", "AddMaxHearts",
  "AddSoulHearts", "AddBlackHearts",
}

local function getSharedItemConfig()
  if not sharedItemConfigResolved then
    sharedItemConfigResolved = true
    local ok, itemConfig = pcall(Isaac.GetItemConfig)
    if ok then sharedItemConfig = itemConfig end
  end
  return sharedItemConfig
end

local function objectKey(objectType, id)
  return tostring(objectType or "") .. ":" .. tostring(id or "")
end

function FavoriteModel.canonicalCommandText(value)
  return tostring(value or ""):lower():match("^%s*(.-)%s*$"):gsub("%s+", " ")
end

function FavoriteModel.encodeFavoriteSegment(value)
  return (tostring(value or ""):gsub("([^%w._%-])", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

function FavoriteModel.commandFavoriteKey(command, spec)
  local action = command.catalogAction
  assert(action == "execute" or action == "manual" or action == "disabled",
    "invalid favorite command action: " .. tostring(action))
  local mode = command.cat == "stage"
    and (command.stageMode == "greed" and "greed" or "normal") or "any"
  local commandText = action == "execute" and FavoriteModel.canonicalCommandText(command.cmd) or "-"
  return table.concat({
    "m", FavoriteModel.encodeFavoriteSegment(spec.id), action, mode, FavoriteModel.encodeFavoriteSegment(commandText),
  }, ":")
end

function FavoriteModel.registerEntry(entry)
  local key = assert(entry and entry.objectKey, "favorite entry key is missing")
  assert(not FavoriteModel.entryByKey[key], "duplicate favorite entry key: " .. key)
  FavoriteModel.entryByKey[key] = entry
end

local function normalizeSearchText(value)
  value = tostring(value or ""):lower()
  local spaced = value:gsub("[^%w]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return spaced .. " " .. spaced:gsub("%s+", "")
end

local function buildSearchText(entry)
  local parts = {
    entry.name or "",
    entry.en or "",
    entry.cmd or "",
    tostring(entry.id or ""),
  }
  local itemId = tonumber(entry.id)
  if entry.kind == "item" and itemId and entry.objectType == "c" then
    parts[#parts + 1] = EnglishAliases[itemId] or ""
  end
  parts[#parts + 1] = normalizeSearchText(entry.name)
  parts[#parts + 1] = normalizeSearchText(entry.en)
  return table.concat(parts, " "):lower()
end

for _, item in ipairs(Catalog.items) do
  item.cmd = "giveitem c" .. tostring(item.id)
  item.kind = "item"
  item.objectType = "c"
  item.objectKey = objectKey(item.objectType, item.id)
  item.canFavorite = true
  item.canRemove = true
  item.repeatMax = 99
  item.searchText = buildSearchText(item)
  FavoriteModel.registerEntry(item)
  knownItemIds[item.id] = true
  allEntries[#allEntries + 1] = item
end
for _, command in ipairs(Catalog.commands) do
  local commandVerb = tostring(command.cmd or ""):lower():match("^(%S+)")
  local spec = CommandSpecs.byId[command.commandId] or CommandSpecs.byVerb[commandVerb]
  assert(spec, "missing command contract for catalog entry: " .. tostring(command.commandId or command.cmd))
  command.commandSpec = spec
  command.catalogAction = command.catalogAction
    or ((spec.mode == "output" or spec.mode == "disabled") and "disabled" or "execute")
  command.cmd = command.cmd or spec.syntax
  command.commandTemplate = spec.template
  command.displayCommand = spec.syntax
  command.kind = "command"
  command.objectKey = FavoriteModel.commandFavoriteKey(command, spec)
  command.canFavorite = true
  command.canRemove = tostring(command.cmd or ""):match("^giveitem%s+c%d+%s*$") ~= nil
  command.repeatMax = tonumber(command.repeatMax) or spec.repeatMax or 1
  command.searchText = buildSearchText(command)
  FavoriteModel.registerEntry(command)
  if command.cat == "stage" then
    local mode = command.stageMode == "greed" and "greed" or "normal"
    stageCommandWhitelists[mode][tostring(command.cmd or ""):lower()] = true
  end
  allEntries[#allEntries + 1] = command
end

local function cleanConfigText(value, fallback)
  value = tostring(value or "")
  if value == "" or value:sub(1, 1) == "#" then return fallback end
  value = value:gsub("#", " · "):gsub("^%s+", ""):gsub("%s+$", "")
  if value == "" then return fallback end
  return value
end

local EID_ICON_WORDS = {
  Heart = "Red Heart", SoulHeart = "Soul Heart", BlackHeart = "Black Heart", EternalHeart = "Eternal Heart",
  BoneHeart = "Bone Heart", RottenHeart = "Rotten Heart", Coin = "Coin", Bomb = "Bomb", Key = "Key",
  Damage = "Damage", Tears = "Tears", Range = "Range", Speed = "Speed", Shotspeed = "Shot Speed",
  Luck = "Luck", Flight = "Flight", Charge = "Charge", Battery = "Battery", Shop = "Shop",
  TreasureRoom = "Treasure Room", DevilRoom = "Devil Room", AngelRoom = "Angel Room", SecretRoom = "Secret Room",
  Card = "Card", Rune = "Rune", Pill = "Pill", Boss = "Boss", Fear = "Fear",
  Poison = "Poison", Burning = "Burning", Slow = "Slow", Charm = "Charm", Bleeding = "Bleeding",
  HealingRed = "Red-heart healing", UnknownHeart = "Random heart",
}

local function cleanEidDescription(value)
  local text = tostring(value or "")
  text = text:gsub("{{([^{}]+)}}", function(token)
    local key = token:match("^([^|]+)") or token
    key = key:gsub("^Color.-$", ""):gsub("^CR$", "")
    if key == "" then return "" end
    return EID_ICON_WORDS[key] or ""
  end)
  text = text:gsub("#", " / ")
  text = text:gsub("!!!", "Warning: ")
  text = text:gsub("%s*/%s*", " / ")
  text = text:gsub("/%s*/+", "/")
  text = text:gsub("%s+", " ")
  text = text:gsub("^%s*/?%s*", ""):gsub("%s*/?%s*$", "")
  return text
end

local function getEidCollectible(id)
  local ok, name, description = pcall(function()
    if type(EID) ~= "table" then return nil, nil end
    local descriptions = EID.descriptions and EID.descriptions.en_us
    local entry = descriptions and descriptions.collectibles and descriptions.collectibles[id]
    local itemNames = EID.ItemNames and EID.ItemNames.en_us
    local localizedName = itemNames and itemNames["5.100." .. tostring(id)]
    if type(entry) == "table" then
      localizedName = localizedName or entry[2]
      return localizedName, entry[3]
    end
    return localizedName, nil
  end)
  if not ok then return nil, nil end
  name = tostring(name or "")
  description = cleanEidDescription(description)
  if name == "" then name = nil end
  if description == "" then description = nil end
  return name, description
end

local function getEidObject(objectType, id)
  local ok, name, description = pcall(function()
    if type(EID) ~= "table" then return nil, nil end
    local descriptions = EID.descriptions and EID.descriptions.en_us
    if type(descriptions) ~= "table" then return nil, nil end
    local source, index
    if objectType == "t" then
      source, index = descriptions.trinkets, id
    elseif objectType == "k" then
      source, index = descriptions.cards, id
    elseif objectType == "p" then
      source, index = descriptions.pills, id + 1
    else
      return nil, nil
    end
    local entry = type(source) == "table" and source[index] or nil
    if type(entry) ~= "table" or tonumber(entry[1]) ~= id then return nil, nil end
    return entry[2], entry[3]
  end)
  if not ok then return nil, nil end
  name = tostring(name or "")
  description = cleanEidDescription(description)
  if name == "" then name = nil end
  if description == "" then description = nil end
  return name, description
end

local function getOfficialConfig(itemConfig, objectType, id)
  if objectType == "t" then return itemConfig:GetTrinket(id) end
  if objectType == "k" then return itemConfig:GetCard(id) end
  if objectType == "p" then return itemConfig:GetPillEffect(id) end
  return nil
end

local function loadCompleteCatalog()
  if completeCatalogLoaded then return end
  completeCatalogLoaded = true
  for _, item in ipairs(Catalog.items) do completeEntries[#completeEntries + 1] = item end

  local itemConfig = getSharedItemConfig()
  if not itemConfig then
    debugLog("complete catalog unavailable")
    return
  end
  local maxId = (CollectibleType and CollectibleType.NUM_COLLECTIBLES or 800) - 1
  local eidNames, eidDescriptions = 0, 0
  for id = 1, maxId do
    if not knownItemIds[id] then
      local configOk, config = pcall(function() return itemConfig:GetCollectible(id) end)
      if configOk and config then
        local quality = tonumber(config.Quality) or 0
        local eidName, eidDescription = getEidCollectible(id)
        local gameName = cleanConfigText(config.Name, "")
        local name = eidName or (gameName ~= "" and gameName or ("Item " .. id))
        local description = eidDescription or cleanConfigText(config.Description, "In-game collectible, ID " .. id)
        if eidName then eidNames = eidNames + 1 end
        if eidDescription then eidDescriptions = eidDescriptions + 1 end
        local entry = {
          id = id,
          cat = "all_items",
          name = name,
          en = gameName ~= "" and gameName or name,
          tier = quality >= 4 and "S" or (quality >= 3 and "A" or "B"),
          quality = quality,
          icon = "ITM",
          desc = description,
          cmd = "giveitem c" .. id,
          kind = "item",
          objectType = "c",
          objectKey = objectKey("c", id),
          canFavorite = true,
          canRemove = true,
          repeatMax = 99,
          dynamic = true,
          descSource = eidDescription and "EID" or "game",
        }
        entry.searchText = buildSearchText(entry)
        FavoriteModel.registerEntry(entry)
        completeEntries[#completeEntries + 1] = entry
        allEntries[#allEntries + 1] = entry
      end
    end
  end

  local objectSpecs = {
    {
      objectType = "t", cat = "trinkets", names = OfficialObjects.trinkets,
      minimum = 1, maximum = ((TrinketType and TrinketType.NUM_TRINKETS) or 190) - 1,
      icon = "TR", fallback = "Official trinket, ID ", canRemove = true,
    },
    {
      objectType = "k", cat = "cards", names = OfficialObjects.cards,
      minimum = 1, maximum = ((Card and Card.NUM_CARDS) or 98) - 1,
      icon = "CRD", fallback = "Official card or rune, ID ", canRemove = false,
    },
    {
      objectType = "p", cat = "pills", names = OfficialObjects.pills,
      minimum = 0, maximum = ((PillEffect and PillEffect.NUM_PILL_EFFECTS) or 50) - 1,
      icon = "PIL", fallback = "Official pill effect, ID ", canRemove = false,
    },
  }
  local objectCounts = { t = 0, k = 0, p = 0 }
  local eidObjectDescriptions = 0
  for _, spec in ipairs(objectSpecs) do
    for id = spec.minimum, spec.maximum do
      local static = spec.names[id]
      if static then
        local configOk, config = pcall(function()
          return getOfficialConfig(itemConfig, spec.objectType, id)
        end)
        if configOk and config then
          local descriptionOk, configDescription = pcall(function() return config.Description end)
          local _, eidDescription = getEidObject(spec.objectType, id)
          if eidDescription then eidObjectDescriptions = eidObjectDescriptions + 1 end
          local englishName = type(static) == "table"
            and (static.en or static.name)
            or tostring(static)
          local entry = {
            id = id,
            cat = spec.cat,
            name = englishName,
            en = englishName,
            tier = "B",
            icon = spec.icon,
            desc = eidDescription or cleanConfigText(descriptionOk and configDescription or nil, spec.fallback .. id),
            cmd = "giveitem " .. spec.objectType .. id,
            kind = "item",
            objectType = spec.objectType,
            objectKey = objectKey(spec.objectType, id),
            canFavorite = true,
            canRemove = spec.canRemove,
            repeatMax = 1,
            dynamic = true,
            descSource = eidDescription and "EID" or "game",
          }
          entry.searchText = buildSearchText(entry)
          FavoriteModel.registerEntry(entry)
          allEntries[#allEntries + 1] = entry
          objectCounts[spec.objectType] = objectCounts[spec.objectType] + 1
        end
      end
    end
  end
  table.sort(completeEntries, function(a, b)
    if (a.hot or 0) ~= (b.hot or 0) then return (a.hot or 0) > (b.hot or 0) end
    local tierRank = { S = 3, A = 2, B = 1 }
    if (tierRank[a.tier] or 0) ~= (tierRank[b.tier] or 0) then
      return (tierRank[a.tier] or 0) > (tierRank[b.tier] or 0)
    end
    return (a.id or 0) < (b.id or 0)
  end)
  FavoriteModel.catalogReady = true
  debugLog("complete catalog loaded: " .. #completeEntries .. " collectibles; EID en_us names="
    .. eidNames .. " descriptions=" .. eidDescriptions
    .. "; trinkets=" .. objectCounts.t .. " cards=" .. objectCounts.k
    .. " pills=" .. objectCounts.p .. " object descriptions=" .. eidObjectDescriptions)
end

local function clamp(value, minimum, maximum)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function utf8sub(value, maxChars)
  local bytes = #value
  local index = 1
  local chars = 0
  while index <= bytes and chars < maxChars do
    local byte = value:byte(index)
    if byte < 0x80 then
      index = index + 1
    elseif byte < 0xE0 then
      index = index + 2
    elseif byte < 0xF0 then
      index = index + 3
    else
      index = index + 4
    end
    chars = chars + 1
  end
  return value:sub(1, index - 1)
end

local function encode(value)
  return tostring(value):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\n", "%%0A")
end

local function decode(value)
  return tostring(value):gsub("%%0A", "\n"):gsub("%%7C", "|"):gsub("%%25", "%%")
end

local FAVORITE_ID_LIMITS = {
  c = { 1, 732 }, t = { 1, 189 }, k = { 1, 97 }, p = { 0, 49 },
}

local function validFavoriteKey(value)
  local text = tostring(value or "")
  local code, idText = text:match("^([ctkp]):(%d+)$")
  local limits = code and FAVORITE_ID_LIMITS[code] or nil
  local id = tonumber(idText)
  if limits and id and id >= limits[1] and id <= limits[2] then
    return objectKey(code, id), code, id
  end
  local entry = FavoriteModel.entryByKey[text]
  if entry and entry.kind == "command" then return text, "m" end
  return nil
end

function FavoriteModel.orderIndex(key)
  for index, value in ipairs(state.favoriteOrder) do
    if value == key then return index end
  end
  return nil
end

function FavoriteModel.orderedKeys()
  assert(#state.favoriteOrder <= MAX_FAVORITES, "favorite order exceeds the configured limit")
  local result, seen = {}, {}
  for _, key in ipairs(state.favoriteOrder) do
    local normalized = validFavoriteKey(key)
    assert(normalized == key, "favorite order contains an invalid key: " .. tostring(key))
    assert(state.favorites[key] == true, "favorite order contains a disabled key: " .. key)
    assert(not seen[key], "favorite order contains a duplicate key: " .. key)
    seen[key] = true
    result[#result + 1] = key
  end
  for key, enabled in pairs(state.favorites) do
    if enabled then
      assert(validFavoriteKey(key) == key, "favorite state contains an invalid key: " .. tostring(key))
      assert(seen[key], "favorite state is missing from recent order: " .. key)
    end
  end
  return result
end

local function debugStateStats(label, rawBytes)
  pcall(function()
    local favoriteCount = 0
    for _, enabled in pairs(state.favorites) do
      if enabled then favoriteCount = favoriteCount + 1 end
    end
    local memoryText = "unavailable"
    local memoryOk, memoryKb = pcall(function() return collectgarbage("count") end)
    if memoryOk and tonumber(memoryKb) then memoryText = string.format("%.1fKB", memoryKb) end
    debugLog(label .. "; bytes=" .. tostring(rawBytes or 0)
      .. " favorites=" .. favoriteCount .. " history=" .. #state.history
      .. " lua=" .. memoryText)
  end)
end

local function saveState()
  local favoriteKeys = FavoriteModel.orderedKeys()

  local history = {}
  for index = 1, math.min(#state.history, MAX_HISTORY) do
    history[#history + 1] = encode(state.history[index])
  end
  local payload =
    "version=" .. VERSION .. "\n"
      .. "openKey=" .. tostring(state.openKey or DEFAULT_OPEN_KEY) .. "\n"
      .. "startupHintEnabled=" .. (state.startupHintEnabled == false and "0" or "1") .. "\n"
      .. "closeAfterRegularCommand=" .. (state.closeAfterRegularCommand == false and "0" or "1") .. "\n"
      .. "controllerFavoriteButton=" .. tostring(state.controllerFavoriteButton or "auto") .. "\n"
      .. (state.favoriteOrderNeedsCatalogMigration and "" or "favoriteOrder=recent\n")
      .. "favorites=" .. table.concat(favoriteKeys, ",") .. "\n"
      .. "history=" .. table.concat(history, "|")
  if #payload > MAX_SAVE_BYTES then
    debugLog("state save rejected: " .. #payload .. " bytes")
    return false, "Save data is unexpectedly large"
  end
  local ok, err = pcall(function() ConsoleUI:SaveData(payload) end)
  if not ok then
    debugLog("state save failed: " .. tostring(err))
    return false, tostring(err)
  end
  debugStateStats("state saved", #payload)
  return true
end

local function loadState()
  if state.loaded then return end
  state.loaded = true
  state.favorites = {}
  state.favoriteOrder = {}
  state.favoriteOrderNeedsCatalogMigration = false
  state.history = {}
  state.openKey = DEFAULT_OPEN_KEY
  state.startupHintEnabled = true
  state.closeAfterRegularCommand = true
  state.controllerFavoriteButton = nil

  local hasDataOk, hasData = pcall(function() return ConsoleUI:HasData() end)
  if not hasDataOk or not hasData then
    if not hasDataOk then debugLog("state availability check failed: " .. tostring(hasData)) end
    debugStateStats("state empty", 0)
    return
  end

  local loadOk, raw = pcall(function() return ConsoleUI:LoadData() end)
  if not loadOk or type(raw) ~= "string" then
    debugLog("state load failed: " .. tostring(raw))
    debugStateStats("state load failed", 0)
    return
  end

  local rawBytes = #raw
  local migrated = rawBytes > MAX_SAVE_BYTES
  local parseRaw = migrated and raw:sub(1, MAX_SAVE_BYTES) or raw
  local savedOpenKey = tonumber(parseRaw:match("openKey=(%-?%d+)"))
  if savedOpenKey ~= nil then
    if isValidOpenKey(savedOpenKey) then
      state.openKey = savedOpenKey
    else
      migrated = true
    end
  end
  local savedStartupHint = parseRaw:match("startupHintEnabled=([^\n]*)")
  if savedStartupHint == "0" then
    state.startupHintEnabled = false
  elseif savedStartupHint == "1" then
    state.startupHintEnabled = true
  elseif savedStartupHint ~= nil then
    migrated = true
  end
  local savedCloseAfterRegularCommand = parseRaw:match("closeAfterRegularCommand=([^\n]*)")
  if savedCloseAfterRegularCommand == "0" then
    state.closeAfterRegularCommand = false
  elseif savedCloseAfterRegularCommand == "1" then
    state.closeAfterRegularCommand = true
  elseif savedCloseAfterRegularCommand ~= nil then
    migrated = true
  end
  local savedFavoriteButton = parseRaw:match("controllerFavoriteButton=([^\n]*)")
  if savedFavoriteButton ~= nil and savedFavoriteButton ~= "auto" then
    local normalized = normalizeControllerButton(savedFavoriteButton)
    if normalized ~= nil then
      state.controllerFavoriteButton = normalized
    else
      migrated = true
    end
  end
  local favoriteOrderMode = parseRaw:match("favoriteOrder=([^\n]*)")
  if favoriteOrderMode == "recent" then
    state.favoriteOrderNeedsCatalogMigration = false
  else
    state.favoriteOrderNeedsCatalogMigration = true
    if favoriteOrderMode ~= nil then migrated = true end
  end
  local favorites = parseRaw:match("favorites=([^\n]*)") or ""
  local favoriteCount = 0
  for token in favorites:gmatch("([^,]+)") do
    local key, code, id = validFavoriteKey(token)
    if not key and token:match("^%d+$") then
      id = tonumber(token)
      key, code = validFavoriteKey(objectKey("c", id))
      migrated = true
    elseif not key then
      migrated = true
    end
    if key and not state.favorites[key] then
      state.favorites[key] = true
      state.favoriteOrder[#state.favoriteOrder + 1] = key
      favoriteCount = favoriteCount + 1
      if favoriteCount >= MAX_FAVORITES then
        migrated = true
        break
      end
    end
  end

  if rawBytes <= MAX_SAVE_BYTES then
    local history = parseRaw:match("history=([^\n]*)") or ""
    for value in history:gmatch("([^|]+)") do
      if #state.history >= MAX_HISTORY then
        migrated = true
        break
      end
      state.history[#state.history + 1] = decode(value)
    end
  end

  debugStateStats(migrated and "state loaded; compaction required" or "state loaded", rawBytes)
  if migrated then
    local saved, err = saveState()
    if not saved then debugLog("state compaction failed: " .. tostring(err)) end
  end
end

function FavoriteModel.finalizeOrder(forceAvailableCatalog)
  if not state.favoriteOrderNeedsCatalogMigration then return end
  if not FavoriteModel.catalogReady and not forceAvailableCatalog then return end
  if not FavoriteModel.catalogReady then
    debugLog("favorite order migration used the available partial catalog")
  end
  local ordered, seen = {}, {}
  for _, entry in ipairs(allEntries) do
    local key = entry.objectKey
    if key and state.favorites[key] and not seen[key] then
      ordered[#ordered + 1] = key
      seen[key] = true
    end
  end
  local unavailable = {}
  for key, enabled in pairs(state.favorites) do
    if enabled and not seen[key] then unavailable[#unavailable + 1] = key end
  end
  table.sort(unavailable)
  for _, key in ipairs(unavailable) do ordered[#ordered + 1] = key end
  state.favoriteOrder = ordered
  state.favoriteOrderNeedsCatalogMigration = false
  local saved, err = saveState()
  if not saved then debugLog("favorite order migration save failed: " .. tostring(err)) end
end

local function clearRunTransientState()
  if state.open then setMenuOpen(false) end
  lifecycleDispatcher.disarm()
  state.queue = nil
  state.lifecycleRequest = nil
  state.unknownCommandConfirmation = nil
  state.toast = nil
  state.toastFramesRemaining = 0
  state.inputMode = nil
  state.searchSelectAll = false
  state.commandSelectAll = false
  state.commandHistoryIndex = nil
  state.commandHistoryDraft = nil
  state.commandHistoryDraftRepeat = nil
  state.nativePauseSuspended = false
  state.inputLease = nil
  state.controllerIndex = nil
  state.controllerOpenHold = 0
  state.controllerOpenLatched = false
  state.controllerOpenIndex = nil
  state.controllerConfirmHold = 0
  state.controllerConfirmCommand = nil
  state.controllerConfirmRemoveCommand = nil
  state.controllerConfirmRemoveMessage = nil
  state.controllerConfirmRepeat = 1
  state.controllerConfirmRepeatMax = nil
  state.controllerConfirmIndex = nil
  state.controllerConfirmSource = nil
  state.controllerConfirmValue = nil
  state.controllerShoulderLatch = {}
  state.pointerActive = false
  state.controlMode = "keyboard"
end

local function showToast(message, kind, duration, action, actionFit)
  kind = kind or "info"
  assert(Presentation.toastColors[kind] ~= nil, "unknown toast kind: " .. tostring(kind))
  local combined = tostring(message or "")
  if action and action ~= "" then combined = combined .. ": " .. tostring(action) end
  state.toast = {
    message = combined,
    primary = tostring(message or ""),
    action = action,
    actionFit = actionFit or "leading",
    kind = kind,
  }
  local resolvedDuration = kind == "success"
    and Presentation.toastDurations.success
    or (tonumber(duration) or Presentation.toastDurations.default)
  state.toastFramesRemaining = math.max(1, math.floor(resolvedDuration))
end

local mcmRegistered = false
local mcmControllerShimInstalled = false

local function installMcmControllerShim()
  if mcmControllerShimInstalled
      or type(InputHelper) ~= "table"
      or type(InputHelper.MultipleButtonTriggered) ~= "function"
      or type(Controller) ~= "table"
      or type(Controller.BUTTON_A) ~= "number"
      or type(ButtonAction) ~= "table"
      or type(ButtonAction.ACTION_MENUCONFIRM) ~= "number"
      or type(Input.IsActionTriggered) ~= "function" then
    return
  end

  local existing = InputHelper.ConsoleUIMenuConfirmShim
  if type(existing) == "table" and InputHelper.MultipleButtonTriggered == existing.wrapper then
    mcmControllerShimInstalled = true
    return
  end

  local declaredConfirmButton = Controller.BUTTON_A
  local menuConfirmAction = ButtonAction.ACTION_MENUCONFIRM
  local previousMultipleButtonTriggered = InputHelper.MultipleButtonTriggered
  local function logicalMenuConfirmTriggered(controllerIndex)
    local firstIndex, lastIndex = 0, 4
    if type(controllerIndex) == "number" then
      firstIndex, lastIndex = controllerIndex, controllerIndex
    end
    for index = firstIndex, lastIndex do
      local ok, triggered = pcall(Input.IsActionTriggered, menuConfirmAction, index)
      if ok and triggered == true then return true end
    end
    return false
  end

  local function multipleButtonTriggered(buttons, controllerIndex)
    if type(buttons) == "table" and #buttons == 1
        and buttons[1] == declaredConfirmButton then
      if logicalMenuConfirmTriggered(controllerIndex) then return declaredConfirmButton end
    end
    return previousMultipleButtonTriggered(buttons, controllerIndex)
  end

  InputHelper.MultipleButtonTriggered = multipleButtonTriggered
  InputHelper.ConsoleUIMenuConfirmShim = {
    previous = previousMultipleButtonTriggered,
    wrapper = multipleButtonTriggered,
  }
  mcmControllerShimInstalled = true
  debugLog("optional MCM logical controller confirm shim installed")
end

local function registerMcmSettings()
  if mcmRegistered or type(ModConfigMenu) ~= "table"
      or type(ModConfigMenu.AddSetting) ~= "function"
      or type(ModConfigMenu.OptionType) ~= "table"
      or ModConfigMenu.OptionType.KEYBIND_KEYBOARD == nil then
    return
  end
  installMcmControllerShim()
  local keybindSetting = {
    Type = ModConfigMenu.OptionType.KEYBIND_KEYBOARD,
    CurrentSetting = function() return state.openKey or DEFAULT_OPEN_KEY end,
    Default = DEFAULT_OPEN_KEY,
    Display = function()
      return "Keyboard open key: " .. openKeyName(state.openKey)
    end,
    OnChange = function(value)
      local nextKey = tonumber(value)
      if not isValidOpenKey(nextKey) then
        showToast("That key conflicts with menu controls", "warning", 150, "Binding unchanged")
        return
      end
      local previousKey = state.openKey or DEFAULT_OPEN_KEY
      state.openKey = nextKey
      local saved, err = saveState()
      if not saved then
        state.openKey = previousKey
        debugLog("open key save failed; rollback: " .. tostring(err))
        showToast("Keybind save failed", "error", 150,
          "Restored " .. openKeyName(previousKey))
        return
      end
      showToast("Open key changed to " .. openKeyName(nextKey), "success", 120)
    end,
    Popup = function()
      return "Press a new keyboard key.$newlineEsc cancels. Avoid gameplay keys and other Mod shortcuts."
    end,
    Info = {
      "Default: F6. The custom key replaces F6.",
      "Navigation, confirm, search, favorite, and restart keys cannot be bound.",
      "Controller opening remains hold L3.",
    },
  }
  if type(ModConfigMenu.PopupGfx) == "table" then
    keybindSetting.PopupGfx = ModConfigMenu.PopupGfx.WIDE_SMALL
    keybindSetting.PopupWidth = 280
  end
  local controllerFavoriteSetting = ModConfigMenu.OptionType.KEYBIND_CONTROLLER ~= nil and {
    Type = ModConfigMenu.OptionType.KEYBIND_CONTROLLER,
    CurrentSetting = function() return state.controllerFavoriteButton or -1 end,
    Default = -1,
    Display = function()
      local button = state.controllerFavoriteButton
      return "Controller favorite key: "
        .. (button ~= nil and ("Custom button " .. button) or "Automatic")
    end,
    OnChange = function(value)
      local numeric = tonumber(value)
      local nextButton = nil
      if value ~= nil and numeric ~= -1 then
        nextButton = normalizeControllerButton(numeric)
        if nextButton == nil then
          showToast("Invalid controller favorite key", "warning", 150, "Binding unchanged")
          return
        end
      end
      local previousButton = state.controllerFavoriteButton
      if nextButton == previousButton then return end
      state.controllerFavoriteButton = nextButton
      local saved, err = saveState()
      if not saved then
        state.controllerFavoriteButton = previousButton
        debugLog("controller favorite button save failed; rollback: " .. tostring(err))
        showToast("Controller favorite key save failed", "error", 150, "Binding restored")
        return
      end
      if nextButton ~= nil then
        showToast("Controller favorite key set to custom button " .. nextButton, "success", 120)
      else
        showToast("Controller favorite key restored to automatic", "success", 120)
      end
    end,
    Popup = function()
      return "Press the controller button to use for favorites.$newlineBack or left clears the binding and restores automatic detection."
    end,
    Info = {
      "Automatic uses logical runtime actions first, then a compatibility fallback.",
      "Custom bindings show raw button numbers to avoid incorrect A / X labels.",
      "Confirm and back actions always outrank a conflicting favorite binding.",
    },
  } or nil
  if controllerFavoriteSetting and type(ModConfigMenu.PopupGfx) == "table" then
    controllerFavoriteSetting.PopupGfx = ModConfigMenu.PopupGfx.WIDE_SMALL
    controllerFavoriteSetting.PopupWidth = 280
  end
  local startupHintSetting = ModConfigMenu.OptionType.BOOLEAN ~= nil and {
    Type = ModConfigMenu.OptionType.BOOLEAN,
    CurrentSetting = function() return state.startupHintEnabled ~= false end,
    Default = true,
    Display = function()
      return "Show startup key hint: " .. (state.startupHintEnabled ~= false and "On" or "Off")
    end,
    OnChange = function(value)
      local nextEnabled = value == true
      local previousEnabled = state.startupHintEnabled ~= false
      if nextEnabled == previousEnabled then return end
      state.startupHintEnabled = nextEnabled
      local saved, err = saveState()
      if not saved then
        state.startupHintEnabled = previousEnabled
        debugLog("startup hint setting save failed; rollback: " .. tostring(err))
        showToast("Startup hint setting save failed", "error", 150, "Previous value restored")
        return
      end
      showToast("Startup key hint turned " .. (nextEnabled and "on" or "off"), "success")
    end,
    Info = {
      "Controls the F6 / L3 hint shown in the first run of each game process.",
      "Turning it off does not change F6, L3, menu help, or other features.",
      "Controller A uses the runtime's logical menu-confirm action.",
    },
  } or nil
  local closeAfterRegularCommandSetting = ModConfigMenu.OptionType.BOOLEAN ~= nil and {
    Type = ModConfigMenu.OptionType.BOOLEAN,
    CurrentSetting = function() return state.closeAfterRegularCommand ~= false end,
    Default = true,
    Display = function()
      return "Close menu after regular commands: "
        .. (state.closeAfterRegularCommand ~= false and "On" or "Off")
    end,
    OnChange = function(value)
      local nextEnabled = value == true
      local previousEnabled = state.closeAfterRegularCommand ~= false
      if nextEnabled == previousEnabled then return end
      state.closeAfterRegularCommand = nextEnabled
      local saved, err = saveState()
      if not saved then
        state.closeAfterRegularCommand = previousEnabled
        debugLog("close-after-command setting save failed; rollback: " .. tostring(err))
        showToast("Close-after-command setting save failed", "error", 150,
          "Previous value restored")
        return
      end
      showToast("Close menu after regular commands turned "
        .. (nextEnabled and "on" or "off"), "success")
    end,
    Info = {
      "Applies to regular give, remove, spawn, debug, batch, and manual commands.",
      "When off, the current page and selection remain; command editing ends but text is kept.",
      "Rewind, restart, warp, and other run-changing commands always close the menu.",
    },
  } or nil
  local ok, err = pcall(function()
    ModConfigMenu.AddSetting("Console UI", "Settings", keybindSetting)
    if controllerFavoriteSetting then
      ModConfigMenu.AddSetting("Console UI", "Settings", controllerFavoriteSetting)
    end
    if startupHintSetting then
      ModConfigMenu.AddSetting("Console UI", "Settings", startupHintSetting)
    end
    if closeAfterRegularCommandSetting then
      ModConfigMenu.AddSetting("Console UI", "Settings", closeAfterRegularCommandSetting)
    end
  end)
  if ok then
    mcmRegistered = true
    debugLog("optional Mod Config Menu settings registered")
    if not controllerFavoriteSetting then
      debugLog("optional Mod Config Menu controller keybind unavailable; favorite option skipped")
    end
    if not startupHintSetting then
      debugLog("optional Mod Config Menu boolean setting unavailable; startup hint option skipped")
    end
    if not closeAfterRegularCommandSetting then
      debugLog("optional Mod Config Menu boolean setting unavailable; close-after-command option skipped")
    end
  else
    debugLog("optional Mod Config Menu registration failed: " .. tostring(err))
  end
end

local function commandSpec(command)
  local verb = trim(command):lower():match("^(%S+)")
  return CommandSpecs.byVerb[verb], verb
end

local function disabledCommandReason(spec)
  if spec.mode == "output" then return "This command only outputs to the native console and cannot run here" end
  local reasons = {
    code = "This command can execute arbitrary code and is disabled in the Workshop build",
    save = "This command may change persistent progress and is disabled here",
    process = "This command controls the game process and is disabled here",
    indirect = "This command can indirectly execute uncontrolled commands and is disabled here",
    lifecycle = "Runtime testing caused a hang and process exit, so this command is disabled",
  }
  return reasons[spec.reason] or "This command is disabled in the Workshop build"
end

local function validateKnownParameters(spec, command, verb)
  local argument = trim(command:sub(#verb + 1))
  if spec.syntax:find("<", 1, true) and argument == "" then
    return false, "Missing command parameters; press C to inspect and complete the syntax"
  end
  if spec.validator == "restart" then
    if argument == "" then return true end
    local id = tonumber(argument)
    if not id or id % 1 ~= 0 or id < 0 or id > 40 then
      return false, "restart character ID must be an integer from 0 to 40"
    end
  elseif spec.validator == "challenge" then
    local id = tonumber(argument)
    local count = Challenge and tonumber(Challenge.NUM_CHALLENGES)
    if not count then return false, "This runtime does not expose its challenge count; command blocked" end
    if not id or id % 1 ~= 0 or id < 1 or id >= count then
      return false, "challenge ID must be between 1 and " .. tostring(count - 1)
    end
  elseif spec.validator == "curse" then
    local value = tonumber(argument)
    if not value or value % 1 ~= 0 or value < 0 or value > 255 then
      return false, "curse must be an integer from 0 to 255"
    end
  elseif spec.validator == "seed" then
    if not argument:match("^[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]%s+[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]$") then
      return false, "seed must use the uppercase XXXX XXXX format"
    end
  end
  return true
end

local function validateCommand(command)
  command = trim(command)
  if command == "" then return false, "Command cannot be empty" end
  if #command > 120 then return false, "Command is too long" end
  if command:find("[\r\n;]") then return false, "Command contains an unsafe separator" end
  local spec, verb = commandSpec(command)
  if spec and (spec.mode == "output" or spec.mode == "disabled") then
    return false, disabledCommandReason(spec), spec
  end
  if spec then
    local valid, reason = validateKnownParameters(spec, command, verb)
    if not valid then return false, reason, spec end
  end
  return true, command, spec
end

local function isStageCommand(command)
  local lowered = trim(command):lower()
  return lowered == "stage" or lowered:match("^stage%s+") ~= nil
end

local function isGreedMode()
  local ok, result = pcall(function() return Game():IsGreedMode() end)
  return ok and result == true
end

local function stageEntryAvailable(entry, greedMode)
  if entry.cat ~= "stage" then return true end
  if greedMode then return entry.stageMode == "greed" end
  return entry.stageMode ~= "greed"
end

local function addHistory(command, count)
  local label = command .. (count > 1 and (" ×" .. count) or "")
  for index = #state.history, 1, -1 do
    if state.history[index] == label then table.remove(state.history, index) end
  end
  table.insert(state.history, 1, label)
  while #state.history > MAX_HISTORY do table.remove(state.history) end
end

local function applyPostCommandMenuPolicy(spec)
  if (spec and spec.phase == "render") or state.closeAfterRegularCommand ~= false then
    setMenuOpen(false)
    return
  end
  state.inputMode = nil
  state.commandSelectAll = false
  state.commandHistoryIndex = nil
  state.commandHistoryDraft = nil
  state.commandHistoryDraftRepeat = nil
end

local function queueCommand(command, requestedCount, explicitRepeatMax)
  local valid, value, spec = validateCommand(command)
  if not valid then
    showToast(value, "warning", 120)
    return false
  end

  if not spec then
    if state.unknownCommandConfirmation ~= value then
      state.unknownCommandConfirmation = value
      showToast("Unknown or third-party command", "warning", 180,
        "Press Enter again to run it once")
      return false
    end
    state.unknownCommandConfirmation = nil
  else
    state.unknownCommandConfirmation = nil
  end

  if isStageCommand(value) then
    local stageMode = isGreedMode() and "greed" or "normal"
    if not stageCommandWhitelists[stageMode][value:lower()] then
      local message = stageMode == "greed"
      and "That floor is not on the Greed-mode safe list, so the command was blocked"
      or "That floor is not on the Normal-mode safe list, so the command was blocked"
      showToast(message, "warning", 180)
      return false
    end
  end

  if state.queue or state.lifecycleRequest or state.lifecycleReceipt then
    showToast("The previous batch is still running", "warning", 90)
    return false
  end

  local requested = clamp(tonumber(requestedCount) or 1, 1, 99)
  local repeatMax = tonumber(explicitRepeatMax)
  if not repeatMax then repeatMax = spec and spec.repeatMax or 1 end
  repeatMax = clamp(math.floor(repeatMax), 1, 99)
  local count = math.min(requested, repeatMax)
  if requested > repeatMax then
    showToast("This command is limited to one execution for safety", "warning", 120)
  end

  if spec and spec.phase == "render" then
    state.lifecycleRequest = { command = value }
    state.repeatCount = 1
    state.inputLease = nil
    applyPostCommandMenuPolicy(spec)
    lifecycleDispatcher.arm()
    return true
  end

  state.queue = {
    command = value,
    total = count,
    done = 0,
    nextFrame = Game():GetFrameCount(),
    failed = nil,
    finished = false,
  }
  applyPostCommandMenuPolicy(spec)
  return true
end

local function queueEntry(entry, requestedCount)
  if not entry then return false end
  if entry.catalogAction == "disabled" then
    showToast(disabledCommandReason(entry.commandSpec), "warning", 180)
    return false
  end
  if entry.catalogAction == "manual" then
    showToast("Parameter reference: press C to enter the full command", "warning", 120)
    return false
  end
  return queueCommand(entry.cmd, requestedCount, entry.repeatMax)
end

local function finishQueue(queue)
  if not queue or queue.finished then return end
  queue.finished = true
  queue.total = clamp(math.floor(tonumber(queue.total) or 1), 1, 99)
  queue.done = clamp(math.floor(tonumber(queue.done) or 0), 0, queue.total)
  if state.queue == queue then state.queue = nil end
  addHistory(queue.command, queue.done)
  state.repeatCount = 1
  local saved, saveError = saveState()
  if not saved then
      showToast("Command completed", "error", 180, "History could not be saved")
    debugLog("history save failed: " .. tostring(saveError))
  elseif queue.failed then
    showToast("Partially completed " .. queue.done .. "/" .. queue.total,
      "error", 180, queue.failed)
  else
    showToast(
      "Completed" .. (queue.total > 1 and (" x" .. queue.total) or ""),
      "success", 60, queue.command, "trailing")
    state.toast.inlineAction = true
  end
end

local function processQueue()
  local queue = state.queue
  if not queue then return end
  local rawTotal = tonumber(queue.total) or 1
  local rawDone = tonumber(queue.done) or 0
  queue.total = clamp(math.floor(rawTotal), 1, 99)
  queue.done = clamp(math.floor(rawDone), 0, queue.total)
  if rawTotal ~= queue.total or rawDone ~= queue.done then
    debugLog("queue invariant corrected: done=" .. tostring(rawDone)
      .. "; total=" .. tostring(rawTotal))
  end
  if queue.finished or queue.done >= queue.total then
    finishQueue(queue)
    return
  end
  local frame = Game():GetFrameCount()
  if frame < queue.nextFrame then return end

  local ok, result = pcall(Isaac.ExecuteCommand, queue.command)
  if not ok then
    queue.failed = tostring(result or "The Lua API rejected the command")
    finishQueue(queue)
    return
  end

  queue.done = math.min(queue.total, queue.done + 1)
  if queue.done >= queue.total then
    finishQueue(queue)
  else
    queue.nextFrame = frame + REPEAT_DELAY_FRAMES
  end
end

local function finalizeLifecycleReceipt()
  local receipt = state.lifecycleReceipt
  if not receipt then return end
  receipt.stableUpdates = (receipt.stableUpdates or 0) + 1
  if receipt.stableUpdates < 2 then return end
  state.lifecycleReceipt = nil
  addHistory(receipt.command, 1)
  state.repeatCount = 1
  local saved, saveError = saveState()
  if not saved then
    showToast("Command was dispatched", "error", 180, "History could not be saved")
    debugLog("lifecycle history save failed: " .. tostring(saveError))
  else
    showToast("Completed", "success", 60, receipt.command, "trailing")
    state.toast.inlineAction = true
  end
end

local function onUpdate()
  local frame = Game():GetFrameCount()
  local previousFrame = state.lastGameFrame
  if previousFrame ~= nil and frame < previousFrame then
    clearRunTransientState()
    debugLog("game frame reset detected; cleared transient run state")
  elseif state.toast and previousFrame ~= nil then
    local elapsed = frame - previousFrame
    if elapsed > 0 then
      state.toastFramesRemaining = math.max(0, state.toastFramesRemaining - elapsed)
      if state.toastFramesRemaining == 0 then state.toast = nil end
    end
  end
  state.lastGameFrame = frame
  finalizeLifecycleReceipt()
  processQueue()
end

local function currentCategory()
  return Catalog.categories[state.categoryIndex]
end

local function searchableText(entry)
  if not entry.searchText then entry.searchText = buildSearchText(entry) end
  return entry.searchText
end

local function visibleEntries()
  local category = currentCategory()
  local result = {}
  local query = trim(state.search):lower()
  local greedMode = isGreedMode()

  if query ~= "" then
    -- Searching is global: official names, normalized names, common aliases,
    -- commands, and IDs all work regardless of the selected category.
    for _, entry in ipairs(allEntries) do result[#result + 1] = entry end
  elseif category.id == "featured" then
    FavoriteModel.finalizeOrder()
    local seen = {}
    if state.favoriteOrderNeedsCatalogMigration then
      for _, entry in ipairs(allEntries) do
        local key = entry.objectKey
        if entry.canFavorite and key and state.favorites[key] and not seen[key] then
          result[#result + 1] = entry
          seen[key] = true
        end
      end
    else
      for _, key in ipairs(state.favoriteOrder) do
        local entry = FavoriteModel.entryByKey[key]
        if entry and state.favorites[key] and not seen[key] then
          result[#result + 1] = entry
          seen[key] = true
        end
      end
    end
  elseif category.id == "all_items" then
    for _, entry in ipairs(completeEntries) do result[#result + 1] = entry end
  else
    for _, entry in ipairs(allEntries) do
      if entry.cat == category.id then result[#result + 1] = entry end
    end
  end

  local modeFiltered = {}
  for _, entry in ipairs(result) do
    if stageEntryAvailable(entry, greedMode) then modeFiltered[#modeFiltered + 1] = entry end
  end
  result = modeFiltered

  if query ~= "" then
    local filtered = {}
    for _, entry in ipairs(result) do
      if searchableText(entry):find(query, 1, true) then filtered[#filtered + 1] = entry end
    end
    result = filtered
  end
  return result
end

local function resetSelection()
  state.selection = 1
  state.page = 1
  state.detailEntryId = nil
  state.detailPage = 1
end

local function setCategory(index)
  state.categoryIndex = ((index - 1) % #Catalog.categories) + 1
  state.categoryPage = math.floor((state.categoryIndex - 1) / CATEGORIES_PER_PAGE) + 1
  resetSelection()
end

local function changeCategoryPage(delta)
  local pageCount = math.max(1, math.ceil(#Catalog.categories / CATEGORIES_PER_PAGE))
  local targetPage = clamp(state.categoryPage + delta, 1, pageCount)
  if targetPage == state.categoryPage then return false end
  state.categoryPage = targetPage
  setCategory((state.categoryPage - 1) * CATEGORIES_PER_PAGE + 1)
  return true
end

local function changeEntryPage(delta, entries)
  local pageCount = math.max(1, math.ceil(#entries / ITEMS_PER_PAGE))
  local targetPage = clamp(state.page + delta, 1, pageCount)
  if targetPage == state.page then return false end
  state.page = targetPage
  state.selection = 1
  return true
end

local function resolveInitialMenuFocus(entries)
  if state.initialMenuFocusResolved then return entries end
  state.initialMenuFocusResolved = true
  if trim(state.search) ~= "" or currentCategory().id ~= "featured" or #entries > 0 then
    return entries
  end
  local allItems = categoryById.all_items
  if allItems then
    setCategory(allItems.index)
    entries = visibleEntries()
  end
  state.sidebarFocus = #entries == 0
  return entries
end

local function selectedEntry(entries)
  return entries[(state.page - 1) * ITEMS_PER_PAGE + state.selection]
end

local function toggleFavorite(entry)
  local key = entry and entry.objectKey or nil
  if not entry or not entry.canFavorite or not key then
    showToast("This entry cannot be favorited", "warning", 75)
    return
  end
  FavoriteModel.finalizeOrder(true)
  local wasFavorite = state.favorites[key] == true
  local previousIndex = FavoriteModel.orderIndex(key)
  assert((previousIndex ~= nil) == wasFavorite, "favorite state and recent order differ: " .. key)
  if wasFavorite then
    state.favorites[key] = nil
    table.remove(state.favoriteOrder, previousIndex)
  else
    if #state.favoriteOrder >= MAX_FAVORITES then
      showToast("Favorite limit reached", "warning", 120)
      return
    end
    state.favorites[key] = true
    table.insert(state.favoriteOrder, 1, key)
  end
  local saved, saveError = saveState()
  if not saved then
    if wasFavorite then
      state.favorites[key] = true
      table.insert(state.favoriteOrder, previousIndex, key)
    else
      state.favorites[key] = nil
      assert(state.favoriteOrder[1] == key, "new favorite moved before rollback")
      table.remove(state.favoriteOrder, 1)
    end
    showToast("Favorite could not be saved", "error", 150, "The change was reverted")
    debugLog("favorite save failed: " .. tostring(saveError))
    return
  end
  showToast(wasFavorite and "Removed from favorites" or "Added to Featured", "success", 75)
end

local function changeRepeat(delta)
  state.repeatCount = clamp(state.repeatCount + delta, 1, 99)
  if state.repeatCount > 20 then
    showToast("More than 20 repeats may cause a brief pause", "warning", 75)
  end
end

local KEY_CHARS = {
  [Keyboard.KEY_SPACE] = " ", [Keyboard.KEY_PERIOD] = ".", [Keyboard.KEY_MINUS] = "-",
  [Keyboard.KEY_SLASH] = "/", [Keyboard.KEY_EQUAL] = "=",
}
for code = Keyboard.KEY_0, Keyboard.KEY_9 do KEY_CHARS[code] = string.char(code) end
for code = Keyboard.KEY_A, Keyboard.KEY_Z do KEY_CHARS[code] = string.char(code + 32) end

local function controlPressed()
  return Input.IsButtonPressed(Keyboard.KEY_LEFT_CONTROL, 0)
    or Input.IsButtonPressed(Keyboard.KEY_RIGHT_CONTROL, 0)
end

local function markKeyboardInput()
  state.pointerActive = false
  state.controlMode = "keyboard"
end

local function captureEditableText(value, selectAll)
  if controlPressed() and Input.IsButtonTriggered(Keyboard.KEY_A, 0) then
    return value, value ~= "", false
  end
  local backspace = Input.IsButtonTriggered(Keyboard.KEY_BACKSPACE, 0)
  local delete = Input.IsButtonTriggered(Keyboard.KEY_DELETE, 0)
  if selectAll and (backspace or delete) then return "", false, true end
  if backspace then
    return value:sub(1, math.max(0, #value - 1)), false, value ~= ""
  end
  for key, character in pairs(KEY_CHARS) do
    if Input.IsButtonTriggered(key, 0) then
      if selectAll then return character, false, true end
      if #value < 120 then return value .. character, false, true end
      return value, false, false
    end
  end
  return value, selectAll, false
end

local function editableTextTriggered()
  if controlPressed() and Input.IsButtonTriggered(Keyboard.KEY_A, 0) then
    markKeyboardInput()
    return true
  end
  if Input.IsButtonTriggered(Keyboard.KEY_BACKSPACE, 0)
      or Input.IsButtonTriggered(Keyboard.KEY_DELETE, 0) then
    markKeyboardInput()
    return true
  end
  for key in pairs(KEY_CHARS) do
    if Input.IsButtonTriggered(key, 0) then
      markKeyboardInput()
      return true
    end
  end
  return false
end

local function captureSearchText(value)
  local nextValue, selectAll = captureEditableText(value, state.searchSelectAll)
  state.searchSelectAll = selectAll
  return nextValue
end

local function clearCommandHistoryNavigation()
  state.commandHistoryIndex = nil
  state.commandHistoryDraft = nil
  state.commandHistoryDraftRepeat = nil
end

local function decodeHistoryEntry(label)
  local command = tostring(label or "")
  local count = tonumber(command:match(" ×(%d+)$")) or 1
  if count > 1 then command = command:gsub(" ×%d+$", "") end
  return command, clamp(math.floor(count), 1, 99)
end

local function recallCommandHistory(delta)
  state.unknownCommandConfirmation = nil
  if #state.history == 0 then return end
  if state.commandHistoryIndex == nil then
    if delta < 0 then return end
    state.commandHistoryDraft = state.manualCommand
    state.commandHistoryDraftRepeat = state.repeatCount
    state.commandHistoryIndex = 1
  else
    local target = state.commandHistoryIndex + delta
    if target < 1 then
      state.manualCommand = state.commandHistoryDraft or ""
      state.repeatCount = clamp(state.commandHistoryDraftRepeat or 1, 1, 99)
      clearCommandHistoryNavigation()
      state.commandSelectAll = false
      return
    end
    state.commandHistoryIndex = clamp(target, 1, #state.history)
  end
  state.manualCommand, state.repeatCount = decodeHistoryEntry(
    state.history[state.commandHistoryIndex])
  state.commandSelectAll = false
end

local function captureCommandText()
  local value, selectAll, changed = captureEditableText(
    state.manualCommand, state.commandSelectAll)
  state.manualCommand = value
  state.commandSelectAll = selectAll
  if changed then
    clearCommandHistoryNavigation()
    state.unknownCommandConfirmation = nil
  end
end

local function beginCommandInput(entry)
  if entry and entry.catalogAction == "disabled" then
    showToast(disabledCommandReason(entry.commandSpec), "warning", 180)
    return false
  end
  if entry then
    state.manualCommand = entry.catalogAction == "manual"
      and (entry.commandTemplate or "") or entry.cmd
  end
  state.inputMode = "command"
  state.searchSelectAll = false
  state.commandSelectAll = entry ~= nil and entry.catalogAction ~= "manual"
    and state.manualCommand ~= ""
  state.unknownCommandConfirmation = nil
  clearCommandHistoryNavigation()
  return true
end

local function addControllerCandidate(candidates, seen, index)
  index = tonumber(index)
  if not index then return end
  index = math.floor(index)
  if index < 0 or seen[index] then return end
  seen[index] = true
  candidates[#candidates + 1] = index
end

local function controllerCandidates()
  local candidates, seen = {}, {}
  local countOk, playerCount = pcall(function() return Game():GetNumPlayers() end)
  assert(countOk and tonumber(playerCount), "unable to enumerate assigned controllers")
  for playerIndex = 0, math.max(0, math.floor(tonumber(playerCount)) - 1) do
    local playerOk, controllerIndex = pcall(function()
      local player = Isaac.GetPlayer(playerIndex)
      return player and player.ControllerIndex
    end)
    if playerOk then addControllerCandidate(candidates, seen, controllerIndex) end
  end
  return candidates
end

local function controllerButtonPressed(button, index)
  if button == nil or type(Input.IsButtonPressed) ~= "function" then return false end
  local ok, pressed = pcall(Input.IsButtonPressed, button, index)
  return ok and pressed == true
end

local function markControllerInput(index)
  state.controllerIndex = index
  state.pointerActive = false
  state.controlMode = "controller"
end

local function controllerButtonTriggeredAt(button, index)
  if button == nil or type(Input.IsButtonTriggered) ~= "function" then return false end
  local ok, triggered = pcall(Input.IsButtonTriggered, button, index)
  return ok and triggered == true
end

local function controllerButtonTriggered(button)
  for _, index in ipairs(controllerCandidates()) do
    if controllerButtonTriggeredAt(button, index) then
      markControllerInput(index)
      return true
    end
  end
  return false
end

local function controllerActionTriggeredAt(action, index)
  if action == nil or type(Input.IsActionTriggered) ~= "function" then return false end
  local ok, triggered = pcall(Input.IsActionTriggered, action, index)
  return ok and triggered == true
end

local function controllerRoleEvent(candidates, role, source, value)
  if value == nil then return nil end
  local triggeredAt = source == "action"
    and controllerActionTriggeredAt or controllerButtonTriggeredAt
  for _, index in ipairs(candidates) do
    if triggeredAt(value, index) then
      markControllerInput(index)
      return { role = role, source = source, value = value, index = index }
    end
  end
  return nil
end

function ConsoleUI.controllerActionValueAt(action, index)
  if action == nil or type(Input.GetActionValue) ~= "function" then return 0 end
  local ok, value = pcall(Input.GetActionValue, action, index)
  value = ok and tonumber(value) or 0
  return value or 0
end

function ConsoleUI.controllerShoulderRoleEvent(candidates, role, action, button, analog)
  for _, index in ipairs(candidates) do
    local latchKey = role .. ":" .. tostring(index)
    local value = analog and ConsoleUI.controllerActionValueAt(action, index) or 0
    if analog and value <= CONTROLLER_INPUT_COMPATIBILITY.triggerReleaseThreshold then
      state.controllerShoulderLatch[latchKey] = nil
    end
    if controllerActionTriggeredAt(action, index) then
      if analog and value > CONTROLLER_INPUT_COMPATIBILITY.triggerReleaseThreshold then
        state.controllerShoulderLatch[latchKey] = true
      end
      markControllerInput(index)
      return { role = role, source = "action", value = action, index = index }
    end
    if analog and value >= CONTROLLER_INPUT_COMPATIBILITY.triggerPressThreshold
        and not state.controllerShoulderLatch[latchKey] then
      state.controllerShoulderLatch[latchKey] = true
      markControllerInput(index)
      return { role = role, source = "action_value", value = action, index = index }
    end
    if controllerButtonTriggeredAt(button, index) then
      if analog then state.controllerShoulderLatch[latchKey] = true end
      markControllerInput(index)
      return { role = role, source = "button", value = button, index = index }
    end
  end
  return nil
end

function ConsoleUI.controllerShoulderOwnerActive(side, index, repeatAction, repeatButton, pageAction)
  local ownerKey = "owner:" .. side .. ":" .. tostring(index)
  if not state.controllerShoulderLatch[ownerKey] then return false end
  local actionPressed = false
  if repeatAction ~= nil and type(Input.IsActionPressed) == "function" then
    local ok, pressed = pcall(Input.IsActionPressed, repeatAction, index)
    actionPressed = ok and pressed == true
  end
  local pageValue = ConsoleUI.controllerActionValueAt(pageAction, index)
  if actionPressed or controllerButtonPressed(repeatButton, index)
      or pageValue > CONTROLLER_INPUT_COMPATIBILITY.triggerReleaseThreshold then
    return true
  end
  state.controllerShoulderLatch[ownerKey] = nil
  return false
end

local function controllerShoulderEvent(candidates)
  -- Steam Input may expose shoulder controls only through semantic actions,
  -- while older runtimes may expose only named raw buttons. Resolve the four
  -- physical roles independently and let the existing business dispatcher
  -- consume a single event. Bumpers retain priority if a runtime aliases names.
  local previousAction = CONTROLLER_INPUT_COMPATIBILITY.pagePreviousAction
  if previousAction == CONTROLLER_INPUT_COMPATIBILITY.repeatDecreaseAction then previousAction = nil end
  local nextAction = CONTROLLER_INPUT_COMPATIBILITY.pageNextAction
  if nextAction == CONTROLLER_INPUT_COMPATIBILITY.repeatIncreaseAction then nextAction = nil end
  local event = ConsoleUI.controllerShoulderRoleEvent(candidates, "repeat_decrease",
    CONTROLLER_INPUT_COMPATIBILITY.repeatDecreaseAction, CONTROLLER_REPEAT_DECREASE, false)
  if event then
    local bumperEvidence = controllerButtonTriggeredAt(CONTROLLER_REPEAT_DECREASE, event.index)
      or controllerButtonPressed(CONTROLLER_REPEAT_DECREASE, event.index)
    local triggerEvidence = controllerButtonTriggeredAt(CONTROLLER_PAGE_PREVIOUS, event.index)
      or controllerButtonPressed(CONTROLLER_PAGE_PREVIOUS, event.index)
      or controllerActionTriggeredAt(previousAction, event.index)
      or ConsoleUI.controllerActionValueAt(previousAction, event.index)
        >= CONTROLLER_INPUT_COMPATIBILITY.triggerPressThreshold
    if bumperEvidence or not triggerEvidence then
      state.controllerShoulderLatch["owner:left:" .. tostring(event.index)] = true
      return event
    end
  end
  event = ConsoleUI.controllerShoulderRoleEvent(candidates, "repeat_increase",
    CONTROLLER_INPUT_COMPATIBILITY.repeatIncreaseAction, CONTROLLER_REPEAT_INCREASE, false)
  if event then
    local bumperEvidence = controllerButtonTriggeredAt(CONTROLLER_REPEAT_INCREASE, event.index)
      or controllerButtonPressed(CONTROLLER_REPEAT_INCREASE, event.index)
    local triggerEvidence = controllerButtonTriggeredAt(CONTROLLER_PAGE_NEXT, event.index)
      or controllerButtonPressed(CONTROLLER_PAGE_NEXT, event.index)
      or controllerActionTriggeredAt(nextAction, event.index)
      or ConsoleUI.controllerActionValueAt(nextAction, event.index)
        >= CONTROLLER_INPUT_COMPATIBILITY.triggerPressThreshold
    if bumperEvidence or not triggerEvidence then
      state.controllerShoulderLatch["owner:right:" .. tostring(event.index)] = true
      return event
    end
  end
  local previousSuppressed = false
  for _, index in ipairs(candidates) do
    if ConsoleUI.controllerShoulderOwnerActive("left", index,
        CONTROLLER_INPUT_COMPATIBILITY.repeatDecreaseAction, CONTROLLER_REPEAT_DECREASE,
        previousAction) then previousSuppressed = true end
  end
  if not previousSuppressed then
    event = ConsoleUI.controllerShoulderRoleEvent(candidates, "page_previous",
      previousAction, CONTROLLER_PAGE_PREVIOUS, true)
    if event then return event end
  end
  local nextSuppressed = false
  for _, index in ipairs(candidates) do
    if ConsoleUI.controllerShoulderOwnerActive("right", index,
        CONTROLLER_INPUT_COMPATIBILITY.repeatIncreaseAction, CONTROLLER_REPEAT_INCREASE,
        nextAction) then nextSuppressed = true end
  end
  if nextSuppressed then return nil end
  return ConsoleUI.controllerShoulderRoleEvent(candidates, "page_next",
    nextAction, CONTROLLER_PAGE_NEXT, true)
end

local function controllerMenuEvent()
  local candidates = controllerCandidates()
  -- Primary menu actions retain semantic priority. Physical shoulder roles
  -- are resolved separately because official menu-tab actions do not
  -- distinguish LB/RB from LT/RT consistently across runtimes.
  local event = controllerRoleEvent(candidates, "back", "action", CONTROLLER_ACTION_BACK)
  if event then return event end
  event = controllerRoleEvent(candidates, "confirm", "action", CONTROLLER_ACTION_CONFIRM)
  if event then return event end
  event = controllerRoleEvent(candidates, "favorite", "action", CONTROLLER_ACTION_FAVORITE)
  if event then return event end
  local favoriteButton = state.controllerFavoriteButton
    or CONTROLLER_INPUT_COMPATIBILITY.favorite
  event = controllerRoleEvent(candidates, "back", "button", CONTROLLER_INPUT_COMPATIBILITY.back)
  if event then return event end
  event = controllerRoleEvent(candidates, "confirm", "button", CONTROLLER_INPUT_COMPATIBILITY.confirm)
  if event then return event end
  event = controllerRoleEvent(candidates, "favorite", "button", favoriteButton)
  if event then return event end
  event = controllerRoleEvent(candidates, "details", "button", controllerButton("BUTTON_Y"))
  if event then return event end
  return controllerShoulderEvent(candidates)
end

local function controllerDirectionTriggered(action, button)
  local candidates = controllerCandidates()
  local event = controllerRoleEvent(candidates, "direction", "action", action)
  if event then return true end
  return controllerRoleEvent(candidates, "direction", "button", button) ~= nil
end

local function controllerOpenPressed()
  for _, index in ipairs(controllerCandidates()) do
    if controllerButtonPressed(CONTROLLER_OPEN_BUTTON, index) then return true, index end
  end
  return false, nil
end

local function moveGridSelection(entries, delta)
  if #entries == 0 then return end
  local current = (state.page - 1) * ITEMS_PER_PAGE + state.selection
  local target = clamp(current + delta, 1, #entries)
  state.page = math.floor((target - 1) / ITEMS_PER_PAGE) + 1
  state.selection = ((target - 1) % ITEMS_PER_PAGE) + 1
  state.detailEntryId = nil
  state.detailPage = 1
end

local function keyTriggered(key)
  local triggered = Input.IsButtonTriggered(key, 0)
  if triggered then markKeyboardInput() end
  return triggered
end

local function enterTriggered()
  local pressed = Input.IsButtonPressed(Keyboard.KEY_ENTER, 0)
  local triggered = Input.IsButtonTriggered(Keyboard.KEY_ENTER, 0)
  local rising = pressed and not state.keyboardEnterPressed
  state.keyboardEnterPressed = pressed
  if triggered or rising then
    markKeyboardInput()
    return true
  end
  return false
end

local function controllerActionPressed(action, index)
  if action == nil or type(Input.IsActionPressed) ~= "function" then return false end
  local ok, pressed = pcall(Input.IsActionPressed, action, index)
  return ok and pressed == true
end

local function restartActionPressed()
  if CONTROLLER_ACTION_RESTART == nil then return false end
  local candidates, seen = {}, {}
  -- Controller index 0 is also the keyboard action route. Assigned player
  -- controllers cover controller-driven restart bindings without scanning
  -- arbitrary unassigned indexes.
  addControllerCandidate(candidates, seen, 0)
  for _, index in ipairs(controllerCandidates()) do
    addControllerCandidate(candidates, seen, index)
  end
  for _, index in ipairs(candidates) do
    if controllerActionPressed(CONTROLLER_ACTION_RESTART, index) then return true end
  end
  return false
end

local function clearInputLease()
  state.inputLease = nil
end

local function armInputLease(kind, value, index)
  assert(kind == "keyboard" or kind == "mouse" or kind == "action"
      or kind == "controller_button", "unsupported input lease kind")
  assert(type(value) == "number", "input lease value must be numeric")
  state.inputLease = { kind = kind, value = value, index = tonumber(index) or 0 }
end

local function armControllerInputLease(event)
  if not event then return end
  local kind = event.source == "action" and "action" or "controller_button"
  armInputLease(kind, event.value, event.index)
end

local function inputLeaseActive()
  local lease = state.inputLease
  if not lease then return false end
  local pressed
  if lease.kind == "action" then
    pressed = controllerActionPressed(lease.value, lease.index)
  elseif lease.kind == "mouse" then
    pressed = Input.IsMouseBtnPressed(lease.value)
  else
    pressed = controllerButtonPressed(lease.value, lease.index)
  end
  if pressed then return true end
  clearInputLease()
  return false
end

local function controllerConfirmPressed(index)
  if state.controllerConfirmSource == "action" then
    return controllerActionPressed(state.controllerConfirmValue, index)
  elseif state.controllerConfirmSource == "button" then
    return controllerButtonPressed(state.controllerConfirmValue, index)
  end
  return false
end

local function collectibleIdFromEntry(entry)
  if not entry then return nil end
  return tonumber(tostring(entry.cmd or ""):match("^giveitem%s+c(%d+)%s*$"))
end

local function hasOfficialImmediateGrant(entry)
  local itemId = collectibleIdFromEntry(entry)
  if not itemId then return false end
  if officialGrantCache[itemId] ~= nil then return officialGrantCache[itemId] end

  local hasGrant = false
  local itemConfig = getSharedItemConfig()
  if itemConfig then
    local itemOk, config = pcall(function() return itemConfig:GetCollectible(itemId) end)
    if itemOk and config then
      for _, field in ipairs(OFFICIAL_GRANT_FIELDS) do
        local fieldOk, value = pcall(function() return config[field] end)
        if fieldOk and (tonumber(value) or 0) ~= 0 then
          hasGrant = true
          break
        end
      end
    end
  end
  officialGrantCache[itemId] = hasGrant
  return hasGrant
end

local function removalCommand(entry)
  if not entry or entry.canRemove ~= true or hasOfficialImmediateGrant(entry) then return nil end
  local itemCode = tostring(entry.cmd or ""):match("^giveitem%s+(.+)$")
  if itemCode then return "remove " .. itemCode end
  return nil
end

local function removalUnavailableMessage(entry, controller)
  if hasOfficialImmediateGrant(entry) then
    return controller
      and "This item grants resources immediately; holding A cannot reverse them"
      or "This item grants resources immediately; removing it will not take them back"
  end
  return controller
      and "This action has no removable item; tap A to execute it"
      or "This action has no removable item"
end

local function clearControllerConfirm()
  state.controllerConfirmHold = 0
  state.controllerConfirmCommand = nil
  state.controllerConfirmRemoveCommand = nil
  state.controllerConfirmRemoveMessage = nil
  state.controllerConfirmRepeat = 1
  state.controllerConfirmRepeatMax = nil
  state.controllerConfirmIndex = nil
  state.controllerConfirmSource = nil
  state.controllerConfirmValue = nil
end

local function updateControllerConfirm()
  if not state.controllerConfirmCommand then return false end
  local index = state.controllerConfirmIndex or state.controllerIndex or 0
  if controllerConfirmPressed(index) then
    state.controllerConfirmHold = state.controllerConfirmHold + 1
    if state.controllerConfirmHold >= CONTROLLER_REMOVE_HOLD_FRAMES then
      local command = state.controllerConfirmRemoveCommand
      local message = state.controllerConfirmRemoveMessage
      local source, value = state.controllerConfirmSource, state.controllerConfirmValue
      clearControllerConfirm()
      if command then
        armInputLease(source == "action" and "action" or "controller_button", value, index)
        queueCommand(command, 1)
      else
  showToast(message or "This action has no removable item; tap A to execute it", "warning", 120)
      end
    end
  else
    local command = state.controllerConfirmCommand
    local repeatCount = state.controllerConfirmRepeat
    local repeatMax = state.controllerConfirmRepeatMax
    local source, value = state.controllerConfirmSource, state.controllerConfirmValue
    clearControllerConfirm()
    armInputLease(source == "action" and "action" or "controller_button", value, index)
    queueCommand(command, repeatCount, repeatMax)
  end
  return true
end

local function handleKeyboardAndController(entries)
  local keyboardEnter = enterTriggered()
  local controllerOpen = false
  local openPressed, openIndex = controllerOpenPressed()
  if not state.open and openPressed then
    if state.controllerOpenIndex ~= openIndex then state.controllerOpenHold = 0 end
    state.controllerOpenIndex = openIndex
    state.controllerOpenHold = state.controllerOpenHold + 1
    if state.controllerOpenHold >= CONTROLLER_OPEN_HOLD_FRAMES and not state.controllerOpenLatched then
      state.controllerOpenLatched = true
      state.controllerIndex = openIndex
      state.pointerActive = false
      state.controlMode = "controller"
      controllerOpen = true
    end
  elseif not state.open then
    state.controllerOpenHold = 0
    state.controllerOpenLatched = false
    state.controllerOpenIndex = nil
  end

  local keyboardOpen = keyTriggered(state.openKey or DEFAULT_OPEN_KEY)
  if keyboardOpen or controllerOpen then
    if state.open and keyboardOpen then
      armInputLease("keyboard", state.openKey or DEFAULT_OPEN_KEY, 0)
    end
    setMenuOpen(not state.open)
    return
  end
  if not state.open then return end

  local controllerClose = controllerRoleEvent(
    controllerCandidates(), "close", "button", CONTROLLER_OPEN_BUTTON)
  if controllerClose then
    armControllerInputLease(controllerClose)
    setMenuOpen(false)
    return
  end
  local controllerEvent = controllerMenuEvent()

  if state.inputMode == "search" then
    if editableTextTriggered() then
      state.search = captureSearchText(state.search)
      resetSelection()
    elseif keyTriggered(Keyboard.KEY_ESCAPE) or (controllerEvent and controllerEvent.role == "back") then
      state.inputMode = nil
      state.searchSelectAll = false
      state.commandSelectAll = false
    elseif keyboardEnter or (controllerEvent and controllerEvent.role == "confirm") then
      state.inputMode = nil
      state.searchSelectAll = false
      state.commandSelectAll = false
      resetSelection()
    end
    return
  elseif state.inputMode == "command" then
    if keyTriggered(Keyboard.KEY_UP) then
      recallCommandHistory(1)
    elseif keyTriggered(Keyboard.KEY_DOWN) then
      recallCommandHistory(-1)
    elseif editableTextTriggered() then
      captureCommandText()
    elseif keyTriggered(Keyboard.KEY_ESCAPE) or (controllerEvent and controllerEvent.role == "back") then
      if state.unknownCommandConfirmation then
        state.unknownCommandConfirmation = nil
      else
        state.inputMode = nil
        state.commandSelectAll = false
        clearCommandHistoryNavigation()
      end
    elseif keyboardEnter or (controllerEvent and controllerEvent.role == "confirm") then
      if controllerEvent then
        armControllerInputLease(controllerEvent)
      else
        armInputLease("keyboard", Keyboard.KEY_ENTER, 0)
      end
      queueCommand(state.manualCommand, state.repeatCount)
    elseif controllerEvent and controllerEvent.role == "repeat_decrease" then
      changeRepeat(-1)
    elseif controllerEvent and controllerEvent.role == "repeat_increase" then
      changeRepeat(1)
    end
    return
  end

  if updateControllerConfirm() then return end

  local keyboardEscape = keyTriggered(Keyboard.KEY_ESCAPE)
  if keyboardEscape or (controllerEvent and controllerEvent.role == "back") then
    if controllerEvent then
      armControllerInputLease(controllerEvent)
    else
      armInputLease("keyboard", Keyboard.KEY_ESCAPE, 0)
    end
    setMenuOpen(false)
    return
  end
  if keyTriggered(Keyboard.KEY_SLASH) then
    state.inputMode = "search"
    state.searchSelectAll = false
    state.commandSelectAll = false
    clearCommandHistoryNavigation()
    return
  end
  if keyTriggered(Keyboard.KEY_C) then
    beginCommandInput(selectedEntry(entries))
    return
  end
  if controllerEvent and (controllerEvent.role == "page_previous"
      or controllerEvent.role == "page_next") then
    local delta = controllerEvent.role == "page_previous" and -1 or 1
    if state.sidebarFocus then
      changeCategoryPage(delta)
    else
      changeEntryPage(delta, entries)
    end
    return
  end
  if controllerEvent and controllerEvent.role == "repeat_decrease" then
    changeRepeat(-1)
    return
  elseif controllerEvent and controllerEvent.role == "repeat_increase" then
    changeRepeat(1)
    return
  end
  if keyTriggered(Keyboard.KEY_F) or (controllerEvent and controllerEvent.role == "favorite") then
    toggleFavorite(selectedEntry(entries))
    return
  end
  if keyTriggered(Keyboard.KEY_D)
      or (controllerEvent and controllerEvent.role == "details") then
    Presentation.advanceDetails(entries)
    return
  end
  if keyTriggered(Keyboard.KEY_MINUS) then
    changeRepeat(-1)
    return
  end
  if keyTriggered(Keyboard.KEY_EQUAL) or keyTriggered(Keyboard.KEY_KP_ADD) then
    changeRepeat(1)
    return
  end

  local maxPage = math.max(1, math.ceil(#entries / ITEMS_PER_PAGE))
  if keyTriggered(Keyboard.KEY_PAGE_UP) then
    changeEntryPage(-1, entries)
    return
  end
  if keyTriggered(Keyboard.KEY_PAGE_DOWN) then
    changeEntryPage(1, entries)
    return
  end

  local up = keyTriggered(Keyboard.KEY_UP)
    or controllerDirectionTriggered(CONTROLLER_ACTION_UP, CONTROLLER_DPAD_UP)
  local down = keyTriggered(Keyboard.KEY_DOWN)
    or controllerDirectionTriggered(CONTROLLER_ACTION_DOWN, CONTROLLER_DPAD_DOWN)
  local left = keyTriggered(Keyboard.KEY_LEFT)
    or controllerDirectionTriggered(CONTROLLER_ACTION_LEFT, CONTROLLER_DPAD_LEFT)
  local right = keyTriggered(Keyboard.KEY_RIGHT)
    or controllerDirectionTriggered(CONTROLLER_ACTION_RIGHT, CONTROLLER_DPAD_RIGHT)
  local keyboardConfirm = keyboardEnter
  local controllerConfirm = controllerEvent and controllerEvent.role == "confirm"
  local confirm = keyboardConfirm or controllerConfirm
  if up or down or left or right or confirm then state.pointerActive = false end

  if state.sidebarFocus then
    if up then setCategory(state.categoryIndex - 1) end
    if down then setCategory(state.categoryIndex + 1) end
    if right or confirm then state.sidebarFocus = false end
    return
  end

  if left and ((state.selection - 1) % GRID_COLUMNS == 0) then state.sidebarFocus = true return end
  if left then moveGridSelection(entries, -1) end
  if right then moveGridSelection(entries, 1) end
  if up then moveGridSelection(entries, -GRID_COLUMNS) end
  if down then moveGridSelection(entries, GRID_COLUMNS) end
  local pageCount = math.min(ITEMS_PER_PAGE, math.max(0, #entries - (state.page - 1) * ITEMS_PER_PAGE))
  state.selection = clamp(state.selection, 1, math.max(1, pageCount))
  if keyboardConfirm then
    local entry = selectedEntry(entries)
    if entry then
      armInputLease("keyboard", Keyboard.KEY_ENTER, 0)
      queueEntry(entry, state.repeatCount)
    end
  elseif controllerConfirm then
    local entry = selectedEntry(entries)
    if entry then
      if entry.catalogAction and entry.catalogAction ~= "execute" then
        armControllerInputLease(controllerEvent)
        queueEntry(entry, state.repeatCount)
        return
      end
      state.controllerConfirmHold = 0
      state.controllerConfirmCommand = entry.cmd
      state.controllerConfirmRemoveCommand = removalCommand(entry)
      state.controllerConfirmRemoveMessage = removalUnavailableMessage(entry, true)
      state.controllerConfirmRepeat = state.repeatCount
      state.controllerConfirmRepeatMax = entry.repeatMax
      state.controllerConfirmSource = controllerEvent.source
      state.controllerConfirmValue = controllerEvent.value
      state.controllerConfirmIndex = controllerEvent.index or state.controllerIndex or 0
    end
  end
end

local function drawRect(x, y, width, height, color)
  pixel.Scale = Vector(width, height)
  pixel.Color = color
  pixel:Render(Vector(x, y), Vector(0, 0), Vector(0, 0))
end

local FAVORITE_STAR_SPANS = {
  { 4, 1 }, { 3, 3 }, { 0, 9 }, { 1, 7 }, { 2, 5 },
  { 2, 5 }, { 1, 2, 6, 2 }, { 0, 2, 7, 2 }, { 0, 1, 8, 1 },
}

local FAVORITE_STAR_CELLS = {}
for row, spans in ipairs(FAVORITE_STAR_SPANS) do
  FAVORITE_STAR_CELLS[row] = {}
  for index = 1, #spans, 2 do
    for column = spans[index], spans[index] + spans[index + 1] - 1 do
      FAVORITE_STAR_CELLS[row][column] = true
    end
  end
end

local function drawFavoriteStar(x, y, width, height, filled)
  local cell = 1
  local starW, starH = 9, #FAVORITE_STAR_SPANS
  local startX = math.floor(x + (width - starW) / 2)
  local startY = math.floor(y + (height - starH) / 2)
  for row, spans in ipairs(FAVORITE_STAR_SPANS) do
    for index = 1, #spans, 2 do
      drawRect(startX + spans[index] * cell - 1, startY + (row - 1) * cell - 1,
        spans[index + 1] * cell + 2, cell + 2, COLORS.panel)
    end
  end
  if filled then
    for row, spans in ipairs(FAVORITE_STAR_SPANS) do
      for index = 1, #spans, 2 do
        drawRect(startX + spans[index] * cell, startY + (row - 1) * cell,
          spans[index + 1] * cell, cell, COLORS.gold)
      end
    end
  else
    for row, columns in ipairs(FAVORITE_STAR_CELLS) do
      local previous = FAVORITE_STAR_CELLS[row - 1]
      local following = FAVORITE_STAR_CELLS[row + 1]
      for column = 0, starW - 1 do
        if columns[column] and not (previous and previous[column]
            and following and following[column]
            and columns[column - 1] and columns[column + 1]) then
          drawRect(startX + column * cell, startY + (row - 1) * cell,
            cell, cell, COLORS.favoriteOff)
        end
      end
    end
  end
end

local function drawText(value, x, y, scale, color, boxWidth, centered)
  if fontLoaded then
    -- Native bitmap rendering stays sharp. Layout spacing, truncation and
    -- dedicated detail rows handle density instead of fractional scaling.
    local selectedFont = scale >= 0.85 and font12 or font10
    local text = tostring(value)
    local width = math.floor((boxWidth or 0) + 0.5)
    if width > 0 and selectedFont:GetStringWidthUTF8(text) > width then
      local limit = math.min(#text, 96)
      local fitted = "..."
      while limit > 1 do
        local candidate = utf8sub(text, limit) .. "..."
        if selectedFont:GetStringWidthUTF8(candidate) <= width then
          fitted = candidate
          break
        end
        limit = limit - 1
      end
      text = fitted
    end
    selectedFont:DrawStringUTF8(
      text,
      math.floor(x + 0.5),
      math.floor(y + 0.5),
      color or TEXT.main,
      width,
      centered or false
    )
  else
    Isaac.RenderText(tostring(value), x, y, 1, 1, 1, 1)
  end
end

local function safeLineHeight(font, fallback)
  local ok, value = pcall(function() return font:GetLineHeight() end)
  value = ok and tonumber(value) or nil
  if not value or value <= 0 then return fallback end
  return math.max(fallback, math.floor(value + 0.5))
end

local function safeTextWidth(font, value)
  local text = tostring(value or "")
  local ok, width = pcall(function() return font:GetStringWidthUTF8(text) end)
  if ok and tonumber(width) then return math.floor(tonumber(width) + 0.5) end
  return #text * 8
end

local function fittingText(candidates, width)
  for _, value in ipairs(candidates) do
    if safeTextWidth(font10, value) <= width then return value end
  end
  return ""
end

local function fittingInputText(value, width)
  local text = tostring(value or "")
  if safeTextWidth(font10, text) <= width then return text end
  local start = math.max(1, #text - 95)
  while start <= #text do
    local candidate = "..." .. text:sub(start)
    if safeTextWidth(font10, candidate) <= width then return candidate end
    start = start + 1
  end
  return ""
end

function Presentation.fittingLeadingText(value, width)
  local text = tostring(value or "")
  if safeTextWidth(font10, text) <= width then return text end
  local limit = math.min(#text, 256)
  while limit > 0 do
    local candidate = utf8sub(text, limit) .. "..."
    if safeTextWidth(font10, candidate) <= width then return candidate end
    limit = limit - 1
  end
  return ""
end

local function resolveFooterContext(entries)
  if state.inputMode == "search" then return "search", nil end
  if state.inputMode == "command" then return "command", nil end
  if state.sidebarFocus then return "category", currentCategory() end
  local entry = selectedEntry(entries)
  if entry then return "entry", entry end
  return "empty", nil
end

local function categoryFooterText(category, greedMode, width)
  local candidates
  if category.id == "stage" and greedMode then
    candidates = {
      "Greed safe route: stage 1-7; hidden floors and suffix combinations are blocked",
      "Greed route: stages 1-7.",
      "Greed stages 1-7.",
    }
  else
    candidates = { category.desc or "", category.shortDesc or "" }
  end
  local text = fittingText(candidates, width)
  assert(text ~= "", "category description does not fit: " .. tostring(category.id))
  return text
end

local function splitUtf8(value)
  local text = tostring(value or "")
  local result = {}
  local index = 1
  while index <= #text do
    local byte = text:byte(index)
    local length = 1
    if byte >= 0xF0 then length = 4
    elseif byte >= 0xE0 then length = 3
    elseif byte >= 0xC0 then length = 2 end
    result[#result + 1] = text:sub(index, index + length - 1)
    index = index + length
  end
  return result
end

local function wrapText(value, width, maxLines)
  local lines = {}
  local current = ""
  local chars = splitUtf8(value)
  for _, char in ipairs(chars) do
    local candidate = current .. char
    if current ~= "" and safeTextWidth(font10, candidate) > width then
      lines[#lines + 1] = current
      current = char == " " and "" or char
      if #lines >= maxLines then
        current = ""
        break
      end
    else
      current = candidate
    end
  end
  if #lines < maxLines and current ~= "" then lines[#lines + 1] = current end
  return lines, #lines >= maxLines and current == ""
end

local function computeLayout(screenWidth, screenHeight)
  local line10 = safeLineHeight(font10, 16)
  local line12 = safeLineHeight(font12, line10 + 4)
  local shortSide = math.min(screenWidth, screenHeight)
  local pad = clamp(math.floor(shortSide * 0.012), 5, 12)
  local margin = clamp(math.floor(shortSide * 0.025), 8, 22)
  local panelX, panelY = margin, margin
  local panelW, panelH = screenWidth - margin * 2, screenHeight - margin * 2

  local widestCategory = math.max(
    safeTextWidth(font10, "ISAAC TOOLS"),
    safeTextWidth(font10, "CONSOLE UI")
  )
  for _, category in ipairs(Catalog.categories) do
    widestCategory = math.max(widestCategory, safeTextWidth(font10, category.name or ""))
  end
  local iconW = math.max(line10, safeTextWidth(font10, "ALL"))
  local sidebarMin = math.floor(panelW * 0.22)
  local sidebarMax = math.floor(panelW * 0.34)
  local sidebarW = clamp(widestCategory + iconW + pad * 5, sidebarMin, sidebarMax)
  local contentX = panelX + sidebarW + pad * 2
  local contentW = panelW - sidebarW - pad * 3

  local categoryHeaderH = line10 * 3 + pad * 4
  local categoryRowH = line10 + pad
  local categoryNavH = line10 + pad * 2
  local categoryTop = panelY + categoryHeaderH
  local categoryNavY = categoryTop + CATEGORIES_PER_PAGE * categoryRowH + pad

  local closeW = line10 + pad * 2
  local searchH = line10 + pad * 2
  local desiredSearchW = safeTextWidth(font10, "Search: name/alias/ID") + pad * 3
  local searchW = clamp(desiredSearchW, math.floor(contentW * 0.30), math.floor(contentW * 0.46))
  local searchX = contentX + contentW - closeW - pad - searchW
  local searchY = panelY + pad
  local closeX = contentX + contentW - closeW
  local titleH = math.max(line12, searchH)
  local headerH = titleH + line10 + pad * 4

  local footerH = line10 * 3 + pad * 5
  local footerY = panelY + panelH - footerH
  local gridY = panelY + headerH
  local gridH = math.max(1, footerY - gridY - pad)
  local gridRows = math.ceil(ITEMS_PER_PAGE / GRID_COLUMNS)
  local gap = pad
  local cardW = math.floor((contentW - gap * (GRID_COLUMNS - 1)) / GRID_COLUMNS)
  local cardH = math.floor((gridH - gap * (gridRows - 1)) / gridRows)

  local buttonH = line10 + pad * 2
  local repeatLabelW = math.max(safeTextWidth(font10, "LB/RB"), safeTextWidth(font10, "Repeat"))
  local countW = math.max(safeTextWidth(font10, "99"), line10 + pad)
  local stepW = math.max(safeTextWidth(font10, "+"), line10) + pad * 2
  local repeatW = repeatLabelW + stepW * 2 + countW + pad * 5
  local starW = 9 + pad * 2

  local layout = {
    screenWidth = screenWidth, screenHeight = screenHeight,
    line10 = line10, line12 = line12, pad = pad,
    panelX = panelX, panelY = panelY, panelW = panelW, panelH = panelH,
    sidebarW = sidebarW, contentX = contentX, contentW = contentW,
    iconW = iconW, categoryHeaderH = categoryHeaderH,
    categoryTop = categoryTop, categoryRowH = categoryRowH,
    categoryNavY = categoryNavY, categoryNavH = categoryNavH,
    searchX = searchX, searchY = searchY, searchW = searchW, searchH = searchH,
    closeX = closeX, closeW = closeW, titleH = titleH, headerH = headerH,
    footerY = footerY, footerH = footerH,
    gridY = gridY, gridH = gridH, gridRows = gridRows,
    gap = gap, cardW = cardW, cardH = cardH,
    buttonH = buttonH, repeatW = repeatW, repeatLabelW = repeatLabelW,
    countW = countW, stepW = stepW, starW = starW,
  }
  local signature = table.concat({
    screenWidth, screenHeight, line10, line12, pad, sidebarW,
    headerH, footerH, cardW, cardH
  }, ":")
  if state.layoutSignature ~= signature then
    state.layoutSignature = signature
    debugLog("measured layout " .. signature .. " content=" .. contentW .. "x" .. gridH)
  end
  return layout
end

function Presentation.effectLines(entry, width)
  return wrapText("Effect: " .. (entry.desc or "No description available"), width, 99)
end

function Presentation.advanceDetails(entries)
  if state.inputMode ~= nil or state.sidebarFocus then return false end
  local entry = selectedEntry(entries)
  if not entry then return false end
  local L = computeLayout(Isaac.GetScreenWidth(), Isaac.GetScreenHeight())
  local lines = Presentation.effectLines(entry, L.contentW - L.pad * 2)
  if #lines <= 1 then return false end
  state.detailPage = (state.detailPage % #lines) + 1
  return true
end

function Presentation.repeatLabel()
  return state.controlMode == "controller" and "LB/RB" or "Repeat"
end

function Presentation.emptyFeaturedHint()
  if state.controlMode == "controller" then return "Press X in another category to add entries" end
  if state.controlMode == "mouse" then return "Click a star in another category to add entries" end
  return "Press F in another category to add entries"
end

function Presentation.categoryHint()
  if state.controlMode == "controller" then return "Right / A: enter items" end
  if state.controlMode == "mouse" then return "Click an item to enter" end
  return "Right / Enter: enter items"
end

function Presentation.entryHintCandidates(entry, isFavorite, effectPageCount)
  local mode = state.controlMode
  local actions = {}
  local function add(value)
    if value and value ~= "" then actions[#actions + 1] = value end
  end
  local favorite
  if entry.canFavorite then
    if mode == "controller" then favorite = isFavorite and "X: unfavorite" or "X: favorite"
    elseif mode == "mouse" then favorite = isFavorite and "Click star: unfavorite" or "Click star: favorite"
    else favorite = isFavorite and "F: unfavorite" or "F: favorite" end
  end
  local details
  if effectPageCount > 1 and mode ~= "controller" then
    details = mode == "mouse" and "Click details: next" or "D: details"
  end

  if entry.catalogAction == "disabled" then
    add("Disabled")
  elseif entry.catalogAction == "manual" then
    if mode == "controller" then add("A: help"); add("C: parameters")
    elseif mode == "mouse" then
      if details then add(details); details = nil else add("Click card: help") end
      add("Click command: edit")
    else
      if details then add(details); details = nil else add("Enter: help") end
      add("C: parameters")
    end
  elseif mode == "controller" and removalCommand(entry) then
    add("A: give / hold: remove")
  elseif mode == "controller" then
    add("A: run")
  elseif mode == "mouse" and removalCommand(entry) then
    add("LMB: give"); add("RMB: remove")
  elseif mode == "mouse" then
    add("LMB: run")
  elseif removalCommand(entry) then
    add("Enter: give")
  else
    add("Enter: run")
  end
  add(details)
  add(favorite)

  local candidates = { table.concat(actions, " · ") }
  if mode == "controller" then
    local primary = entry.catalogAction == "disabled" and "Disabled"
      or (entry.catalogAction == "manual" and "A: help"
      or (removalCommand(entry) and "A: give" or "A: run"))
    candidates[#candidates + 1] = favorite and (primary .. " · " .. favorite) or primary
    candidates[#candidates + 1] = primary
  elseif mode == "keyboard" then
    if #actions > 1 then
      candidates[#candidates + 1] = table.concat(actions, " · ", 1, #actions - 1)
    end
    local compact = {}
    if entry.catalogAction == "manual" then compact[#compact + 1] = "Enter/C"
    elseif entry.catalogAction ~= "disabled" then compact[#compact + 1] = "Enter" end
    if details then compact[#compact + 1] = "D" end
    if favorite then compact[#compact + 1] = "F" end
    candidates[#candidates + 1] = table.concat(compact, "/")
  end
  if mode ~= "controller" then
    for last = #actions - 2, 1, -1 do
      candidates[#candidates + 1] = table.concat(actions, " · ", 1, last)
    end
  end
  return candidates
end

function Presentation.controllerDetailHint(effectPageCount)
  if state.controlMode == "controller" and effectPageCount > 1 then return "Y: page" end
  return nil
end

function Presentation.toastLines(toast, width)
  local primary = tostring(toast.primary or toast.message or "")
  if toast.inlineAction and toast.action and toast.action ~= "" then
    local label = primary .. ": "
    local labelW = math.min(width, safeTextWidth(font10, label))
    local actionW = math.max(1, width - labelW)
    return { label .. fittingInputText(toast.action, actionW) }
  end
  if toast.action and toast.action ~= "" then
    local action = toast.actionFit == "trailing"
      and fittingInputText(toast.action, width) or Presentation.fittingLeadingText(toast.action, width)
    return { Presentation.fittingLeadingText(primary, width), action }
  end
  local lines, truncated = wrapText(primary, width, 2)
  if truncated and #lines > 0 then
    lines[#lines] = Presentation.fittingLeadingText(lines[#lines] .. "...", width)
  end
  return lines
end

local function hit(mouse, x, y, width, height)
  return mouse.X >= x and mouse.X <= x + width and mouse.Y >= y and mouse.Y <= y + height
end

local function drawToast(screenWidth, screenHeight, hostRect)
  if state.queue and clamp(math.floor(tonumber(state.queue.total) or 1), 1, 99) > 1 then
    local queue = state.queue
    local total = clamp(math.floor(tonumber(queue.total) or 1), 1, 99)
    local done = clamp(math.floor(tonumber(queue.done) or 0), 0, total)
    if hostRect then
      local contentX = hostRect.x + 6
      local contentW = math.max(1, hostRect.width - 12)
      local lineH = clamp(safeLineHeight(font10, 10), 10, 16)
      local textY = hostRect.y + math.floor((hostRect.height - lineH) / 2)
      drawRect(hostRect.x, hostRect.y, hostRect.width, hostRect.height, COLORS.sidebar)
      drawRect(hostRect.x, hostRect.y, hostRect.width * (done / total), 2, COLORS.accent)
      drawText("Running " .. done .. "/" .. total, contentX, textY,
        0.64, TEXT.main, contentW, true)
      return
    end
    local x, width = screenWidth * 0.20, screenWidth * 0.60
    local prefix = "Running " .. done .. "/" .. total .. "  "
    local contentX, contentW = x + 6, math.max(1, width - 12)
    local prefixW = math.min(contentW, safeTextWidth(font10, prefix))
    drawRect(x, screenHeight - 28, width, 20, COLORS.panel)
    drawRect(x, screenHeight - 28, width * (done / total), 2, COLORS.accent)
    drawText(prefix, contentX, screenHeight - 24, 0.64, TEXT.main, prefixW)
    drawText(fittingInputText(queue.command, contentW - prefixW), contentX + prefixW,
      screenHeight - 24, 0.64, TEXT.main, contentW - prefixW)
  elseif state.toast and state.toastFramesRemaining > 0 then
    local maxWidth = hostRect and math.max(1, hostRect.width - 12)
      or math.max(1, math.min(screenWidth - 40, 360))
    local lines = Presentation.toastLines(state.toast, math.max(1, maxWidth - 12))
    local measuredW = 0
    for _, line in ipairs(lines) do measuredW = math.max(measuredW, safeTextWidth(font10, line)) end
    local width = hostRect and hostRect.width
      or clamp(measuredW + 12, math.min(96, maxWidth), maxWidth)
    local contentW = math.max(1, width - 12)
    -- Some official localized fonts report generous leading rather than the
    -- visible 10px glyph height. Toast spacing is capped so that one short
    -- message cannot turn into a large empty footer-covering panel.
    local lineH = clamp(safeLineHeight(font10, 10), 10, 16)
    local height = hostRect and hostRect.height or math.max(20, #lines * lineH + 8)
    local x = hostRect and hostRect.x or (screenWidth - width) / 2
    local y = hostRect and hostRect.y or screenHeight - height - 8
    drawRect(x, y, width, height, hostRect and COLORS.sidebar or COLORS.panel)
    local textY = y + math.floor((height - #lines * lineH) / 2)
    for index, line in ipairs(lines) do
      drawText(line, x + 6, textY + (index - 1) * lineH,
        0.64, Presentation.toastColors[state.toast.kind or "info"], contentW, hostRect ~= nil)
    end
  end
end

-- Measured layout: every rectangle is computed from the current render size
-- and the official bitmap font metrics before anything is drawn.
local function drawMenu(entries)
  local screenWidth = Isaac.GetScreenWidth()
  local screenHeight = Isaac.GetScreenHeight()
  local L = computeLayout(screenWidth, screenHeight)
  local greedMode = isGreedMode()
  local mouse = Isaac.WorldToScreen(Input.GetMousePosition(true))
  local mousePressed = Input.IsMouseBtnPressed(0)
  local rightPressed = Input.IsMouseBtnPressed(1)
  local clicked = mousePressed and not state.mouseDown
  local rightClicked = rightPressed and not state.rightMouseDown
  local mouseMoved = false
  if state.lastMouseX ~= nil and state.lastMouseY ~= nil then
    mouseMoved = math.abs(mouse.X - state.lastMouseX) + math.abs(mouse.Y - state.lastMouseY) >= 2
  end
  state.lastMouseX, state.lastMouseY = mouse.X, mouse.Y
  if mouseMoved or clicked or rightClicked then
    state.pointerActive = true
    state.controlMode = "mouse"
  end

  drawRect(0, 0, screenWidth, screenHeight, COLORS.overlay)
  drawRect(L.panelX + 3, L.panelY + 4, L.panelW, L.panelH, COLORS.shadow)
  drawRect(L.panelX, L.panelY, L.panelW, L.panelH, COLORS.panel)
  drawRect(L.panelX, L.panelY, L.sidebarW, L.panelH, COLORS.sidebar)
  drawRect(L.panelX, L.panelY, 3, L.panelH, COLORS.accent)

  local sideX = L.panelX + L.pad * 2
  local sideTextW = L.sidebarW - L.pad * 4
  local sideY = L.panelY + L.pad
  drawText("ISAAC TOOLS", sideX, sideY, 0.60, TEXT.accent, sideTextW)
  drawText("CONSOLE UI", sideX, sideY + L.line10 + L.pad, 0.60, TEXT.main, sideTextW)
  drawText("v" .. VERSION, sideX, sideY + (L.line10 + L.pad) * 2, 0.60, TEXT.muted, sideTextW)

  local categoryPageCount = math.max(1, math.ceil(#Catalog.categories / CATEGORIES_PER_PAGE))
  state.categoryPage = clamp(state.categoryPage, 1, categoryPageCount)
  local categoryStart = (state.categoryPage - 1) * CATEGORIES_PER_PAGE + 1
  for slot = 1, CATEGORIES_PER_PAGE do
    local index = categoryStart + slot - 1
    local category = Catalog.categories[index]
    local rowY = L.categoryTop + (slot - 1) * L.categoryRowH
    if category then
      local rowX = L.panelX + L.pad
      local rowW = L.sidebarW - L.pad * 2
      local hovered = hit(mouse, rowX, rowY, rowW, L.categoryRowH - 1)
      if index == state.categoryIndex then
        drawRect(rowX, rowY, rowW, L.categoryRowH - 1, COLORS.selected)
      elseif hovered then
        drawRect(rowX, rowY, rowW, L.categoryRowH - 1, COLORS.cardHover)
      end
      local textY = rowY + math.floor((L.categoryRowH - L.line10) / 2)
      drawText(category.icon or "?", rowX + L.pad, textY, 0.60,
        index == state.categoryIndex and TEXT.accent or TEXT.muted, L.iconW)
      drawText(category.name or "", rowX + L.pad * 2 + L.iconW, textY, 0.60, TEXT.main,
        rowW - L.iconW - L.pad * 3)
      if hovered and clicked then
        setCategory(index)
        state.sidebarFocus = true
      end
    end
  end

  local navX = L.panelX + L.pad
  local navW = L.sidebarW - L.pad * 2
  drawRect(navX, L.categoryNavY, navW, L.categoryNavH, COLORS.card)
  local navTextY = L.categoryNavY + math.floor((L.categoryNavH - L.line10) / 2)
  local arrowW = math.max(L.line10, safeTextWidth(font10, "<"),
    safeTextWidth(font10, "LT"), safeTextWidth(font10, "RT")) + L.pad * 2
  local controllerPaging = state.controlMode == "controller" and state.inputMode == nil
  local categoryPaging = controllerPaging and state.sidebarFocus
  local categoryPreviousLabel = categoryPaging and "LT" or "<"
  local categoryNextLabel = categoryPaging and "RT" or ">"
  drawRect(navX, L.categoryNavY, arrowW, L.categoryNavH, COLORS.selected)
  drawRect(navX + navW - arrowW, L.categoryNavY, arrowW, L.categoryNavH, COLORS.selected)
  drawText(categoryPreviousLabel, navX, navTextY, 0.60, TEXT.main, arrowW, true)
  drawText(state.categoryPage .. "/" .. categoryPageCount,
    navX + arrowW, navTextY, 0.60, TEXT.muted, navW - arrowW * 2, true)
  drawText(categoryNextLabel, navX + navW - arrowW, navTextY, 0.60, TEXT.main, arrowW, true)
  if clicked and hit(mouse, navX, L.categoryNavY, arrowW, L.categoryNavH) then
    changeCategoryPage(-1)
    state.sidebarFocus = true
    entries = visibleEntries()
  elseif clicked and hit(mouse, navX + navW - arrowW, L.categoryNavY, arrowW, L.categoryNavH) then
    changeCategoryPage(1)
    state.sidebarFocus = true
    entries = visibleEntries()
  end

  local category = currentCategory()
  local titleY = L.panelY + L.pad
  local titleW = math.max(1, L.searchX - L.contentX - L.pad)
  local titleText = state.search ~= "" and "Global Search" or category.name
  local titleScale = safeTextWidth(font12, titleText) <= titleW and 0.90 or 0.60
  local fittedTitle = fittingText({ titleText }, titleW)
  drawText(fittedTitle ~= "" and fittedTitle or titleText,
    L.contentX, titleY, titleScale, TEXT.main, titleW)

  drawRect(L.searchX, L.searchY, L.searchW, L.searchH,
    state.inputMode == "search" and COLORS.selected or COLORS.sidebar)
  local searchLabel
  if state.search == "" then
    searchLabel = state.inputMode == "search" and "Search: _" or "Search: name/alias/ID"
  elseif state.inputMode == "search" and state.searchSelectAll then
    searchLabel = "[" .. state.search .. "]"
  else
    searchLabel = state.search .. (state.inputMode == "search" and "_" or "")
  end
  local clearW = state.search ~= "" and (L.line10 + L.pad * 2) or 0
  searchLabel = fittingInputText(searchLabel, L.searchW - L.pad * 2 - clearW)
  drawText(searchLabel, L.searchX + L.pad, L.searchY + math.floor((L.searchH - L.line10) / 2),
    0.60, state.inputMode == "search" and TEXT.main or TEXT.muted,
    L.searchW - L.pad * 2 - clearW)
  if clearW > 0 then
    drawText("×", L.searchX + L.searchW - clearW, L.searchY + math.floor((L.searchH - L.line10) / 2),
      0.60, TEXT.accent, clearW, true)
  end
  drawText("×", L.closeX, L.searchY + math.floor((L.searchH - L.line10) / 2),
    0.60, TEXT.accent, L.closeW, true)

  if clicked and clearW > 0 and hit(mouse, L.searchX + L.searchW - clearW, L.searchY, clearW, L.searchH) then
    state.search = ""
    state.inputMode = nil
    state.searchSelectAll = false
    resetSelection()
    entries = visibleEntries()
  elseif clicked and hit(mouse, L.searchX, L.searchY, L.searchW, L.searchH) then
    state.inputMode = "search"
    state.searchSelectAll = false
  end
  if clicked and hit(mouse, L.closeX, L.searchY, L.closeW, L.searchH) then
    state.mouseDown = mousePressed
    state.rightMouseDown = rightPressed
    armInputLease("mouse", 0, 0)
    setMenuOpen(false)
    return
  end

  local maxPage = math.max(1, math.ceil(#entries / ITEMS_PER_PAGE))
  state.page = clamp(state.page, 1, maxPage)
  local pageLabel = state.page .. "/" .. maxPage .. " · " .. #entries .. " items"
  local pageArrowW = arrowW
  local pageLabelW = safeTextWidth(font10, "99/99 · 999 items") + L.pad * 2
  local pageNavW = pageArrowW * 2 + pageLabelW
  local subY = L.panelY + L.titleH + L.pad * 2
  local pageNavX = L.contentX + L.contentW - pageNavW
  local pageButtonY = subY - L.pad
  local pageButtonH = L.line10 + L.pad * 2
  local entryPaging = controllerPaging and not state.sidebarFocus
  local entryPreviousLabel = entryPaging and "LT" or "<"
  local entryNextLabel = entryPaging and "RT" or ">"
  drawRect(pageNavX, pageButtonY, pageArrowW, pageButtonH, COLORS.selected)
  drawRect(pageNavX + pageArrowW + pageLabelW, pageButtonY, pageArrowW, pageButtonH, COLORS.selected)
  drawText(entryPreviousLabel, pageNavX, subY, 0.60, TEXT.main, pageArrowW, true)
  drawText(pageLabel, pageNavX + pageArrowW, subY, 0.60, TEXT.muted, pageLabelW, true)
  drawText(entryNextLabel, pageNavX + pageArrowW + pageLabelW, subY, 0.60, TEXT.main, pageArrowW, true)
  if clicked and hit(mouse, pageNavX, pageButtonY, pageArrowW, pageButtonH) then
    changeEntryPage(-1, entries)
  elseif clicked and hit(mouse, pageNavX + pageArrowW + pageLabelW, pageButtonY, pageArrowW, pageButtonH) then
    changeEntryPage(1, entries)
  end

  local pageStart = (state.page - 1) * ITEMS_PER_PAGE
  if #entries == 0 and category.id == "featured" then
    drawText("No favorites yet", L.contentX, L.gridY + L.cardH, 0.72, TEXT.main, L.contentW, true)
    drawText(Presentation.emptyFeaturedHint(), L.contentX,
      L.gridY + L.cardH + L.line10 + L.pad, 0.60, TEXT.muted, L.contentW, true)
  end
  for localIndex = 1, ITEMS_PER_PAGE do
    local entry = entries[pageStart + localIndex]
    local column = (localIndex - 1) % GRID_COLUMNS
    local row = math.floor((localIndex - 1) / GRID_COLUMNS)
    local x = L.contentX + column * (L.cardW + L.gap)
    local y = L.gridY + row * (L.cardH + L.gap)
    if entry then
      local hovered = state.pointerActive and hit(mouse, x, y, L.cardW, L.cardH)
      local selected = not state.sidebarFocus and localIndex == state.selection
      drawRect(x, y, L.cardW, L.cardH,
        selected and COLORS.selected or (hovered and COLORS.cardHover or COLORS.card))
      local entryDisabled = entry.catalogAction == "disabled"
      drawRect(x, y, 3, L.cardH, entryDisabled and COLORS.disabled
        or (entry.tier == "S" and COLORS.accent or COLORS.gold))
      local textY = y + math.floor((L.cardH - L.line10) / 2)
      local iconX = x + L.pad
      local removeCommand = removalCommand(entry)
      local isFavorite = entry.canFavorite and entry.objectKey
        and state.favorites[entry.objectKey] == true
      local favoriteW = entry.canFavorite and L.starW or 0
      local favoriteX = x + L.cardW - favoriteW
      drawText(entry.icon or "?", iconX, textY, 0.60,
        entryDisabled and TEXT.muted or (entry.tier == "S" and TEXT.accent or TEXT.gold), L.iconW, true)
      drawText(entry.name or "", iconX + L.iconW + L.pad, textY, 0.60,
        entryDisabled and TEXT.muted or TEXT.main,
        math.max(1, favoriteX - (iconX + L.iconW + L.pad) - L.pad))
      if favoriteW > 0 then
        drawFavoriteStar(favoriteX, y, favoriteW, L.cardH, isFavorite)
      end
      if hovered then
        state.selection = localIndex
        state.sidebarFocus = false
      end
      local favoriteHovered = favoriteW > 0 and hit(mouse, favoriteX, y, favoriteW, L.cardH)
      if hovered and clicked then
        if favoriteHovered then
          toggleFavorite(entry)
        else
          armInputLease("mouse", 0, 0)
          queueEntry(entry, state.repeatCount)
        end
      elseif hovered and rightClicked then
        if removeCommand then
          armInputLease("mouse", 1, 0)
          queueCommand(removeCommand, 1)
        else
          showToast(removalUnavailableMessage(entry, false), "warning", 120)
        end
      end
    end
  end

  drawRect(L.contentX, L.footerY, L.contentW, L.footerH, COLORS.sidebar)
  local queueTotal = state.queue
    and clamp(math.floor(tonumber(state.queue.total) or 1), 1, 99) or 0
  local footerNoticeActive = state.inputMode == nil and (queueTotal > 1
    or (state.toast ~= nil and state.toastFramesRemaining > 0))
  local footerTextY = L.footerY + L.pad
  local repeatX = L.contentX + L.pad
  local repeatLabel = Presentation.repeatLabel()
  drawText(repeatLabel, repeatX, footerTextY, 0.60, TEXT.main, L.repeatLabelW)
  local minusX = repeatX + L.repeatLabelW + L.pad
  local countX = minusX + L.stepW + L.pad
  local plusX = countX + L.countW + L.pad
  drawRect(minusX, L.footerY + L.pad, L.stepW, L.buttonH, COLORS.card)
  drawText("-", minusX, footerTextY, 0.60, TEXT.main, L.stepW, true)
  drawText(tostring(state.repeatCount), countX, footerTextY, 0.60,
    state.repeatCount > 20 and TEXT.warning or TEXT.main, L.countW, true)
  drawRect(plusX, L.footerY + L.pad, L.stepW, L.buttonH, COLORS.card)
  drawText("+", plusX, footerTextY, 0.60, TEXT.accent, L.stepW, true)
  if clicked and hit(mouse, minusX, L.footerY + L.pad, L.stepW, L.buttonH) then changeRepeat(-1) end
  if clicked and hit(mouse, plusX, L.footerY + L.pad, L.stepW, L.buttonH) then changeRepeat(1) end

  local detailX = L.contentX + L.repeatW + L.pad * 2
  local detailW = math.max(1, L.contentX + L.contentW - detailX - L.pad)
  local fullDetailX = L.contentX + L.pad
  local fullDetailW = L.contentW - L.pad * 2
  local rowStep = L.line10
  local footerMode, footerTarget = resolveFooterContext(entries)
  if footerMode == "search" then
    drawText(fittingText(state.searchSelectAll and {
      "Selected: type to replace · Backspace/Delete: clear",
      "Type to replace · Backspace/Delete: clear",
    } or {
      "Name / alias / command / ID",
      "Name / alias / ID",
    }, fullDetailW), fullDetailX, footerTextY + rowStep, 0.60, TEXT.main, fullDetailW)
    local searchHint = state.controlMode == "controller"
      and fittingText({
        "Ctrl+A: select all · Enter/A: done · Esc/B: back",
        "Ctrl+A · Enter/A · Esc/B",
      }, fullDetailW)
      or fittingText({
        "Ctrl+A: select all · Enter: done · Esc: back",
        "Ctrl+A · Enter · Esc",
      }, fullDetailW)
    drawText(searchHint, fullDetailX, footerTextY + rowStep * 2,
      0.60, TEXT.muted, fullDetailW)
  elseif footerMode == "command" then
    local commandLabel = "Cmd: "
    local commandLabelW = math.min(fullDetailW, safeTextWidth(font10, commandLabel) + L.pad)
    local commandInputW = math.max(1, fullDetailW - commandLabelW)
    local commandInput = state.commandSelectAll
      and ("[" .. state.manualCommand .. "]") or (state.manualCommand .. "_")
    local commandY = footerTextY + rowStep
    drawText(commandLabel, fullDetailX, commandY, 0.60, TEXT.accent, commandLabelW)
    drawText(fittingInputText(commandInput, commandInputW), fullDetailX + commandLabelW,
      commandY, 0.60, TEXT.accent, commandInputW)
    local awaitingUnknown = state.unknownCommandConfirmation == trim(state.manualCommand)
    local commandHint = awaitingUnknown
      and fittingText({ "Unknown/third-party command: press Enter again to run once", "Unknown: press Enter again" }, fullDetailW)
      or (state.controlMode == "controller"
        and fittingText({
          "History Up/Down · Ctrl+A · Enter/A: run · Esc/B: back · LB/RB: count",
          "History ↑↓ · Ctrl+A · Enter/A · Esc/B · LB/RB",
        }, fullDetailW)
        or fittingText({
          "Up/Down history · Ctrl+A · Enter · Esc",
          "History ↑↓ · Ctrl+A · Enter · Esc",
        }, fullDetailW))
    drawText(commandHint, fullDetailX, footerTextY + rowStep * 2,
      0.60, awaitingUnknown and TEXT.warning or TEXT.muted, fullDetailW)
  elseif footerMode == "category" then
    local categoryText = categoryFooterText(footerTarget, greedMode, fullDetailW)
    drawText(categoryText, fullDetailX, footerTextY + rowStep,
      0.60, TEXT.main, fullDetailW)
    local categoryHint = Presentation.categoryHint()
    drawText(categoryHint, fullDetailX, footerTextY + rowStep * 2,
      0.60, TEXT.muted, fullDetailW)
  elseif footerMode == "entry" then
    local activeEntry = footerTarget
    local detailEntryId = activeEntry.objectKey
      or (tostring(activeEntry.kind or "") .. ":" .. tostring(activeEntry.id or activeEntry.cmd or ""))
    if state.detailEntryId ~= detailEntryId then
      state.detailEntryId = detailEntryId
      state.detailPage = 1
    end
    local effectLines = Presentation.effectLines(activeEntry, fullDetailW)
    local effectPageCount = math.max(1, #effectLines)
    state.detailPage = ((state.detailPage - 1) % effectPageCount) + 1
    local indicator = (activeEntry.descSource == "EID" and "EID · " or "")
      .. "Details " .. state.detailPage .. "/" .. effectPageCount
    local indicatorW = safeTextWidth(font10, indicator) + L.pad * 2
    -- Row 0 is shared with the repeat controls, so it only carries the page
    -- indicator. The title receives the full width on row 1.
    drawText(indicator, L.contentX + L.contentW - L.pad - indicatorW,
      footerTextY, 0.60, effectPageCount > 1 and TEXT.accent or TEXT.muted, indicatorW, true)
    local detailTitle = activeEntry.name or activeEntry.en or ""
    if activeEntry.en and activeEntry.en ~= "" and activeEntry.en ~= detailTitle then
      detailTitle = detailTitle .. " / " .. activeEntry.en
    end
    drawText(detailTitle, fullDetailX, footerTextY + rowStep, 0.60, TEXT.main, fullDetailW)
    local effectLine = effectLines[state.detailPage]
    if effectLine then
      drawText(effectLine, fullDetailX, footerTextY + rowStep * 2, 0.60, TEXT.main, fullDetailW)
    end
    local effectHitY = footerTextY + rowStep * 2
    if effectPageCount > 1 and clicked and hit(mouse, fullDetailX, effectHitY, fullDetailW, rowStep) then
      Presentation.advanceDetails(entries)
    end
    local isFavorite = state.favorites[activeEntry.objectKey] == true
    local hintCandidates = Presentation.entryHintCandidates(
      activeEntry, isFavorite, effectPageCount)
    local commandLabel = "Manual command (C): "
    local commandValue = activeEntry.displayCommand or activeEntry.cmd or ""
    local commandLabelW = safeTextWidth(font10, commandLabel)
    local desiredCommandW = commandLabelW + safeTextWidth(font10, commandValue)
    local commandW = math.min(fullDetailW, desiredCommandW)
    local commandValueW = math.max(1, commandW - commandLabelW)
    local topHintW = math.max(1,
      L.contentX + L.contentW - L.pad - indicatorW - detailX - L.pad)
    local commandHintW = math.max(1, fullDetailW - commandW - L.pad)
    local detailHint = Presentation.controllerDetailHint(effectPageCount)
    local hintW = detailHint and commandHintW or topHintW
    local hint = fittingText(hintCandidates, hintW)
    local hintOnTop = not detailHint and hint ~= ""
    if not detailHint and hint == "" then
      hintW = commandHintW
      hint = fittingText(hintCandidates, hintW)
    end
    local commandY = footerTextY + rowStep * 3
    local commandHovered = state.pointerActive
      and hit(mouse, fullDetailX, commandY, commandW, rowStep)
    local commandColor = activeEntry.catalogAction == "disabled" and TEXT.warning
      or (commandHovered and TEXT.accent or TEXT.muted)
    drawText(commandLabel, fullDetailX, commandY, 0.60,
      commandColor, commandLabelW)
    drawText(fittingInputText(commandValue, commandValueW),
      fullDetailX + commandLabelW, commandY, 0.60, commandColor, commandValueW)
    if commandHovered and clicked then beginCommandInput(activeEntry) end
    if detailHint then
      drawText(detailHint, detailX, footerTextY, 0.60, TEXT.muted, topHintW)
    end
    if hintOnTop then
      drawText(hint, detailX, footerTextY, 0.60, TEXT.muted, hintW)
    elseif hint ~= "" and hintW > L.pad then
      drawText(hint, fullDetailX + commandW + L.pad, footerTextY + rowStep * 3,
        0.60, TEXT.muted, hintW)
    end
  else
    drawText("No matching entries in this view", fullDetailX, footerTextY + rowStep,
      0.60, TEXT.warning, fullDetailW)
    drawText("Clear the search or try another term", fullDetailX, footerTextY + rowStep * 2,
      0.60, TEXT.muted, fullDetailW)
  end

  state.mouseDown = mousePressed
  state.rightMouseDown = rightPressed
  if footerNoticeActive then
    drawToast(screenWidth, screenHeight, {
      x = L.contentX, y = L.footerY, width = L.contentW, height = L.footerH,
    })
  end
end

local function onRender()
  loadState()
  local paused = Game():IsPaused()
  if paused then
    state.keyboardEnterPressed = Input.IsButtonPressed(Keyboard.KEY_ENTER, 0)
    if state.open then
      suppressEidOverlay()
      state.nativePauseSuspended = true
      clearControllerConfirm()
    end
    return
  end
  -- R is text while an editor owns focus. Everywhere else it is a game-owned
  -- lifecycle boundary, so release all overlay state before the engine starts
  -- rebuilding players and controller assignments.
  if state.inputMode == nil and restartActionPressed() then
    clearRunTransientState()
    return
  end
  local inputLeaseBlocked = inputLeaseActive()
  local blockResumeInput = state.nativePauseSuspended
  if blockResumeInput then
    state.keyboardEnterPressed = Input.IsButtonPressed(Keyboard.KEY_ENTER, 0)
    state.nativePauseSuspended = false
    state.mouseDown = Input.IsMouseBtnPressed(0)
    state.rightMouseDown = Input.IsMouseBtnPressed(1)
    local mouse = Isaac.WorldToScreen(Input.GetMousePosition(true))
    state.lastMouseX, state.lastMouseY = mouse.X, mouse.Y
    state.pointerActive = false
  end
  local inputHandled = false
  if not state.open then
    if not blockResumeInput and not inputLeaseBlocked then handleKeyboardAndController({}) end
    inputHandled = true
    if not state.open then
      drawToast(Isaac.GetScreenWidth(), Isaac.GetScreenHeight())
      return
    end
  end
  suppressEidOverlay()

  -- Building 732 runtime entries and scanning them is menu work. Deferring it
  -- keeps normal gameplay, R restarts and exits independent of the catalog.
  loadCompleteCatalog()
  local entries = resolveInitialMenuFocus(visibleEntries())
  if not inputHandled and not blockResumeInput then handleKeyboardAndController(entries) end
  if not state.open then
    drawToast(Isaac.GetScreenWidth(), Isaac.GetScreenHeight())
    return
  end
  entries = visibleEntries()
  pcall(function() Game():GetHUD():SetVisible(false) end)
  if fontLoaded then
    drawMenu(entries)
  else
    local screenWidth, screenHeight = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
    drawRect(0, 0, screenWidth, screenHeight, COLORS.overlay)
    drawRect(24, 24, math.max(320, screenWidth - 48), math.max(190, screenHeight - 48), COLORS.panel)
    Isaac.RenderText("CONSOLE UI v" .. VERSION, 48, 52, 1, 1, 1, 1)
    Isaac.RenderText("FONT LOAD FAILED - MENU DISABLED", 48, 80, 1, 0.35, 0.35, 1)
    Isaac.RenderText("Runtime: " .. (IS_REPENTANCE_PLUS and "REPENTANCE+" or "REPENTANCE"), 48, 108, 1, 1, 1, 1)
    Isaac.RenderText("See log.txt for [Console UI] details.", 48, 136, 1, 1, 1, 1)
    Isaac.RenderText("Press " .. openKeyName(state.openKey) .. " or ESC to close.", 48, 164, 1, 1, 1, 1)
  end
end

lifecycleDispatcher.dispatch = function()
  local request = state.lifecycleRequest
  lifecycleDispatcher.disarm()
  if not request then return end
  state.lifecycleRequest = nil
  state.lifecycleReceipt = { command = request.command, stableUpdates = 0 }
  state.queue = nil
  state.inputLease = nil
  -- This one-shot callback is registered only after the request, so it is
  -- appended after existing render callbacks. ExecuteCommand must remain the
  -- final operation because rewind invalidates EntityPlayer userdata at once.
  return Isaac.ExecuteCommand(request.command)
end

local function runBoundaryPending()
  local previousFrame = state.lastGameFrame
  return previousFrame ~= nil and Game():GetFrameCount() < previousFrame
end

local function onInput(_, _, inputHook, action)
  -- When the overlay neither owns the screen nor waits for a closing input to
  -- be released, it has no input authority at all. This early return is also
  -- important while the engine is constructing players: querying physical
  -- keys from MC_INPUT_ACTION during that phase can interfere with native
  -- controller assignment and create a phantom co-op player.
  if not state.open and state.inputLease == nil then return nil end
  -- Restart is a game-owned lifecycle action. It must remain visible while the
  -- overlay or a release lease is active, otherwise a controller-controlled
  -- run can enter the next run before the engine sees its reconnect input.
  if action == CONTROLLER_ACTION_RESTART and state.inputMode == nil then return nil end
  -- R, Rewind and Rerun can reset the game clock before
  -- MC_POST_GAME_STARTED. During that callback gap the previous run's overlay
  -- state must not intercept any native controller assignment or pause input.
  if runBoundaryPending() then return nil end
  if Game():IsPaused() then return nil end
  if state.inputLease ~= nil then
    if inputHook == InputHook.GET_ACTION_VALUE then return 0.0 end
    return false
  end
  if not state.open then return nil end
  if inputHook == InputHook.GET_ACTION_VALUE then return 0.0 end
  return false
end

local function onGameStarted()
  restoreEidOverlay()
  clearRunTransientState()
  state.lastGameFrame = Game():GetFrameCount()
  state.loaded = false
  state.hudWasVisible = true
  state.controllerOpenHold = 0
  state.controllerOpenLatched = false
  state.controllerOpenIndex = nil
  state.controllerIndex = nil
  clearControllerConfirm()
  clearInputLease()
  state.pointerActive = false
  state.lastMouseX = nil
  state.lastMouseY = nil
  state.controlMode = "keyboard"
  state.searchSelectAll = false
  pcall(function() Game():GetHUD():SetVisible(true) end)
  loadState()
  registerMcmSettings()
  if state.startupHintEnabled ~= false and not state.startupHintShown then
    state.startupHintShown = true
    showToast("Console UI loaded", "success", 90,
      openKeyName(state.openKey) .. " / hold L3 to open")
  end
end

local function onGameExit()
  setMenuOpen(false)
  clearRunTransientState()
  state.lifecycleReceipt = nil
  state.lastGameFrame = nil
  state.controllerOpenHold = 0
  state.controllerOpenLatched = false
  state.controllerOpenIndex = nil
  state.controllerIndex = nil
  clearControllerConfirm()
  clearInputLease()
  state.pointerActive = false
  state.lastMouseX = nil
  state.lastMouseY = nil
  state.controlMode = "keyboard"
end

ConsoleUI:AddCallback(ModCallbacks.MC_POST_RENDER, onRender)
ConsoleUI:AddCallback(ModCallbacks.MC_POST_UPDATE, onUpdate)
ConsoleUI:AddCallback(ModCallbacks.MC_INPUT_ACTION, onInput)
ConsoleUI:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, onGameStarted)
ConsoleUI:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, onGameExit)

registerMcmSettings()

if fontLoaded then
  print("[Console UI] v" .. VERSION .. " loaded; font=" .. fontKind .. "; root=" .. fontRoot)
else
  print("[Console UI] v" .. VERSION .. " loaded; UTF8 font=failed; " .. tostring(fontLoadError))
end

