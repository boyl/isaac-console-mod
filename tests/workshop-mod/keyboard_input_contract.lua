local count = 0
local function check(value, label)
  assert(value, label); count = count + 1
end
for _, route in ipairs({0, -2}) do
  REPENTANCE_PLUS = route == -2
  local keyboardDown, gamepadDown, negativeThrows = false, false, false
  local function sample(key, index)
    if negativeThrows and index < 0 then error("unsupported index") end
    if index == route and keyboardDown and key == 295 then return true end
    if index == 0 and gamepadDown and (key == 295 or key == 295 % 32) then return true end
    return false
  end
  Input = {IsButtonTriggered = sample, IsButtonPressed = sample}
  local adapter = dofile(MOD_ROOT .. "/scripts/keyboard_input.lua")
  for _, method in ipairs({"triggered", "pressed"}) do
    check(not adapter[method](295), "idle key")
    keyboardDown = true
    check(adapter[method](295), "physical F6 route " .. route)
    keyboardDown = false; gamepadDown = true
    check(not adapter[method](295), "gamepad alias opened keyboard UI")
    gamepadDown = false
    check(not adapter[method](295), "release retained input")
    check(not adapter[method](nil), "missing optional key")
    if route == 0 then
      REPENTANCE_PLUS = true
      adapter = dofile(MOD_ROOT .. "/scripts/keyboard_input.lua")
      negativeThrows = true; keyboardDown = true
      check(adapter[method](295), "legacy negative index error blocked keyboard")
      negativeThrows = false; keyboardDown = false
    end
  end
end
print("KEYBOARD_CONTRACT_PASS assertions=" .. count)
