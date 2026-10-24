-- 目录物品的地面生成边界；药丸和手动命令不进入此路径。
local Pedestals = {}
local types = {
  c = { variant = 100, config = "GetCollectible" },
  t = { variant = 350, config = "GetTrinket" },
  k = { variant = 300, config = "GetCard" },
}

function Pedestals.supports(entry, enabled)
  return enabled == true and entry ~= nil and entry.kind == "item" and types[entry.objectType] ~= nil
end

function Pedestals.request(entry, enabled)
  if not Pedestals.supports(entry, enabled) then return nil end
  return { objectType = entry.objectType, id = tonumber(entry.id), variant = types[entry.objectType].variant }
end

local function distanceSquared(a, b)
  return (a.X - b.X)^2 + (a.Y - b.Y)^2
end

function Pedestals.spawn(request)
  local spec = types[request.objectType]
  assert(spec and request.variant == spec.variant, "invalid ground pickup request")
  local config = Isaac.GetItemConfig()
  if not config[spec.config](config, request.id) then return false, "invalid_item" end
  local game = Game()
  local room = game:GetRoom()
  local players = {}
  for index = 0, game:GetNumPlayers() - 1 do players[#players + 1] = Isaac.GetPlayer(index) end
  if #players == 0 then return false, "no_player" end
  local origin = players[1].Position
  local pickups = Isaac.FindByType(EntityType.ENTITY_PICKUP, -1, -1, false, false)
  local function available(pos)
    if not room:IsPositionInRoom(pos, 20)
        or room:GetGridCollisionAtPos(pos) ~= GridCollisionClass.COLLISION_NONE then return false end
    for _, player in ipairs(players) do
      if distanceSquared(pos, player.Position) < math.max(48, player.Size + 24)^2 then return false end
    end
    for _, pickup in ipairs(pickups) do
      if distanceSquared(pos, pickup.Position) < math.max(40, pickup.Size + 20)^2 then return false end
    end
    return true
  end
  -- 此 API 找不到空位时会返回原位置，因此返回值必须再校验。
  local pos = room:FindFreePickupSpawnPosition(Vector(origin.X + 64, origin.Y), 0, true, false)
  if not available(pos) then
    pos = nil
    local nearestDistance
    for index = 0, room:GetGridSize() - 1 do
      local candidate = room:GetGridPosition(index)
      local distance = distanceSquared(candidate, origin)
      if (not nearestDistance or distance < nearestDistance) and available(candidate) then
        pos, nearestDistance = candidate, distance
      end
    end
  end
  if not pos then return false, "no_space" end
  local seed = Random()
  if seed == 0 then seed = 1 end
  local entity = game:Spawn(EntityType.ENTITY_PICKUP, request.variant,
    pos, Vector(0, 0), nil, request.id, seed)
  local pickup = entity and entity:ToPickup()
  if not pickup then return false, "spawn_failed" end
  pickup.AutoUpdatePrice = false
  pickup.Price = 0
  if request.objectType == "c" then
    pickup.ShopItemId = -1
    pickup.OptionsPickupIndex = 0
  end
  return true
end

return Pedestals
