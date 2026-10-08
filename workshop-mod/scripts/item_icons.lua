-- 物品图标 View：只解析/缓存/绘制资源，不改变命令或目录。
local ItemIcons = {}
local CACHE_LIMIT = 128
-- 原生普通胶囊颜色 1..13；金胶囊没有固定效果，不参与反查。
local PILL_NAMES = {'blue-blue', 'white-blue', 'orange-orange', 'white-white',
  'dots-red', 'pink-red', 'blue-cadetblue', 'yellow-orange', 'dots-white',
  'white-azure', 'black-yellow', 'white-black', 'white-yellow'}

local function validId(objectType, id)
  if type(id) ~= 'number' or id ~= math.floor(id) then return false end
  local maximum = ({c = CollectibleType.NUM_COLLECTIBLES, t = TrinketType.NUM_TRINKETS,
    k = Card.NUM_CARDS, p = PillEffect.NUM_PILL_EFFECTS})[objectType]
  return maximum ~= nil and id >= (objectType == 'p' and 0 or 1) and id < maximum
end

function ItemIcons.new(getConfig, log, pillContext)
  local self = {cache = {}, failed = {}, size = 0, clock = 0, loads = 0, failures = 0}

  pillContext = pillContext or function()
    local game = Game()
    return game:GetFrameCount(), game:GetItemPool(), Isaac.GetPlayer(0)
  end

  function self:resetPills()
    self.pillFrame, self.pillMap = nil, nil
  end

  function self:pillColor(effect)
    local ok, color = pcall(function()
      local frame, pool, player = pillContext()
      if frame ~= self.pillFrame or not self.pillMap then
        local map = {}
        for candidate = 1, #PILL_NAMES do
          local value = pool:GetPillEffect(candidate, player)
          if validId('p', value) and not map[value] then map[value] = candidate end
        end
        self.pillFrame, self.pillMap = frame, map
      end
      return self.pillMap[effect] or 1
    end)
    if not ok then
      if not self.pillDiagnostic then log('pill color lookup unavailable: ' .. tostring(color)); self.pillDiagnostic = true end
      return 1
    end
    return color
  end

  function self:isItem(entry)
    return entry.kind == 'item' and (entry.objectType == 'c' or entry.objectType == 't'
      or entry.objectType == 'k' or entry.objectType == 'p')
  end

  function self:fail(key, message)
    if not self.failed[key] then
      self.failed[key] = message
      self.failures = self.failures + 1
      log('item icon unavailable ' .. key .. ': ' .. tostring(message))
    end
    return nil, message
  end

  function self:get(entry)
    if not self:isItem(entry) then return nil, 'text' end
    local objectType, id = entry.objectType, entry.id
    if not validId(objectType, id) then return self:fail('invalid', 'invalid item type/ID') end
    local pillColor = objectType == 'p' and self:pillColor(id) or nil
    local key = objectType .. ':' .. tostring(id)
    if pillColor then key = 'pill-color:' .. tostring(pillColor) end
    if self.failed[key] then return nil, self.failed[key] end
    self.clock = self.clock + 1
    local cached = self.cache[key]
    if cached then cached.used = self.clock; return cached end

    -- 游戏 API/资源属于外部边界。失败缓存不持有 Sprite，键域限定为收录 ID。
    local ok, icon = pcall(function()
      local sprite, animation, frame = Sprite(), 'Icon', 0
      local width, height, maxScale = 32, 32, 1
      if objectType == 'c' or objectType == 't' then
        local config = getConfig()
        local item = config and (objectType == 'c' and config:GetCollectible(id) or nil)
        if objectType == 't' and config then item = config:GetTrinket(id) end
        if not item or type(item.GfxFileName) ~= 'string' or item.GfxFileName == '' then
          error('missing ItemConfig texture')
        end
        sprite:Load('gfx/ui/isaac_console_item.anm2', false)
        if not sprite:IsLoaded() then error('item animation not loaded') end
        sprite:ReplaceSpritesheet(0, item.GfxFileName)
        sprite:LoadGraphics()
      elseif objectType == 'k' then
        if id > 97 then error('card ID not present in verified animation') end
        sprite:Load('gfx/ui/isaac_console_cards.anm2', false)
        if not sprite:IsLoaded() then error('card animation not loaded') end
        sprite:ReplaceSpritesheet(0, 'gfx/ui/ui_cardfronts.png')
        sprite:ReplaceSpritesheet(1, 'gfx/ui/ui_cardspills.png')
        sprite:LoadGraphics()
        animation, frame = 'Cards', id - 1
        maxScale = 8
        -- 卡面为 16x24，符文/魂石 HUD 为 32x32；按实际可见边界缩放。
        local hud = (id >= 32 and id <= 41) or id == 55 or id == 78 or id >= 81
        if not hud then width, height = 16, 24 end
      else
        -- 只反查当前池，不强制加入效果或识别药丸；未分配时默认蓝蓝。
        sprite:Load(string.format('gfx/005.%03d_pill %s.anm2', 70 + pillColor, PILL_NAMES[pillColor]), true)
        if not sprite:IsLoaded() then error('pill animation not loaded') end
        animation = 'HUD'
      end
      sprite:SetFrame(animation, frame)
      if sprite:GetAnimation() ~= animation or sprite:GetFrame() ~= frame then
        error('animation/frame selection failed')
      end
      return {sprite = sprite, width = width, height = height, maxScale = maxScale, used = self.clock}
    end)
    if not ok then return self:fail(key, tostring(icon)) end
    if self.size == CACHE_LIMIT then
      local oldestKey, oldestTime
      for candidate, value in pairs(self.cache) do
        if not oldestTime or value.used < oldestTime then oldestKey, oldestTime = candidate, value.used end
      end
      self.cache[oldestKey] = nil
      self.size = self.size - 1
    end
    self.cache[key] = icon
    self.size = self.size + 1
    self.loads = self.loads + 1
    return icon
  end

  function self:draw(entry, rect)
    local icon, err = self:get(entry)
    if not icon then return false, err end
    local scale = math.min(rect.maxScale or icon.maxScale, rect.w / icon.width, rect.h / icon.height)
    icon.sprite.Scale = Vector(scale, scale)
    icon.sprite.Color = Color(1, 1, 1, 1, 0, 0, 0)
    icon.sprite:Render(Vector(math.floor(rect.x + rect.w / 2), math.floor(rect.y + rect.h / 2)))
    return true
  end

  function self:stats()
    return {size = self.size, loads = self.loads, failures = self.failures}
  end
  return self
end

return ItemIcons
