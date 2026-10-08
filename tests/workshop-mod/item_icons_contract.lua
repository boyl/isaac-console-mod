-- 图标资源边界契约；独立于游戏，不把模拟结果当作实机证据。
local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local loads, logs, renders, replacements = 0, {}, {}, {}
local forceFailure = false
function Vector(x, y) return {X = x, Y = y} end
function Color(r, g, b, a) return {r, g, b, a} end
CollectibleType = {NUM_COLLECTIBLES = 733}
TrinketType = {NUM_TRINKETS = 190}
Card = {NUM_CARDS = 98}
PillEffect = {NUM_PILL_EFFECTS = 50}
function Sprite()
  local sprite = {}
  function sprite:Load(path)
    loads = loads + 1
    self.path = path
    self.loaded = not forceFailure
  end
  function sprite:IsLoaded() return self.loaded end
  function sprite:ReplaceSpritesheet(layer, path)
    replacements[#replacements + 1] = {layer, path}
  end
  function sprite:LoadGraphics() end
  function sprite:SetFrame(animation, frame) self.animation, self.frame = animation, frame end
  function sprite:GetAnimation() return self.animation end
  function sprite:GetFrame() return self.frame end
  function sprite:Render(position) renders[#renders + 1] = {sprite = self, position = position} end
  return sprite
end
local configCalls = 0
local config = {}
function config:GetCollectible(id)
  configCalls = configCalls + 1
  if id == 43 then return nil end
  return {GfxFileName = 'gfx/items/collectibles/' .. id .. '.png'}
end
function config:GetTrinket(id)
  configCalls = configCalls + 1
  return {GfxFileName = 'gfx/items/trinkets/' .. id .. '.png'}
end
local module = dofile(MOD_ROOT .. '/scripts/item_icons.lua')
local pillFrame, pillCalls, pillMap = 1, 0, {}
local pillPool = {}
function pillPool:GetPillEffect(color, player)
  pillCalls = pillCalls + 1
  check(player == 'player0', 'pill lookup lost player context')
  return pillMap[color] or -1
end
local icons = module.new(function() return config end, function(message) logs[#logs + 1] = message end,
  function() return pillFrame, pillPool, 'player0' end)
local function entry(kind, id) return {kind = 'item', objectType = kind, id = id} end
local function get(kind, id)
  local icon, err = icons:get(entry(kind, id))
  check(icon ~= nil, kind .. tostring(id) .. ': ' .. tostring(err))
  return icon
end
check(icons:draw(entry('k',1), {x=10,y=20,w=32,h=40}), 'card draw failed')
local cardDraw = renders[#renders]
check(cardDraw.sprite.Scale.X == 40/24, 'card did not fill slot using actual 16x24 bounds')
check(get('k',32).width == 32, 'rune must retain native HUD bounds')
check(icons:draw(entry('k',1), {x=0,y=0,w=64,h=72}), 'large card slot')
check(renders[#renders].sprite.Scale.X == 3, 'card still limited to old small size')
for _, kind in ipairs({'c', 't', 'p'}) do
  check(icons:draw(entry(kind, kind == 'p' and 0 or 1), {x=0,y=0,w=96,h=96,maxScale=8}), 'Rep large slot draw')
  check(renders[#renders].sprite.Scale.X == 3, 'Rep icon remained at native size: ' .. kind)
  check(icons:draw(entry(kind, kind == 'p' and 0 or 1), {x=0,y=0,w=32,h=32}), 'unchanged native slot')
  check(renders[#renders].sprite.Scale.X == 1, 'normal runtime icon changed: ' .. kind)
end
local c = get('c', 182)
check(replacements[#replacements][2] == 'gfx/items/collectibles/182.png', 'wrong collectible texture')
check(c.width == 32 and c.height == 32, 'collectible bounds')
get('t', 182)
check(replacements[#replacements][2] == 'gfx/items/trinkets/182.png', 'type/ID collision')
for id = 1, 97 do
  local k = get('k', id)
  check(k.sprite.animation == 'Cards' and k.sprite.frame == id - 1, 'card animation frame ' .. id)
end
for id = 0, 49 do
  local p = get('p', id)
  check(p.sprite.animation == 'HUD' and p.sprite.frame == 0, 'effect ID used as pill color')
  check(p.sprite.path == 'gfx/005.071_pill blue-blue.anm2', 'pill default path')
end
check(pillCalls == 13, 'pill map recomputed within frame')
pillMap[2], pillMap[5], pillFrame = 7, 0, 2
check(get('p',7).sprite.path == 'gfx/005.072_pill white-blue.anm2', 'effect did not resolve actual color')
check(get('p',0).sprite.path == 'gfx/005.075_pill dots-red.anm2', 'effect zero confused with color')
pillMap, pillFrame = {[13]=7}, 3
check(get('p',7).sprite.path == 'gfx/005.083_pill white-yellow.anm2', 'mapping change reused stale appearance')
check(get('p',0).sprite.path == 'gfx/005.071_pill blue-blue.anm2', 'unassigned effect did not use default')
pillMap = {[3]=7}
icons:resetPills()
check(get('p',7).sprite.path == 'gfx/005.073_pill orange-orange.anm2', 'new run reused stale map')
check(icons:stats().size <= 128, 'cache bound after all pocket items')
for id = 1, 300 do if id ~= 43 then get('c', id) end end
check(icons:stats().size == 128, 'cache bound')
local before = loads
get('c', 300)
get('c', 300)
check(loads == before, 'cache hit reload')
get('c', 1)
check(loads == before + 1, 'evicted icon did not reload')
before = loads
for _ = 1, 10 do icons:get(entry('c', 43)) end
check(#logs == 1, 'missing config logged repeatedly')
check(loads == before, 'missing config loaded a sprite')
forceFailure = true
for _ = 1, 10 do icons:get(entry('c', 501)) end
check(#logs == 2 and loads == before + 1, 'load failure retried or repeatedly logged')
forceFailure = false
check(icons:get(entry('c', 501)) == nil, 'failed resource was silently retried')
for _, invalid in ipairs({-1, 0, 733, 1.5}) do
  check(icons:get(entry('c', invalid)) == nil, 'invalid collectible accepted')
end
check(icons:get(entry('p', 50)) == nil, 'invalid effect accepted')
check(not icons:isItem({kind = 'custom_command', id = 182}), 'command treated as item')
check(icons:draw({kind = 'custom_command', id = 182}, {x=0,y=0,w=32,h=32}) == false,
  'command drew a sprite')
check(icons:draw(entry('c',182), {x=10,y=20,w=32,h=40}), 'icon draw failed')
local rendered = renders[#renders]
check(rendered.position.X == 26 and rendered.position.Y == 40, 'icon not centered')
check(rendered.sprite.Scale.X == rendered.sprite.Scale.Y, 'aspect ratio')
check(rendered.sprite.Color[1] == 1 and rendered.sprite.Color[4] == 1, 'icon tinted')
check(icons:draw(entry('c',182), {x=0,y=0,w=12,h=16}), 'small icon draw')
check(renders[#renders].sprite.Scale.X <= 12/32, 'icon exceeds slot')
print('ICON CONTRACT PASS; assertions=' .. checks .. '; loads=' .. loads .. '; failures=' .. #logs)
