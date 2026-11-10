-- Encode-only JSON, for the bridge's replies.
--
-- The bridge never parses JSON: requests are flat key/value fields
-- (shared/bridge/request.lua), so this is the only direction there is.
--
-- Lua has one table type, so two shapes need a rule:
--
--   * A table whose keys are exactly 1..n is an array. **An empty table is an
--     empty array**, never an empty object. A reply field that is an object is
--     therefore never empty (the views always put something in it).
--   * Any other table is an object. Keys are sorted, so a reply is
--     deterministic, and a number key (a `tally` keyed by timebase mode)
--     becomes its string form.
--
-- A function, userdata or thread is an error rather than a silent null: a
-- reply that quietly lost a field is worse than one that fails loudly, and the
-- bridge turns the error into an `internal` refusal.

local json = {}

local MAX_DEPTH = 64

local ESCAPES = {
  ['"'] = '\\"',
  ["\\"] = "\\\\",
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
}

local function escape_char(char)
  return ESCAPES[char] or ("\\u%04x"):format(char:byte())
end

local function encode_string(value)
  return '"' .. value:gsub('[%c"\\]', escape_char) .. '"'
end

local function encode_number(value)
  -- JSON has no NaN or infinity.
  if value ~= value or value == math.huge or value == -math.huge then
    return "null"
  end
  if math.type(value) == "integer" then
    return ("%d"):format(value)
  end
  if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
    return ("%d"):format(value)
  end
  -- %.14g reads back to the same millisecond-scale time; the decimal point is
  -- forced in case the host's locale uses a comma.
  return (("%.14g"):format(value):gsub(",", "."))
end

local function is_array(value)
  local count = 0
  for _ in pairs(value) do
    count = count + 1
  end
  for index = 1, count do
    if value[index] == nil then
      return false
    end
  end
  return true
end

local function sorted_keys(value)
  local keys = {}
  for key in pairs(value) do
    local kind = type(key)
    if kind ~= "string" and kind ~= "number" then
      error("json: cannot encode a table key of type " .. kind, 0)
    end
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return keys
end

local encode

local function encode_table(value, depth)
  if depth > MAX_DEPTH then
    error("json: nested deeper than " .. MAX_DEPTH, 0)
  end
  local parts = {}
  if is_array(value) then
    for index = 1, #value do
      parts[index] = encode(value[index], depth + 1)
    end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  for _, key in ipairs(sorted_keys(value)) do
    parts[#parts + 1] = encode_string(tostring(key)) .. ":" .. encode(value[key], depth + 1)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function encode(value, depth)
  local kind = type(value)
  if kind == "nil" then
    return "null"
  elseif kind == "boolean" then
    return tostring(value)
  elseif kind == "number" then
    return encode_number(value)
  elseif kind == "string" then
    return encode_string(value)
  elseif kind == "table" then
    return encode_table(value, depth)
  end
  error("json: cannot encode a " .. kind, 0)
end

--- Encode a Lua value as JSON text.
-- @return string
function json.encode(value)
  return encode(value, 1)
end

return json
