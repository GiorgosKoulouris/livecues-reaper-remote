-- Where project snapshots live: project ExtState (section `LCRR_SNAPSHOTS`), which ignores undo (suite CONTEXT.md),
-- so nothing here opens an undo block and nothing here can be undone. REAPER does not see an ExtState write as a
-- change to the project either, so `put` and `remove` call `MarkProjectDirty(0)` (otherwise REAPER could close with
-- no prompt to save and the change would be lost).
--
-- Two kinds of key, both a single line (no newline in a value, so the .rpp stays plain):
--   `snapshots`      the index, one record per snapshot: `id,saved,tracks,sends,marks,name` joined by `;`
--                    (name last, percent-escaped). `marks` is a bit set decided at save: 1 a solo, 2 a muted Master.
--   `snapshot.<id>`  one snapshot's contents, records joined by `;`:
--                      `V,1`
--                      `T,<guid|master>,vol,pan,width,dualL,dualR,panmode,mute,solo,phase,fx`  a track or the Master
--                      `S,<dest guid>,vol,pan,mute,mode`   a send of the track above, in REAPER's order
--                      `H,vol,pan,mute,mode`               a hardware output of the track above, in track order
-- The list reads only the index, so it stays small however large a snapshot is. Text handling is the suite's
-- (`shared.snapshot.text`, the same as IEM Mix's store).

local text = require("shared.snapshot.text")

local store = {}

store.SECTION = "LCRR_SNAPSHOTS"
store.INDEX_KEY = "snapshots"
store.VERSION = 1
store.MASTER = "master"
store.MARK_SOLO = 1
store.MARK_MASTER_MUTED = 2

store.MAX_NAME = text.MAX_NAME
store.clean_name = text.clean_name
store.find = text.find
store.next_id = text.next_id

local escape, unescape, split, number = text.escape, text.unescape, text.split, text.number

local TRACK_FIELDS = { "vol", "pan", "width", "dual_l", "dual_r", "pan_mode", "mute", "solo", "phase", "fx" }
local SEND_FIELDS = { "vol", "pan", "mute", "mode" }

local function get(api, key)
  local found, value = api.GetProjExtState(0, store.SECTION, key)
  if found and found ~= 0 and value ~= "" then return value end
  return nil
end

--- The index: a list of `{ id, saved, tracks, sends, marks, name }` in save order. Empty when nothing is saved; nil
--- and `unreadable` when the stored index cannot be read (it is never guessed at, so a save cannot wipe it).
function store.list(api)
  local value = get(api, store.INDEX_KEY)
  local list = {}
  if not value then return list end
  for _, record in ipairs(split(value, ";")) do
    local id, saved, tracks, sends, marks, name = record:match("^(%d+),(%d+),(%d+),(%d+),(%d+),(.*)$")
    if not id then return nil, "unreadable" end
    list[#list + 1] = {
      id = tonumber(id), saved = tonumber(saved), tracks = tonumber(tracks), sends = tonumber(sends),
      marks = tonumber(marks), name = unescape(name),
    }
  end
  return list
end

local function write_index(api, list)
  local records = {}
  for _, e in ipairs(list) do
    records[#records + 1] = ("%d,%d,%d,%d,%d,%s"):format(e.id, e.saved, e.tracks, e.sends, e.marks, escape(e.name))
  end
  api.SetProjExtState(0, store.SECTION, store.INDEX_KEY, table.concat(records, ";"))
  api.MarkProjectDirty(0)
end

local function data_key(id) return "snapshot." .. id end

local function numbers(item, fields)
  local out = {}
  for _, field in ipairs(fields) do out[#out + 1] = number(item[field]) end
  return table.concat(out, ",")
end

--- A snapshot's contents `{ tracks = { { guid, vol, pan, ..., sends = { { dest, vol, pan, mute, mode } },
--- outputs = { { vol, pan, mute, mode } } } } }` as one line. The Master's `guid` is `store.MASTER`.
function store.encode(contents)
  local records = { "V," .. store.VERSION }
  for _, track in ipairs(contents.tracks) do
    records[#records + 1] = ("T,%s,%s"):format(track.guid, numbers(track, TRACK_FIELDS))
    for _, send in ipairs(track.sends) do
      records[#records + 1] = ("S,%s,%s"):format(send.dest, numbers(send, SEND_FIELDS))
    end
    for _, output in ipairs(track.outputs) do
      records[#records + 1] = "H," .. numbers(output, SEND_FIELDS)
    end
  end
  return table.concat(records, ";")
end

local function read_numbers(f, from, fields, into)
  for offset, field in ipairs(fields) do
    local value = tonumber(f[from + offset - 1])
    if not value then return nil end
    into[field] = value
  end
  return into
end

--- The reverse of `encode`; nil when the text is not a snapshot this version wrote.
function store.decode(value)
  local contents, track = { tracks = {} }, nil
  for position, record in ipairs(split(value, ";")) do
    local f = split(record, ",")
    if position == 1 then
      if f[1] ~= "V" or tonumber(f[2]) ~= store.VERSION then return nil end
    elseif f[1] == "T" and f[2] and #f == 2 + #TRACK_FIELDS then
      track = read_numbers(f, 3, TRACK_FIELDS, { guid = f[2], sends = {}, outputs = {} })
      if not track then return nil end
      contents.tracks[#contents.tracks + 1] = track
    elseif f[1] == "S" and track and #f == 2 + #SEND_FIELDS then
      local send = read_numbers(f, 3, SEND_FIELDS, { dest = f[2] })
      if not send then return nil end
      track.sends[#track.sends + 1] = send
    elseif f[1] == "H" and track and #f == 1 + #SEND_FIELDS then
      local output = read_numbers(f, 2, SEND_FIELDS, {})
      if not output then return nil end
      track.outputs[#track.outputs + 1] = output
    else
      return nil
    end
  end
  return contents
end

--- One snapshot's contents by index entry, or nil and `unreadable`.
function store.read(api, entry)
  local value = get(api, data_key(entry.id))
  local contents = value and store.decode(value)
  if not contents then return nil, "unreadable" end
  return contents
end

--- Store a snapshot: its contents first, then the index, so a snapshot is listed only once it is whole. `entry` is
--- `{ id, saved, tracks, sends, marks, name }`; `list` is the current index, which is changed in place.
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

return store
