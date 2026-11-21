-- 只读、限量实机取证；不执行命令，不写存档，不进入发布包。
local probe = RegisterMod("J510 acceptance diagnostic", 1)
local keys = {}
for key = 32, 348 do keys[#keys + 1] = key end
local samples, events, previous = 0, 0, {}
local previousPlayers
probe:AddCallback(ModCallbacks.MC_POST_RENDER, function()
  samples = samples + 1
  local players = {}
  for i = 0, Game():GetNumPlayers() - 1 do players[#players + 1] = tostring(Isaac.GetPlayer(i).ControllerIndex) end
  local playerSignature = table.concat(players, ",")
  if playerSignature ~= previousPlayers then
    Isaac.DebugString("[J510AcceptancePlayers] indices=" .. playerSignature)
    previousPlayers = playerSignature
  end
  if samples % 60 == 0 and samples <= 36000 then
    local owned = type(IsaacConsoleNativePausePrototype) == "function" and IsaacConsoleNativePausePrototype(2)
    Isaac.DebugString("[J510Acceptance] render=" .. Isaac.GetFrameCount() .. " game=" .. Game():GetFrameCount()
      .. " paused=" .. tostring(Game():IsPaused()) .. " owned=" .. tostring(owned))
  end
  if events >= 300 then return end
  for _, key in ipairs(keys) do
    for _, index in ipairs({-2, -1, 0}) do
      local id = key .. ":" .. index
      local down = Input.IsButtonPressed(key, index)
      if down ~= (previous[id] or false) then
        Isaac.DebugString("[J510AcceptanceKey] key=" .. key .. " index=" .. index .. " down=" .. tostring(down)
          .. " trigger=" .. tostring(Input.IsButtonTriggered(key, index))
          .. " alias=" .. tostring(Input.IsButtonPressed(key % 32, index)))
        previous[id] = down
        events = events + 1
      end
    end
  end
end)
