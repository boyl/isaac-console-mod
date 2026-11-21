-- Read-only, bounded probe. Never included in Workshop candidates.
local probe = RegisterMod("Console keyboard route diagnostic", 1)
local keys = {Keyboard.KEY_F6, Keyboard.KEY_ENTER, Keyboard.KEY_ESCAPE, Keyboard.KEY_A, Keyboard.KEY_LEFT_CONTROL}
local indices = {-2, -1, 0, 1, 2, 3}
local previous, count = {}, 0
probe:AddCallback(ModCallbacks.MC_POST_RENDER, function()
  if count >= 100 then return end
  for _, key in ipairs(keys) do
    for _, index in ipairs(indices) do
      local ok, value = pcall(Input.IsButtonPressed, key, index)
      local id = tostring(key) .. ":" .. tostring(index)
      local down = ok and value == true
      if down ~= (previous[id] or false) then
        Isaac.DebugString("[ConsoleKeyboardProbe] key=" .. key .. " index=" .. index .. " pressed=" .. tostring(down))
        count = count + 1
      end
      previous[id] = down
    end
  end
end)
