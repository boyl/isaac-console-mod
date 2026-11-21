-- Physical keyboard routing. J510 moved the keyboard to -2; older runtimes
-- use 0. Do not scan player slots: raw gamepad buttons alias key % 32.
local KeyboardInput = {}
local routes = (REPENTANCE_PLUS or FontRenderSettings ~= nil) and {-2, 0} or {0}

local function read(method, key)
  if type(key) ~= "number" or key < 32 or type(Input[method]) ~= "function" then return false end
  for _, index in ipairs(routes) do
    local ok, down = pcall(Input[method], key, index)
    if ok and down == true then
      local aliasOk, aliasDown = pcall(Input[method], key % 32, index)
      if aliasOk and aliasDown ~= true then return true end
    end
  end
  return false
end

function KeyboardInput.triggered(key) return read("IsButtonTriggered", key) end
function KeyboardInput.pressed(key) return read("IsButtonPressed", key) end

return KeyboardInput
