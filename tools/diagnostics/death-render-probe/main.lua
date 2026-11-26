-- 隔离死亡绘制/重开测试；仅 T1MM AY48 种子响应 F8/F10/F11，不写 SaveData。
local probe = RegisterMod("Death render isolated diagnostic", 1)
local active, tick, restartUntil, restartCalls = false, 0, nil, 0
local shaderFrames, lastShaderFrame = 0, -1
local function log(text) Isaac.DebugString("[DeathRenderProbe] " .. text) end
probe:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
  active = Game():GetSeeds():GetStartSeedString():gsub(" ", "") == "T1MMAY48"
  restartUntil = nil
  log("START active=" .. tostring(active) .. " continued=" .. tostring(continued))
  log("NATIVE pause=" .. tostring(type(IsaacConsoleNativePausePrototype) == "function")
    .. " death=" .. tostring(type(IsaacConsoleNativeDeathOverlay) == "function"))
end)
probe:AddCallback(ModCallbacks.MC_POST_GAME_END, function(_, gameOver)
  if active then log("END gameOver=" .. tostring(gameOver)) end
end)
probe:AddCallback(ModCallbacks.MC_POST_RENDER, function()
  tick = tick + 1
  -- F9 显式进入固定种子测试局，不在加载时自动执行。
  if Input.IsButtonTriggered(Keyboard.KEY_F9, 0) then
    log("ENTER isolated seed via F9")
    return Isaac.ExecuteCommand("seed T1MM AY48")
  end
  if not active then return end
  if Input.IsButtonTriggered(Keyboard.KEY_F7, 0) and not Isaac.GetPlayer(0):IsDead() then
    log("DEATH requested via TakeDamage; no spawn command")
    local player = Isaac.GetPlayer(0)
    player:TakeDamage(99, 0, EntityRef(player), 0)
  end
  if Input.IsButtonTriggered(Keyboard.KEY_F8, 0) and not Isaac.GetPlayer(0):IsDead() then
    log("DEATH requested via Kill; no spawn command")
    Isaac.GetPlayer(0):Kill()
  end
  if Input.IsButtonTriggered(Keyboard.KEY_F10, 0) or Input.IsButtonTriggered(Keyboard.KEY_F11, 0) then
    local duration = Input.IsButtonTriggered(Keyboard.KEY_F11, 0) and 240 or 50
    restartUntil, restartCalls = tick + duration, 0
    log("RESTART hold_render_frames=" .. duration)
  end
  if restartUntil and tick >= restartUntil then
    log("RESTART released input_queries=" .. restartCalls)
    restartUntil = nil
  end
  if tick % 60 == 0 then
    log("FRAME tick=" .. tick .. " game=" .. Game():GetFrameCount() .. " dead=" .. tostring(Isaac.GetPlayer(0):IsDead()) .. " shader_frames=" .. shaderFrames)
  end
end)
probe:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, _, hook, action)
  if not active or not restartUntil or action ~= ButtonAction.ACTION_RESTART then return end
  restartCalls = restartCalls + 1
  if hook == InputHook.GET_ACTION_VALUE then return 1 end
  if hook == InputHook.IS_ACTION_PRESSED then return true end
end)
probe:AddCallback(ModCallbacks.MC_GET_SHADER_PARAMS, function(_, name)
  if name ~= "DeathRenderProbe" then return end
  if lastShaderFrame ~= Isaac.GetFrameCount() then
    shaderFrames, lastShaderFrame = shaderFrames + 1, Isaac.GetFrameCount()
  end
  if active and Isaac.GetPlayer(0):IsDead() then
    -- 对照标记，不调用原生组件；用于观察是否真正晚于遗书绘制。
    Isaac.RenderText("LUA LATE DRAW / NO NATIVE LEASE", 100, 140, 1, 0, 0, 1)
  end
  return nil
end)
