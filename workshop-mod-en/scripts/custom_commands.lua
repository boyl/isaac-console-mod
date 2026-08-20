local CustomCommandModel = {}
CustomCommandModel.__index = CustomCommandModel

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function canonical(command)
  local value = trim(command):lower():gsub("%s+", " ")
  return value
end

local function utf8Length(value)
  local count = 0
  for index = 1, #value do
    local byte = value:byte(index)
    if byte < 0x80 or byte >= 0xC0 then count = count + 1 end
  end
  return count
end

local function escape(value)
  local escaped = tostring(value or "")
    :gsub("%%", "%%25")
    :gsub("|", "%%7C")
    :gsub("~", "%%7E")
    :gsub("\r", "%%0D")
    :gsub("\n", "%%0A")
  return escaped
end

local function unescape(value)
  local unescaped = tostring(value or "")
    :gsub("%%0A", "\n")
    :gsub("%%0D", "\r")
    :gsub("%%7E", "~")
    :gsub("%%7C", "|")
    :gsub("%%25", "%%")
  return unescaped
end

local function copyRecords(records)
  local result = {}
  for index, record in ipairs(records) do
    result[index] = {
      id = record.id,
      command = record.command,
      name = record.name,
      trusted = record.trusted == true,
    }
  end
  return result
end

local function rebuildIndex(self)
  self.byId = {}
  self.byCommand = {}
  for _, record in ipairs(self.records) do
    assert(not self.byId[record.id], "duplicate custom command id")
    local normalized = canonical(record.command)
    assert(normalized ~= "", "empty custom command")
    assert(not self.byCommand[normalized], "duplicate custom command")
    self.byId[record.id] = record
    self.byCommand[normalized] = record
  end
end

function CustomCommandModel.new()
  return setmetatable({ records = {}, byId = {}, byCommand = {}, nextId = 1 }, CustomCommandModel)
end

function CustomCommandModel:key(id)
  return "u:" .. tostring(id)
end

function CustomCommandModel:find(id)
  return self.byId[tonumber(id)]
end

function CustomCommandModel:findByCommand(command)
  return self.byCommand[canonical(command)]
end

function CustomCommandModel:snapshot()
  return { records = copyRecords(self.records), nextId = self.nextId }
end

function CustomCommandModel:restore(snapshot)
  assert(type(snapshot) == "table" and type(snapshot.records) == "table", "invalid custom command snapshot")
  self.records = copyRecords(snapshot.records)
  self.nextId = assert(tonumber(snapshot.nextId), "invalid custom command next id")
  rebuildIndex(self)
end

function CustomCommandModel:add(command, name, trusted)
  local normalized = canonical(command)
  assert(normalized ~= "", "custom command must not be empty")
  assert(not self.byCommand[normalized], "custom command already exists")
  local id = self.nextId
  self.nextId = id + 1
  local record = {
    id = id,
    command = trim(command),
    name = trim(name),
    trusted = trusted == true,
  }
  table.insert(self.records, 1, record)
  rebuildIndex(self)
  return record
end

function CustomCommandModel:update(id, command, name, trusted)
  id = tonumber(id)
  local record = assert(self.byId[id], "custom command does not exist")
  local duplicate = self:findByCommand(command)
  assert(not duplicate or duplicate.id == id, "custom command already exists")
  record.command = trim(command)
  record.name = trim(name)
  record.trusted = trusted == true
  rebuildIndex(self)
  return record
end

function CustomCommandModel:remove(id)
  id = tonumber(id)
  local record = self.byId[id]
  if not record then return nil end
  for index, value in ipairs(self.records) do
    if value.id == id then
      table.remove(self.records, index)
      break
    end
  end
  rebuildIndex(self)
  return record
end

function CustomCommandModel:serialize()
  local result = {}
  for _, record in ipairs(self.records) do
    result[#result + 1] = table.concat({
      tostring(record.id),
      record.trusted and "1" or "0",
      escape(record.name),
      escape(record.command),
    }, "~")
  end
  return table.concat(result, "|")
end

function CustomCommandModel:load(serialized, savedNextId)
  self.records = {}
  self.nextId = 1
  local migrated = false
  local seenIds, seenCommands = {}, {}
  local maximumId = 0
  for value in tostring(serialized or ""):gmatch("([^|]+)") do
    local idText, trustedText, nameText, commandText = value:match("^(%d+)~([01])~(.-)~(.*)$")
    local id = tonumber(idText)
    local name = nameText and unescape(nameText) or nil
    local command = commandText and trim(unescape(commandText)) or nil
    local normalized = command and canonical(command) or ""
    local structurallyValid = id and id >= 1 and id == math.floor(id)
      and not seenIds[id] and normalized ~= "" and not seenCommands[normalized]
      and #command <= 120 and not command:find("\0", 1, true)
      and name ~= nil and not name:find("[\r\n]") and utf8Length(name) <= 40
    if structurallyValid then
      local record = {
        id = id,
        command = command,
        name = trim(name),
        trusted = trustedText == "1",
      }
      self.records[#self.records + 1] = record
      seenIds[id] = true
      seenCommands[normalized] = true
      if id > maximumId then maximumId = id end
    else
      migrated = true
    end
  end
  local requestedNextId = tonumber(savedNextId)
  if requestedNextId and requestedNextId == math.floor(requestedNextId)
      and requestedNextId > maximumId then
    self.nextId = requestedNextId
  else
    self.nextId = maximumId + 1
    if savedNextId ~= nil then migrated = true end
  end
  rebuildIndex(self)
  return migrated
end

return CustomCommandModel
