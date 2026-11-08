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
probe:AddCallback(ModCallbacks.MC_POST_RENDER, function()
  if not startedAt then startedAt = Isaac.GetTime() end
  if Isaac.GetTime() - startedAt > 600000 or emitted >= 600 then return end
  local game = Game()
  local count = game:GetNumPlayers()
  local indices, players = {}, {}
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
  -- 只采样已分配给玩家的手柄；不在 MC_INPUT_ACTION 内递归查询输入。
  for index in pairs(indices) do
    if index >= 0 then
      local buttons, pressedActions = {}, {}
      for button = 0, 31 do
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
