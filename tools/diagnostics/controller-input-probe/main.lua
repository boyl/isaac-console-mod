-- 临时只读输入探针：不拦截输入、不执行命令、不读写存档。
local probe = RegisterMod("Console Input Probe", 1)
local startedAt, previousPlayers = nil, nil
local lastSamples, emitted = {}, 0
local actions = {}
for name, value in pairs(ButtonAction or {}) do
  if type(name) == "string" and name:match("^ACTION_") and type(value) == "number" then
    actions[#actions + 1] = { name = name, value = value }
  end
end
table.sort(actions, function(a, b) return a.name < b.name end)
local function log(message)
  Isaac.DebugString("[Console Input Probe] " .. message)
end
local enumNames = {}
for _, action in ipairs(actions) do
  enumNames[#enumNames + 1] = action.name .. "=" .. action.value
end
log("loaded; repPlus=" .. tostring(REPENTANCE_PLUS) .. "; " .. table.concat(enumNames, ","))
if type(Input.GetKeyboardDeviceId) == "function" then
  local ok, value = pcall(Input.GetKeyboardDeviceId)
  log("keyboardDeviceId=" .. tostring(value) .. "; ok=" .. tostring(ok))
else
  log("keyboardDeviceId=unavailable")
end
probe:AddCallback(ModCallbacks.MC_POST_RENDER, function()
  if not startedAt then startedAt = Isaac.GetTime() end
  if Isaac.GetTime() - startedAt > 600000 or emitted >= 600 then return end
  local game = Game()
  local count = game:GetNumPlayers()
  -- 同时观察玩家索引及相邻查询索引，用来识别 J514 的索引偏移。
  local indices, players = {[-2] = true, [0] = true, [1] = true, [2] = true}, {}
  for playerIndex = 0, count - 1 do
    local player = Isaac.GetPlayer(playerIndex)
    if player then
      indices[player.ControllerIndex] = true
      players[#players + 1] = playerIndex .. ":" .. player.ControllerIndex
    end
  end
  local playerSignature = tostring(count) .. " [" .. table.concat(players, ",") .. "]"
  if previousPlayers ~= playerSignature then
    log("players=" .. playerSignature .. "; frame=" .. game:GetFrameCount())
    previousPlayers = playerSignature
  end
  -- 只读诊断额外观察相邻设备；正式菜单仍只接受已分配玩家的设备。
  for index in pairs(indices) do
    if index >= -2 and index < 8 then
      local buttons, pressedActions = {}, {}
      for button = 0, 31 do
        if Input.IsButtonPressed(button, index) then buttons[#buttons + 1] = tostring(button) end
      end
      for _, button in ipairs({65, 256, 257, 258, 259, 262, 263, 264, 265, 295}) do
        if Input.IsButtonPressed(button, index) then buttons[#buttons + 1] = tostring(button) end
      end
      for _, action in ipairs(actions) do
        if Input.IsActionPressed(action.value, index) then
          pressedActions[#pressedActions + 1] = action.name .. "=" .. action.value
        end
      end
      local signature = "raw=" .. table.concat(buttons, ",")
        .. "; actions=" .. table.concat(pressedActions, ",")
      if lastSamples[index] ~= signature then
        lastSamples[index] = signature
        emitted = emitted + 1
        log("index=" .. index .. "; " .. signature .. "; paused=" .. tostring(game:IsPaused()))
      end
    end
  end
end)
