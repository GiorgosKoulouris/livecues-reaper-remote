-- The text handling every snapshot store shares (IEM Mix, Snapshots): percent-escaping, splitting, the number
-- format, name cleaning, and lookups over an index list of `{ id, name, ... }` entries. What a record holds and how
-- it is joined stays with each app's store, so what is already saved in a project reads the same.

local text = {}

--- Percent-escape `%`, `,`, `;` and control characters, so a value holds no separator and no newline.
function text.escape(value)
  return (value:gsub("[%%,;%c]", function(c) return ("%%%02X"):format(c:byte()) end))
end

function text.unescape(value)
  return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

--- Split on a plain-text separator; "" gives one empty part.
function text.split(value, separator)
  local parts, from = {}, 1
  while true do
    local at = value:find(separator, from, true)
    if not at then
      parts[#parts + 1] = value:sub(from)
      return parts
    end
    parts[#parts + 1] = value:sub(from, at - 1)
    from = at + #separator
  end
end

--- A number as stored: 17 significant digits, which reads back to the same double.
function text.number(value) return ("%.17g"):format(value) end

--- A name as typed: trimmed, not empty, at most MAX_NAME characters, valid UTF-8, no control characters.
--- Returns the name, or nil and `empty_name`, `bad_name` or `name_too_long`.
text.MAX_NAME = 40
function text.clean_name(raw)
  local name = (raw or ""):match("^%s*(.-)%s*$")
  if name == "" then return nil, "empty_name" end
  if name:find("%c") or not utf8.len(name) then return nil, "bad_name" end
  if utf8.len(name) > text.MAX_NAME then return nil, "name_too_long" end
  return name
end

--- The entry of an index list with this name, and its position.
function text.find(list, name)
  for position, entry in ipairs(list) do
    if entry.name == name then return entry, position end
  end
  return nil
end

--- One more than the highest id in an index list.
function text.next_id(list)
  local top = 0
  for _, entry in ipairs(list) do top = math.max(top, entry.id) end
  return top + 1
end

return text
