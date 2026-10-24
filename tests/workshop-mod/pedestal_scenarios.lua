-- 真实 main.lua 队列、设置、持久化与 API 边界的确定性集成测试。
return function(c)
  local eq, ok = c.assertEqual, c.assertTrue
  local state, test = c.state, c.TEST
  c.game.IsPauseMenuOpen = function() return false end
  c.onStarted()
  eq(state.pedestalEnabled, TEST_CONFIG.initialSave == "pedestalEnabled=1\n", "default / legacy save")
  c.openMenu()
  local setting
  for _, entry in ipairs(c.settings.entries) do
    if entry.settingId == "pedestal" then setting = entry end
  end
  ok(setting, "pedestal setting missing")
  c.settings.refreshEntries()
  ok(c.contains(setting.name, TEST_CONFIG.language == "zh" and "地面生成（含底座）" or "Ground Spawn (incl. Pedestals)"), "setting wording")
  ok(c.contains(setting.desc, TEST_CONFIG.language == "zh" and "药丸不受影响" or "Pills are unaffected"), "pill exclusion explained")
  ok(c.settings.applySetting("pedestal", false), "disable")
  TEST_CONFIG.saveFail = true
  eq(c.queueEntry(setting, 1), false, "failed save must reject toggle")
  eq(state.pedestalEnabled, false, "failed save must roll back")
  TEST_CONFIG.saveFail = false
  ok(c.queueEntry(setting, 1), "enable")
  ok(c.contains(test.saveData, "pedestalEnabled=1\n"), "persist toggle")
  c.onStarted()
  eq(state.pedestalEnabled, true, "reload toggle")
  c.openMenu()
  state.closeAfterRegularCommand = false

  local spawned, blocked, spawnFailure = {}, false, false
  local player = { Position = Vector(120, 120), Size = 12, ControllerIndex = 0 }
  Isaac.GetPlayer = function() return player end
  EntityType = { ENTITY_PICKUP = 5 }
  PickupVariant = { PICKUP_COLLECTIBLE = 100, PICKUP_TAROTCARD = 300, PICKUP_TRINKET = 350 }
  GridCollisionClass = { COLLISION_NONE = 0 }
  Random = function() return 0 end -- 零种子必须被替换。
  Isaac.FindByType = function() return spawned end
  local room = {}
  function room:GetGridSize() return 100 end
  function room:GetGridPosition(i) return Vector((i % 10) * 40, math.floor(i / 10) * 40) end
  function room:IsPositionInRoom(p, margin) return p.X >= 40 and p.X <= 320 and p.Y >= 40 and p.Y <= 320 end
  function room:GetGridCollisionAtPos(p) return (blocked or (p.X == 160 and p.Y == 120)) and 1 or 0 end
  function room:FindFreePickupSpawnPosition(p) return p end -- 包含 API 无空间返回原位的情况。
  function c.game:GetRoom() return room end
  function c.game:Spawn(kind, variant, pos, vel, spawner, subtype, seed)
    if spawnFailure then error("injected spawn failure") end
    eq(kind, 5, "pickup type")
    ok(variant == 100 or variant == 300 or variant == 350, "supported pickup variant")
    ok(seed ~= 0, "nonzero seed")
    ok((pos.X-player.Position.X)^2+(pos.Y-player.Position.Y)^2 >= 48^2, "avoid player")
    eq(room:GetGridCollisionAtPos(pos), 0, "avoid obstacles")
    for _, prior in ipairs(spawned) do
      ok((pos.X-prior.Position.X)^2+(pos.Y-prior.Position.Y)^2 >= 40^2, "avoid overlap")
    end
    local pickup = { Position=pos, Size=20, SubType=subtype, Type=kind, Variant=variant, Wait=20 }
    function pickup:ToPickup() return self end
    spawned[#spawned+1] = pickup
    return pickup
  end
  local function drain()
    local frames = 0
    while state.queue and frames < 1000 do
      test.frame = test.frame + 8
      c.onUpdate()
      frames = frames + 1
    end
    ok(not state.queue, "queue finishes")
  end
  local item = c.findObject("c:182")
  for _, mode in ipairs({"keyboard", "mouse", "controller"}) do
    state.controlMode = mode
    ok(c.contains(c.presentation.entryHintCandidates(item, false, 1)[1], TEST_CONFIG.language == "zh" and "生成" or "spawn"), "spawn hint: " .. mode)
    ok(c.contains(c.presentation.entryHintCandidates(c.findObject("c:18"), false, 1)[1], TEST_CONFIG.language == "zh" and "生成" or "spawn"), "non-removable collectible spawn hint: " .. mode)
  end
  for _, id in ipairs({182, 105, 8}) do -- 被动、主动、跟班。
    ok(c.queueEntry(c.findObject("c:" .. id), 1), "collectible queue")
    drain()
    eq(spawned[#spawned].SubType, id, "selected subtype")
    eq(spawned[#spawned].Price, 0, "free pedestal")
    eq(spawned[#spawned].ShopItemId, -1, "reroll identity")
    eq(spawned[#spawned].OptionsPickupIndex, 0, "independent pedestal")
    eq(spawned[#spawned].AutoUpdatePrice, false, "no shop repricing")
    eq(spawned[#spawned].Wait, 20, "keep pickup delay")
  end
  eq(#test.executed, 0, "spawn must not give")
  ok(c.contains(state.history[1], "spawn 5.100.8"), "history records spawn, not give")

  local before = #spawned
  ok(c.queueEntry(item, 3), "batch")
  ok(c.settings.applySetting("pedestal", false), "toggle during queued batch")
  drain()
  eq(#spawned, before + 3, "batch keeps snapshot")
  c.onUpdate(); c.onUpdate()
  eq(#spawned, before + 3, "completed queue not replayed")
  ok(c.queueEntry(item, 2), "off gives")
  ok(c.settings.applySetting("pedestal", true), "enable during give batch")
  drain()
  eq(test.executed[#test.executed], "giveitem c182", "give batch keeps snapshot")
  eq(#spawned, before + 3, "give batch not converted")

  for _, key in ipairs({"p:1"}) do
    local entry = c.findObject(key)
    ok(c.queueEntry(entry, 1), "other item queue")
    drain(); eq(test.executed[#test.executed], entry.cmd, "other item unchanged")
  end
  ok(c.queueCommand("giveitem c182", 1), "manual queue"); drain()
  eq(test.executed[#test.executed], "giveitem c182", "manual unchanged")
  ok(c.queueEntry({kind="custom_command", cmd="giveitem c182", rawPassthrough=true}, 1), "custom queue"); drain()
  eq(test.executed[#test.executed], "giveitem c182", "custom unchanged")
  ok(c.queueCommand(c.removalCommand(item), 1), "remove queue"); drain()
  eq(test.executed[#test.executed], "remove c182", "remove unchanged")
  eq(#spawned, before + 3, "other commands do not spawn/delete")

  state.search = "sacred heart"
  local found
  for _, entry in ipairs(c.visibleEntries()) do if entry.objectKey == "c:182" then found=entry end end
  ok(found, "search finds item"); ok(c.queueEntry(found, 1), "search spawn"); drain()
  state.search = ""
  c.toggleFavorite(item)
  c.setCategory(c.categories.featured.index)
  found = nil
  for _, entry in ipairs(c.visibleEntries()) do if entry.objectKey == "c:182" then found=entry end end
  ok(found, "favorite finds item"); ok(c.queueEntry(found, 1), "favorite spawn"); drain()
  -- 收藏索引保存原始 entry，不复制/改写 cmd。
  eq(item.cmd, "giveitem c182", "catalog command remains stable")
  before = #spawned
  ok(c.queueEntry(item, 99), "large batch")
  eq(state.queue.total, 99, "existing upper bound")
  c.onUpdate()
  blocked = true
  drain()
  eq(#spawned, before+1, "no-space stops after completed items")
  ok(c.contains(state.toast.primary, "1/99"), "partial count visible")
  blocked = false
  spawnFailure = true
  ok(c.queueEntry(item, 1), "failure queue"); drain()
  ok(c.contains(state.toast.primary, "0/1"), "API failure does not count success")
  spawnFailure = false
  ok(c.settings.applySetting("pedestal", false), "persist off")
  c.onStarted()
  eq(state.pedestalEnabled, false, "off survives reload")
  c.openMenu()
  state.closeAfterRegularCommand = false
  c.setCategory(c.categories.input_settings.index)
  state.page, state.selection, state.sidebarFocus = 2, 3, false
  c.pressKey(Keyboard.KEY_ENTER)
  eq(state.pedestalEnabled, true, "keyboard toggles setting")
  c.pressButton(Controller.BUTTON_A)
  c.renderFrame()
  eq(state.pedestalEnabled, false, "controller toggles setting")
  local layout = c.computeLayout(Isaac.GetScreenWidth(), Isaac.GetScreenHeight())
  c.clickMouse(layout.contentX + 8, layout.gridY + layout.cardH + layout.gap + 8, 0)
  eq(state.pedestalEnabled, true, "mouse toggles setting")
  spawned = {}
  state.search = "sacred heart"
  state.page, state.selection, state.sidebarFocus = 1, 1, false
  c.pressKey(Keyboard.KEY_ENTER); drain()
  eq(#spawned, 1, "keyboard executes spawn")
  c.pressButton(Controller.BUTTON_A); c.renderFrame(); drain()
  eq(#spawned, 2, "controller executes spawn")
  c.clickMouse(layout.contentX + 8, layout.gridY + 8, 0); drain()
  eq(#spawned, 3, "mouse executes spawn")
  c.clickMouse(layout.contentX + 8, layout.gridY + 8, 1); drain()
  eq(test.executed[#test.executed], "remove c182", "right click still removes owned item")
  eq(#spawned, 3, "right click does not delete pedestal")
  c.startHeldButton(Controller.BUTTON_A)
  c.holdButton(Controller.BUTTON_A, 31)
  c.releaseButton(Controller.BUTTON_A)
  drain()
  eq(test.executed[#test.executed], "remove c182", "long A still removes owned item")
  eq(#spawned, 3, "long A does not create/delete pedestal")
  -- 暂停时更新时钟冻结，仅 Render 前进；再触发 Update 也不得重复执行。
  local oldFrame = c.game.GetFrameCount
  c.game.GetFrameCount = function() return 1 end
  IsaacConsoleNativePausePrototype = function() return true end
  test.paused = true
  ok(c.queueEntry(item, 3), "paused spawn batch")
  eq(state.queue.renderClock, true, "paused batch uses render clock")
  for _ = 1, 30 do c.renderFrame() end
  eq(#spawned, 6, "paused batch completes")
  c.onUpdate(); c.renderFrame()
  eq(#spawned, 6, "paused duplicate dispatch prevented")
  test.paused = false
  IsaacConsoleNativePausePrototype = nil
  c.game.GetFrameCount = oldFrame

  -- 新增范围：原生卡槽与饰品槽不应被地面生成路径触碰。
  player.AddCard = function() error("ground generation touched card slot") end
  player.SetCard = player.AddCard
  player.AddTrinket = function() error("ground generation touched trinket slot") end
  local executedBefore = #test.executed
  local checkedTypes = 0
  for _, spec in ipairs({{kind="k", maximum=97, variant=300}, {kind="t", maximum=189, variant=350}}) do
    for id = 1, spec.maximum do
      local entry = c.findObject(spec.kind .. ":" .. id)
      if entry then
        checkedTypes = checkedTypes + 1
        spawned = {}
        ok(c.queueEntry(entry, 99), "ground queue " .. entry.objectKey)
        eq(state.queue.total, 1, "retain single-item cap")
        drain()
        eq(#spawned, 1, "exactly one ground pickup: " .. entry.objectKey)
        eq(spawned[1].Variant, spec.variant, "ground variant")
        eq(spawned[1].SubType, id, "ground subtype")
        eq(spawned[1].ShopItemId, nil, "no collectible reroll attributes on pocket items")
        eq(#test.executed, executedBefore, "no give-then-drop")
        ok(c.contains(state.history[1], "spawn 5." .. spec.variant .. "." .. id), "typed spawn history")
      end
    end
  end
  eq(checkedTypes, 97 + 188, "all supported cards/runes/souls and trinkets covered")
  for _, key in ipairs({"k:1", "k:32", "k:81", "t:1"}) do
    c.openMenu()
    local entry = c.findObject(key)
    spawned = {}
    state.search = entry.cmd
    state.page, state.selection, state.sidebarFocus = 1, 1, false
    for _, mode in ipairs({"keyboard", "mouse", "controller"}) do
      state.controlMode = mode
      ok(c.contains(c.presentation.entryHintCandidates(entry, false, 1)[1], TEST_CONFIG.language == "zh" and "生成" or "spawn"), "typed spawn hint")
    end
    c.pressKey(Keyboard.KEY_ENTER); drain()
    c.pressButton(Controller.BUTTON_A); c.renderFrame(); drain()
    c.clickMouse(layout.contentX + 8, layout.gridY + 8, 0); drain()
    eq(#spawned, 3, "three devices spawn pocket items")
    eq(#test.executed, executedBefore, "input never gives pocket item")
    state.search = ""
    c.toggleFavorite(entry)
    c.setCategory(c.categories.featured.index)
    local favorite
    for _, value in ipairs(c.visibleEntries()) do if value.objectKey == key then favorite=value end end
    ok(favorite, "typed favorite present")
    ok(c.queueEntry(favorite, 1), "favorite ground queue"); drain()
    eq(#spawned, 4, "favorite spawns pocket item")
  end
  for _, enabled in ipairs({false, true}) do
    ok(c.settings.applySetting("pedestal", enabled), "toggle for pills")
    ok(c.queueEntry(c.findObject("p:1"), 1), "pill queue"); drain()
    eq(test.executed[#test.executed], "giveitem p1", "pill unaffected in both modes")
  end
  ok(c.settings.applySetting("pedestal", false), "disable ground mode")
  for _, key in ipairs({"t:1", "k:1", "k:32", "k:81"}) do
    local entry = c.findObject(key)
    ok(c.queueEntry(entry, 1), "off queue"); drain()
    eq(test.executed[#test.executed], entry.cmd, "off still gives original item")
  end
  ok(c.settings.applySetting("pedestal", true), "enable for raw commands")
  ok(c.queueCommand("giveitem k1", 1), "manual card command"); drain()
  eq(test.executed[#test.executed], "giveitem k1", "manual card unchanged")
  ok(c.queueEntry({kind="custom_command",cmd="giveitem t1",rawPassthrough=true},1), "custom trinket"); drain()
  eq(test.executed[#test.executed], "giveitem t1", "custom trinket unchanged")
  local beforeFailure = #test.executed
  blocked = true
  spawned = {}
  ok(c.queueEntry(c.findObject("k:1"), 1), "no-space card queue"); drain()
  eq(#spawned, 0, "no-space generates nothing")
  eq(#test.executed, beforeFailure, "no-space must not fall back to give")
  ok(c.contains(state.toast.primary, "0/1"), "no-space count")
end
