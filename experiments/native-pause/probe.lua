-- 实验包独有的观测回调：不修改道具、房间或存档。
do
  Presentation.nativePauseProbeSamples = 0
  ChineseConsole:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    Presentation.nativePauseProbeSamples = Presentation.nativePauseProbeSamples + 1
    if Presentation.nativePauseProbeSamples % 60 == 0 and type(IsaacConsoleNativePausePrototype) == "function" then
      Isaac.DebugString("[NativePauseProbe] render=" .. Isaac.GetFrameCount()
        .. " game=" .. Game():GetFrameCount() .. " paused=" .. tostring(Game():IsPaused())
        .. " owned=" .. tostring(IsaacConsoleNativePausePrototype(2)))
    end
  end)
end
