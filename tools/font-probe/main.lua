-- 高清字形实机门禁：独立样板，无 SaveData、命令执行或游戏设置写入。
local probe = RegisterMod("Isaac Console HD Font Probe", 1)
local visible, attempted, failure = false, false, nil
local fonts = {}
local roles = {"title", "body", "caption"}
local root = "mods/isaac_console_hd_font_probe/resources/hd/"
local background = Sprite()
background:Load("gfx/ui/isaac_hd_probe_pixel.anm2", true)
background:Play("Idle", true)
local function log(value) Isaac.DebugString("[HD Font Probe] " .. value) end
local function load()
  if attempted then return end
  attempted = true
  for _, role in ipairs(roles) do
    local font = Font()
    local ok, err = pcall(function()
      font:Load(root .. "hd_" .. role .. ".fnt")
      assert(font:IsLoaded(), "IsLoaded=false")
      assert(font:GetStringWidthUTF8("中文ABC") > 0, "invalid width")
      assert(font:GetLineHeight() > 0, "invalid line height")
    end)
    if not ok then failure = role .. ": " .. tostring(err); log("FAIL " .. failure); return end
    fonts[role] = font
    log(role .. " loaded; line=" .. font:GetLineHeight() .. "; width=" .. font:GetStringWidthUTF8("中文ABC"))
  end
  log("READY; scale=0.5; game=" .. Isaac.GetScreenWidth() .. "x" .. Isaac.GetScreenHeight())
end
local function text(role, value, x, y, color)
  fonts[role]:DrawStringScaledUTF8(value, x, y, 0.5, 0.5, color or KColor(1,1,1,1), 0, false)
end
probe:AddCallback(ModCallbacks.MC_POST_RENDER, function()
  if Input.IsButtonTriggered(Keyboard.KEY_F8, 0) then
    visible = not visible
    if visible then load() end
    log(visible and "SHOW" or "HIDE")
  end
  if not visible then return end
  if failure then Isaac.RenderText("HD FONT PROBE FAILED - see log; F8 closes", 20,20,1,0.3,0.3,1); return end
  local w, h = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
  background.Scale = Vector(w - 24, h - 24)
  background.Color = Color(0.055,0.065,0.085,0.98)
  background:Render(Vector(12,12))
  text("title", "高清字体样板 · HD FONT", 24, 18)
  text("body", "复杂笔画：鬱 龍 警 懒 惧 魔 魂", 24, 51)
  text("body", "道具名称：悲伤洋葱 / The Sad Onion", 24, 79)
  text("caption", "命令 giveitem c1   ABCDE abcde 0123456789", 24, 110)
  text("caption", "说明：提高射速；长说明按可用宽度换行。", 24, 134)
  text("caption", "不会执行命令、改变存档或修改游戏设置。", 24, 158)
  text("caption", "F8 关闭样板 / Close preview", 24, 190)
end)
log("loaded; press F8 in a safe room")
