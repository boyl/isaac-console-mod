scenarios.native_pause_prototype = function()
  local owned, externalPause = false, false
  local gameClock = TEST.frame
  game.GetFrameCount = function() return gameClock end
  IsaacConsoleNativePausePrototype = function(op)
    if op == 0 then owned = false
    elseif op == 1 and not externalPause then owned = true end
    TEST.paused = owned or externalPause
    return owned and not externalPause
  end
  pressKey(Keyboard.KEY_F6)
  assertTrue(state.open, "prototype did not open menu")
  assertTrue(owned and TEST.paused, "opening did not acquire pause")
  local startClock = game:GetFrameCount()
  for _ = 1, 120 do renderFrame() end
  assertEqual(game:GetFrameCount(), startClock, "game clock advanced while paused")
  assertEqual(state.nativePauseSuspended, false, "owned pause suspended menu")
  state.search = "sacred heart"
  renderFrame()
  assertTrue(#visibleEntries() > 0, "search stopped working while paused")
  state.closeAfterRegularCommand = false
  assertTrue(queueCommand("giveitem c182", 1), "paused command rejected")
  renderFrame()
  assertEqual(TEST.executed[#TEST.executed], "giveitem c182", "paused queue never dispatched")
  assertEqual(state.queue, nil, "paused queue did not finish")
  assertEqual(game:GetFrameCount(), startClock, "command advanced game clock")
  local beforeBatch = #TEST.executed
  assertTrue(queueCommand("giveitem c1", 3), "paused batch rejected")
  for _ = 1, 30 do renderFrame() end
  assertEqual(#TEST.executed - beforeBatch, 3, "paused batch did not dispatch all commands")
  assertEqual(state.queue, nil, "paused batch stalled")
  assertEqual(game:GetFrameCount(), startClock, "batch advanced game clock")
  externalPause = true
  renderFrame()
  assertTrue(state.nativePauseSuspended, "external pause did not suspend menu")
  externalPause = false
  renderFrame()
  assertEqual(state.nativePauseSuspended, false, "menu did not resume after external pause")
  state.search = ""
  pressKey(Keyboard.KEY_F6)
  assertEqual(state.open, false, "prototype menu did not close")
  assertEqual(owned, false, "closing did not release pause")
  assertEqual(TEST.paused, false, "world remained paused after close")
  renderFrame()
  pressKey(Keyboard.KEY_F6)
  state.closeAfterRegularCommand = true
  assertTrue(queueCommand("giveitem c1", 1), "close-after command rejected")
  assertEqual(state.open, false, "close-after policy changed")
  onUpdate()
  assertEqual(TEST.executed[#TEST.executed], "giveitem c1", "clock change stalled close-after command")
  assertEqual(state.queue, nil, "close-after queue remained pending")
  IsaacConsoleNativePausePrototype = nil
end
