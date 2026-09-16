-- Run against the real bilingual Mod through mock_game_harness.lua.
return function(env)
  local T, config, state = env.TEST, env.config, env.state
  local eq, yes = env.assertEqual, env.assertTrue
  local settings = env.InputSettingsUI
  local function cursorPixels()
    local records = {}
    for _, record in ipairs(T.spriteRecords) do
      local c = record.color or {}
      if c[4] == 1 and ((c[1] == 0 and c[2] == 0 and c[3] == 0)
          or (c[1] == 1 and c[2] == 1 and c[3] == 1)) then
        records[#records + 1] = record
      end
    end
    return records
  end
  local function capture(callback)
    T.captureGeometry = true
    T.spriteRecords, T.renderRecords = {}, {}
    if callback then callback() else env.renderFrame() end
    return cursorPixels()
  end
  local function absent(label, callback)
    eq(#capture(callback), 0, label .. ": cursor should be absent")
  end
  local function present(label, callback)
    local pixels = capture(callback)
    yes(#pixels > 0, label .. ": cursor missing")
    eq(pixels[1].x, T.mousePosition.X, label .. ": tip X differs from hit-test coordinate")
    eq(pixels[1].y, T.mousePosition.Y, label .. ": tip Y differs from hit-test coordinate")
    local black, white = false, false
    for _, pixel in ipairs(pixels) do
      yes(pixel.x >= T.mousePosition.X and pixel.x + pixel.width <= T.mousePosition.X + 9,
        label .. ": cursor exceeds its horizontal footprint")
      yes(pixel.y >= T.mousePosition.Y and pixel.y + pixel.height <= T.mousePosition.Y + 13,
        label .. ": cursor exceeds its vertical footprint")
      if pixel.color[1] == 0 then black = true else white = true end
    end
    yes(black and white, label .. ": cursor needs an opaque outline and fill")
    eq(T.spriteRecords[#T.spriteRecords], pixels[#pixels], label .. ": cursor is not the final sprite layer")
    return pixels
  end
  local function persistedWithoutCursor(payload)
    return payload:gsub("fullscreenCursorEnabled=[^\n]*\n", "")
  end

  env.onStarted()
  eq(state.fullscreenCursorEnabled, true, "fresh install must enable the cursor")
  local savesBefore = T.saveAttempts
  T.gameOptions.Fullscreen = true
  absent("closed fullscreen menu")
  eq(T.saveAttempts, savesBefore, "render-only check wrote SaveData")
  env.openMenu()
  T.mousePosition = Vector(71.5, 63.5)
  present("initial fullscreen")
  T.gameOptions.Fullscreen = false
  absent("windowed")
  T.gameOptions.Fullscreen = true
  T.gameOptions.MouseControl = true
  T.gameOptions.UseBorderlessFullscreen = true
  present("borderless fullscreen with game mouse controls")
  eq(Options.MouseControl, true, "cursor changed mouse controls")

  -- Simulate a non-identity room-to-screen transform; both rendering and hit
  -- testing must consume the same converted coordinate, not the raw mouse.
  local worldToScreen = Isaac.WorldToScreen
  Isaac.WorldToScreen = function(value) return Vector(value.X + 17, value.Y + 23) end
  local transformed = capture()
  yes(#transformed > 0, "transformed cursor missing")
  eq(transformed[1].x, T.mousePosition.X + 17, "cursor bypassed WorldToScreen X")
  eq(transformed[1].y, T.mousePosition.Y + 23, "cursor bypassed WorldToScreen Y")
  Isaac.WorldToScreen = worldToScreen

  if config.fontMode == "all_fail" then
    yes(table.concat(T.rendered, "|"):find("FONT LOAD FAILED", 1, true), "font fallback page missing")
    env.pressKey(Keyboard.KEY_ESCAPE)
    absent("font fallback closed")
    return
  end

  -- Missing field in a previous version must enable the feature without
  -- discarding unrelated data or writing merely because a menu was opened.
  T.saveData = "version=2.5.20\nfavoriteOrder=recent\nfavorites=c:182\nhistory=debug 12"
  env.onStarted()
  eq(state.fullscreenCursorEnabled, true, "old save must enable the cursor")
  yes(state.favorites["c:182"], "old favorite was lost")
  eq(state.history[1], "debug 12", "old command history was lost")
  env.openMenu()
  env.CustomCommandUI.beginEdit(nil)
  state.customDraftCommand = "debug 13"
  yes(env.CustomCommandUI.submitEdit(), "custom command setup failed")
  state.customDraftName = "Cursor regression"
  yes(env.CustomCommandUI.submitEdit(), "custom name setup failed")
  local previousData = persistedWithoutCursor(T.saveData)

  env.setCategory(env.categoryById.input_settings.index)
  local entries = env.visibleEntries()
  eq(#entries, 10, "settings include cursor and optional HD font")
  eq(entries[9].id, "fullscreen_cursor_toggle", "existing setting order changed")
  eq(entries[9].name, env.IS_ZH and "全屏光标：开启" or "Fullscreen Cursor: On", "enabled state missing from card title")
  state.sidebarFocus = false
  state.page, state.selection = 1, 1
  env.pressKey(Keyboard.KEY_PAGE_DOWN)
  eq(state.page, 2, "keyboard cannot reach the new settings page")
  eq(state.selection, 1, "new page must select the cursor setting")
  env.pressKey(Keyboard.KEY_ENTER)
  eq(state.fullscreenCursorEnabled, false, "Enter did not disable the cursor")
  eq(env.visibleEntries()[9].name, env.IS_ZH and "全屏光标：关闭" or "Fullscreen Cursor: Off", "disabled title did not refresh")
  absent("disabled fullscreen")
  eq(persistedWithoutCursor(T.saveData), previousData, "cursor toggle changed unrelated save fields")
  yes(T.saveData:find("fullscreenCursorEnabled=0\n", 1, true), "disabled state was not saved")

  env.onStarted()
  eq(state.fullscreenCursorEnabled, false, "disabled state did not survive restart")
  yes(state.favorites["c:182"], "cursor setting lost a favorite")
  eq(state.history[1], "debug 12", "cursor setting lost history")
  eq(state.customCommands:find(1).command, "debug 13", "cursor setting lost a custom command")
  env.openMenu()
  env.setCategory(env.categoryById.input_settings.index)
  state.sidebarFocus, state.page, state.selection = false, 2, 1
  local layout = env.computeLayout(Isaac.GetScreenWidth(), Isaac.GetScreenHeight())
  local commandsBefore = #T.executed
  env.clickMouse(layout.contentX + layout.cardW / 2, layout.gridY + layout.cardH / 2)
  eq(state.fullscreenCursorEnabled, true, "mouse cannot toggle the second-page setting")
  eq(#T.executed, commandsBefore, "setting click executed a game command")
  present("mouse-enabled setting")

  -- Both settings surfaces read and write the same state, including errors.
  local mcmCursor
  if config.mcm then
    eq(T.mcmAddCalls, 6, "MCM must register each of six settings once")
    for _, setting in ipairs(T.mcmSettings) do
      if setting.Display and setting.Display():find(env.IS_ZH and "全屏控制台光标" or "Fullscreen console cursor", 1, true) then
        mcmCursor = setting
      end
    end
    yes(mcmCursor ~= nil, "MCM cursor mirror missing")
    eq(mcmCursor.CurrentSetting(), true, "MCM ignored the built-in change")
    mcmCursor.OnChange(false)
    eq(state.fullscreenCursorEnabled, false, "MCM change did not reach the built-in state")
    yes(env.visibleEntries()[9].desc:find(env.IS_ZH and "关闭" or "Off", 1, true), "built-in description is stale")
    mcmCursor.OnChange(true)
  end
  local payloadBeforeFailure = T.saveData
  T.configWasSaveFail = config.saveFail
  config.saveFail = true
  local ok = settings.applySetting("fullscreen_cursor", false)
  eq(ok, false, "failed save was reported as successful")
  eq(state.fullscreenCursorEnabled, true, "failed save did not restore the previous value")
  eq(env.visibleEntries()[9].name, env.IS_ZH and "全屏光标：开启" or "Fullscreen Cursor: On", "failed save left a stale title")
  eq(T.saveData, payloadBeforeFailure, "failed save corrupted the previous payload")
  if mcmCursor then
    mcmCursor.OnChange(false)
    eq(mcmCursor.CurrentSetting(), true, "failed MCM change did not roll back")
    yes(state.toast and state.toast.kind == "error", "MCM save failure was not visible")
  end
  config.saveFail = T.configWasSaveFail
  eq(settings.applySetting("fullscreen_cursor", "false"), false, "non-boolean value accepted")
  present("failed save retains visible cursor")

  -- Controller navigation changes focus, while drawing a stationary cursor
  -- must not restore mouse focus or alter the selected entry.
  env.setCategory(2)
  state.sidebarFocus, state.page, state.selection = false, 1, 1
  T.mousePosition = Vector(layout.contentX + 5, layout.gridY + 5)
  env.renderFrame()
  env.pressDirection(ButtonAction.ACTION_MENUDOWN, Controller.DPAD_DOWN, config.controllerIndex, true)
  local selected = state.selection
  present("controller-owned menu")
  eq(state.selection, selected, "stationary cursor stole the selection")
  eq(state.controlMode, "controller", "cursor rendering changed the input device")
  eq(state.pointerActive, false, "cursor rendering acquired pointer focus")

  -- Showing or hiding a purely visual cursor must not change input answers.
  for _, enabled in ipairs({false, true}) do
    state.fullscreenCursorEnabled = enabled
    eq(env.onInput(nil, nil, InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_JOINMULTIPLAYER), 0,
      "open-menu input interception changed")
  end
  T.paused = true
  absent("native pause")
  eq(env.onInput(nil, nil, InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_JOINMULTIPLAYER), nil,
    "paused menu kept input authority")
  T.paused = false
  present("resume")
  env.pressKey(Keyboard.KEY_ESCAPE)
  absent("closed menu")
  eq(env.onInput(nil, nil, InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_JOINMULTIPLAYER), nil,
    "closed menu retained input authority")
  env.openMenu()
  T.actionPressed[ButtonAction.ACTION_RESTART] = { [config.controllerIndex] = true }
  absent("R restart boundary")
  T.actionPressed[ButtonAction.ACTION_RESTART] = nil
  eq(state.open, false, "R restart did not close the overlay")
  env.onStarted()
  env.openMenu()
  present("new run")
  env.onGameEnd(nil, true)
  T.paused = true
  env.pressKey(Keyboard.KEY_F6)
  eq(state.open, true, "Game Over did not reopen the console")
  absent("Game Over ordinary render")
  absent("unrelated shader", function() env.runShaderCallbacks("OtherShader") end)
  present("Game Over late surface", function() env.runShaderCallbacks("IsaacConsoleLateOverlay") end)
  absent("same-frame duplicate shader", function() env.runShaderCallbacks("IsaacConsoleLateOverlay") end)
  env.pressKey(Keyboard.KEY_ESCAPE)
  absent("closed Game Over surface", function() env.runShaderCallbacks("IsaacConsoleLateOverlay") end)
  T.paused = false
  env.onExit()
  absent("exit")
  eq(Options.Fullscreen, true, "Mod changed fullscreen state")
  eq(Options.MouseControl, true, "Mod changed gameplay mouse controls")
  eq(Options.UseBorderlessFullscreen, true, "Mod changed fullscreen mode")
end
