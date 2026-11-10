-- Where snapshots live: project ExtState (section `LCRR_IEM`), which ignores undo (suite CONTEXT.md, issue 01), so
-- nothing here opens an undo block and nothing here can be undone.
--
-- Two kinds of key, both a single line (no newline in a value, so the .rpp stays plain):
--   `snapshots`      the index, one record per snapshot: `id,saved,mixes,sends,name` joined by `;`
--                    (name last, with `%`, `,`, `;` and control characters percent-escaped)
--   `snapshot.<id>`  one snapshot's contents: `V,1`, then per mix `M,<guid>,<master|->` followed by its sends
--                    `S,<source guid>,<vol>,<pan>,<0|1 muted>`, all joined by `;`
-- The list reads only the index, so it stays small however large a snapshot is. A snapshot is matched to tracks by
-- GUID. `read` is what recall uses.

local tracks = require("lib.core.tracks")

local store = {}

store.SECTION = tracks.EXT_SECTION
store.INDEX_KEY = "snapshots"
store.VERSION = 1

local function escape(text)
  return (text:gsub("[%%,;%c]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function unescape(text)
  return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function get(api, key)
  local found, value = api.GetProjExtState(0, store.SECTION, key)
  if found and found ~= 0 and value ~= "" then return value end
  return nil
end

local function number(value) return ("%.17g"):format(value) end

local function split(text, separator)
  local parts, from = {}, 1
  while true do
    local at = text:find(separator, from, true)
    if not at then
      parts[#parts + 1] = text:sub(from)
      return parts
    end
    parts[#parts + 1] = text:sub(from, at - 1)
    from = at + #separator
  end
end

--- The index: a list of `{ id, saved, mixes, sends, name }` in save order. Empty when nothing is saved; nil and
--- `unreadable` when the stored index cannot be read (it is never guessed at, so a save cannot wipe it).
function store.list(api)
  local text = get(api, store.INDEX_KEY)
  local list = {}
  if not text then return list end
  for _, record in ipairs(split(text, ";")) do
    local id, saved, mixes, sends, name = record:match("^(%d+),(%d+),(%d+),(%d+),(.*)$")
    if not id then return nil, "unreadable" end
    list[#list + 1] = {
      id = tonumber(id), saved = tonumber(saved), mixes = tonumber(mixes), sends = tonumber(sends),
      name = unescape(name),
    }
  end
  return list
end

function store.find(list, name)
  for position, entry in ipairs(list) do
    if entry.name == name then return entry, position end
  end
  return nil
end

function store.next_id(list)
  local top = 0
  for _, entry in ipairs(list) do top = math.max(top, entry.id) end
  return top + 1
end

local function write_index(api, list)
  local records = {}
  for _, e in ipairs(list) do
    records[#records + 1] = ("%d,%d,%d,%d,%s"):format(e.id, e.saved, e.mixes, e.sends, escape(e.name))
  end
  api.SetProjExtState(0, store.SECTION, store.INDEX_KEY, table.concat(records, ";"))
end

local function data_key(id) return "snapshot." .. id end

--- A snapshot's contents `{ mixes = { { guid, master (number|nil), sends = { { source, vol, pan, muted } } } } }` as
--- one line.
function store.encode(contents)
  local records = { "V," .. store.VERSION }
  for _, mix in ipairs(contents.mixes) do
    records[#records + 1] = ("M,%s,%s"):format(mix.guid, mix.master and number(mix.master) or "-")
    for _, send in ipairs(mix.sends) do
      records[#records + 1] = ("S,%s,%s,%s,%d"):format(send.source, number(send.vol), number(send.pan),
        send.muted and 1 or 0)
    end
  end
  return table.concat(records, ";")
end

--- The reverse of `encode`; nil when the text is not a snapshot this version wrote.
function store.decode(text)
  local contents, mix = { mixes = {} }, nil
  for position, record in ipairs(split(text, ";")) do
    local f = split(record, ",")
    if position == 1 then
      if f[1] ~= "V" or tonumber(f[2]) ~= store.VERSION then return nil end
    elseif f[1] == "M" then
      mix = { guid = f[2], master = tonumber(f[3]), sends = {} }
      contents.mixes[#contents.mixes + 1] = mix
    elseif f[1] == "S" and mix and tonumber(f[3]) and tonumber(f[4]) then
      mix.sends[#mix.sends + 1] = { source = f[2], vol = tonumber(f[3]), pan = tonumber(f[4]), muted = f[5] == "1" }
    else
      return nil
    end
  end
  return contents
end

--- One snapshot's contents by index entry, or nil and `unreadable`.
function store.read(api, entry)
  local text = get(api, data_key(entry.id))
  local contents = text and store.decode(text)
  if not contents then return nil, "unreadable" end
  return contents
end

--- Store a snapshot: its contents first, then the index, so a snapshot is listed only once it is whole. `entry` is
--- `{ id, saved, mixes, sends, name }`; `list` is the current index, which is changed in place.
function store.put(api, list, entry, contents)
  api.SetProjExtState(0, store.SECTION, data_key(entry.id), store.encode(contents))
  local _, position = store.find(list, entry.name)
  list[position or (#list + 1)] = entry
  write_index(api, list)
end

--- Remove a snapshot: out of the index first, then its contents.
function store.remove(api, list, entry)
  local _, position = store.find(list, entry.name)
  table.remove(list, position)
  write_index(api, list)
  api.SetProjExtState(0, store.SECTION, data_key(entry.id), "")
end

--- A snapshot name as typed: trimmed, not empty, at most MAX_NAME characters, no control characters.
store.MAX_NAME = 40
function store.clean_name(raw)
  local name = (raw or ""):match("^%s*(.-)%s*$")
  if name == "" then return nil, "empty_name" end
  if name:find("%c") or not utf8.len(name) then return nil, "bad_name" end
  if utf8.len(name) > store.MAX_NAME then return nil, "name_too_long" end
  return name
end

return store
