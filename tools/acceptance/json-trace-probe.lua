-- 临时诊断探针：只记录 JSON 解码失败的长度与调用栈，保留原返回值和异常。
-- 仅作为独立临时 Mod 部署；不进入控制台候选包，完成诊断后移除。
local json = require("json")
local original = json.decode
local reported = false
json.decode = function(value, startPos)
  local ok, decoded, endPos = pcall(original, value, startPos)
  if ok then return decoded, endPos end
  if not reported then
    reported = true
    Isaac.DebugString("[Console JSON probe] bytes=" .. tostring(type(value) == "string" and #value or -1))
    Isaac.DebugString(debug.traceback("[Console JSON probe] caller", 2))
  end
  error(decoded, 0)
end
Isaac.DebugString("[Console JSON probe] installed; errors are not suppressed")
