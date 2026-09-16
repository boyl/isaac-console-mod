-- 字体服务：经典对象原样保留，高清按需加载；绘制与测量共享缺字分段。
local Typography = {}

local function characters(text)
  local result, i = {}, 1
  while i <= #text do
    local a = text:byte(i)
    local n = a < 128 and 1 or (a < 224 and 2 or (a < 240 and 3 or 4))
    local cp = a % (n == 1 and 256 or 2 ^ (7 - n))
    for j = 1, n - 1 do cp = cp * 64 + (text:byte(i + j) or 128) % 64 end
    result[#result + 1] = {text:sub(i, i + n - 1), cp}
    i = i + n
  end
  return result
end

function Typography.new(options)
  local self = {classic = {body = options.body, title = options.title, caption = options.body},
    active = false, attempted = false, failure = nil, fonts = {}}
  function self:enable(enabled)
    if not enabled then self.active = false; return true end
    if not self.attempted then
      self.attempted = true
      local ok, err = pcall(function()
        local coverage = options.coverage()
        assert(type(coverage) == "table" and coverage[65] == true and coverage[20013] == true,
          "font coverage metadata missing")
        for _, role in ipairs({"title", "body", "caption"}) do
          local raw = Font()
          raw:Load(options.root .. "hd_" .. role .. ".fnt")
          assert(raw:IsLoaded(), role .. " font missing")
          local line = raw:GetLineHeight() * 0.5
          local width = raw:GetStringWidthUTF8("中文ABC")
          assert(line > 0 and line < 100 and width > 0 and width < 1000,
            role .. " invalid metrics")
          assert(type(raw.DrawStringScaledUTF8) == "function", "scaled font drawing unavailable")
          local fallback = self.classic[role]
          local proxy = {}
          local function runs(value)
            local result = {}
            for _, char in ipairs(characters(tostring(value or ""))) do
              local hd = coverage[char[2]] == true
              local last = result[#result]
              if last and last.hd == hd then last.text = last.text .. char[1]
              else result[#result + 1] = {hd = hd, text = char[1]} end
            end
            return result
          end
          local function runWidth(run)
            return run.hd and raw:GetStringWidthUTF8(run.text) * 0.5
              or fallback:GetStringWidthUTF8(run.text)
          end
          function proxy:GetStringWidthUTF8(value)
            local total = 0
            for _, run in ipairs(runs(value)) do total = total + runWidth(run) end
            return total
          end
          function proxy:GetLineHeight() return fallback:GetLineHeight() end
          function proxy:DrawStringUTF8(value, x, y, color, boxWidth, centered)
            local segments = runs(value)
            if (boxWidth or 0) > 0 then
              local delta = boxWidth - self:GetStringWidthUTF8(value)
              x = x + (centered and delta / 2 or delta)
            end
            for _, run in ipairs(segments) do
              if run.hd then raw:DrawStringScaledUTF8(run.text, x, y, 0.5, 0.5, color, 0, false)
              else
                local offset = 0
                fallback:DrawStringUTF8(run.text, x, y + offset, color, 0, false)
              end
              x = x + runWidth(run)
            end
          end
          self.fonts[role] = proxy
          options.log("HD font " .. role .. "; line=" .. line .. "; width=" .. width / 2)
        end
      end)
      if not ok then self.failure = tostring(err); options.log("HD fallback: " .. self.failure) end
    end
    self.active = self.failure == nil
    return self.active, self.failure
  end
  function self:get(role) return (self.active and self.fonts or self.classic)[role] end
  function self:wrap(value, width, maxLines, role)
    local font, lines, current = self:get(role or "body"), {}, ""
    local chars = characters(tostring(value or ""))
    for index, char in ipairs(chars) do
      if char[1] == "\n" or (current ~= "" and font:GetStringWidthUTF8(current .. char[1]) > width) then
        lines[#lines + 1] = current
        if #lines >= maxLines then return lines, true end
        current = (char[1] == "\n" or char[1] == " ") and "" or char[1]
      else current = current .. char[1] end
    end
    if current ~= "" then lines[#lines + 1] = current end
    return lines, false
  end
  return self
end

return Typography
