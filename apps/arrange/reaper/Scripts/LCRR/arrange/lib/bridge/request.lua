-- Parse a bridge request: the value the page wrote to ExtState.
--
--   <id>|<length>|<body>
--
--   id      a token the page makes up for this request; the reply carries it
--   length  how many bytes `body` is, as the page sent it
--   body    flat fields, `key=value&key=value`, each value percent-encoded
--
-- **Why the length.** REAPER cuts a request URL at about 1026 characters and
-- answers HTTP 200 anyway (`.scratch/arrange/issues/01-bridge-spike.md`), so
-- the only way to know a request arrived whole is for it to say how long it
-- is. A body shorter than declared is refused, never guessed at. The page
-- keeps requests under about 900 encoded characters.
--
-- Values are percent-decoded here, so a region name may hold any character.
-- `+` is an ordinary character, not a space (encodeURIComponent never makes
-- one). Fields are all strings; the handlers decide what they mean.

local request = {}

request.MAX_ID = 40

--- The id at the front of a request, even when the rest is unusable, so the
--- refusal can be addressed. Nil when there is none.
local function id_of(raw)
  local id = raw:match("^([%w_%-]+)|")
  if id and #id <= request.MAX_ID then
    return id
  end
  return nil
end

local function decode(value)
  if value:find("%%") then
    local bad = false
    value = value:gsub("%%(%x?%x?)", function(hex)
      if #hex ~= 2 then
        bad = true
        return ""
      end
      return string.char(tonumber(hex, 16))
    end)
    if bad then
      return nil
    end
  end
  return value
end

--- Parse a raw ExtState value.
-- @param raw string
-- @return table|nil { id, fields = { key = value } }
-- @return table|nil refusal { id, code, ... } when the request is unusable;
--   `id` is nil when not even that could be read, and nothing can be answered
function request.parse(raw)
  if type(raw) ~= "string" or raw == "" then
    return nil, { code = "bad_request" }
  end

  local id = id_of(raw)
  if not id then
    return nil, { code = "bad_request" }
  end

  local length, body = raw:match("^[^|]*|(%d+)|(.*)$")
  if not length then
    -- Cut off before the body began: truncation is the only way to get here
    -- from a page that follows the format.
    return nil, { id = id, code = "request_truncated" }
  end
  length = tonumber(length)

  if #body < length then
    return nil, { id = id, code = "request_truncated", declared = length, received = #body }
  end
  if #body > length then
    return nil, { id = id, code = "bad_request", declared = length, received = #body }
  end

  local fields = {}
  if body ~= "" then
    for pair in (body .. "&"):gmatch("([^&]*)&") do
      local key, value = pair:match("^([%w_]+)=(.*)$")
      if not key then
        return nil, { id = id, code = "bad_request" }
      end
      value = decode(value)
      if value == nil then
        return nil, { id = id, code = "bad_request" }
      end
      fields[key] = value
    end
  end

  return { id = id, fields = fields }
end

return request
