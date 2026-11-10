-- The `snapshot_save` core: store everything a restore can bring back, for every track, the Master, and every send
-- and hardware output: volume, full pan state, mute, solo, polarity and FX on/off per track; volume, pan, mute and
-- mode per send and output. The request carries only the name; the values are read here. In-ear tracks are stored
-- like any other.
--
--   snapshot_save.run({ api, fields = { name }, now = function() return os.time() end })
--     -> { status = "ok", name, tracks, sends }
--
-- Refusals, all decided before anything is written: `empty_name`, `bad_name`, `name_too_long`, `duplicate_name`,
-- `unreadable` (the stored list cannot be read).
--
-- Levels and pans are `D_VOL` and `D_PAN`, never `GetTrackUIVolPan`: those report an envelope's value in Read mode,
-- while `D_VOL` keeps the stored one (suite CONTEXT.md, measured). The Master is stored under the key `master`. A
-- send is stored with its destination's GUID, in REAPER's order, so sends of the same pair keep their order; a
-- hardware output is stored in track order. Project ExtState ignores undo: no undo block, no undo step. The store
-- marks the project dirty.

local store = require("lib.core.snapshot_store")
local refusal = require("lib.core.snapshots").refusal

local snapshot_save = {}

local SEND_CATEGORY, OUTPUT_CATEGORY = 0, 1

local function read_send(api, track, category, index)
  local function value(key) return api.GetTrackSendInfo_Value(track, category, index, key) end
  return { vol = value("D_VOL"), pan = value("D_PAN"), mute = value("B_MUTE"), mode = value("I_SENDMODE") }
end

local function read_track(api, track, guid)
  local function value(key) return api.GetMediaTrackInfo_Value(track, key) end
  local out = {
    guid = guid, vol = value("D_VOL"), pan = value("D_PAN"), width = value("D_WIDTH"),
    dual_l = value("D_DUALPANL"), dual_r = value("D_DUALPANR"), pan_mode = value("I_PANMODE"),
    mute = value("B_MUTE"), solo = value("I_SOLO"), phase = value("B_PHASE"), fx = value("I_FXEN"),
    sends = {}, outputs = {},
  }
  for index = 0, api.GetTrackNumSends(track, SEND_CATEGORY) - 1 do
    local send = read_send(api, track, SEND_CATEGORY, index)
    send.dest = api.GetTrackGUID(api.GetTrackSendInfo_Value(track, SEND_CATEGORY, index, "P_DESTTRACK"))
    out.sends[#out.sends + 1] = send
  end
  for index = 0, api.GetTrackNumSends(track, OUTPUT_CATEGORY) - 1 do
    out.outputs[#out.outputs + 1] = read_send(api, track, OUTPUT_CATEGORY, index)
  end
  return out
end

local function capture(api)
  local contents, sends, marks = { tracks = {} }, 0, 0
  local function add(entry)
    contents.tracks[#contents.tracks + 1] = entry
    sends = sends + #entry.sends + #entry.outputs
    if entry.solo ~= 0 then marks = marks | store.MARK_SOLO end
  end
  for index = 0, api.CountTracks(0) - 1 do
    local track = api.GetTrack(0, index)
    add(read_track(api, track, api.GetTrackGUID(track)))
  end
  local master = read_track(api, api.GetMasterTrack(0), store.MASTER)
  contents.tracks[#contents.tracks + 1] = master
  sends = sends + #master.sends + #master.outputs
  if master.solo ~= 0 then marks = marks | store.MARK_SOLO end
  if master.mute ~= 0 then marks = marks | store.MARK_MASTER_MUTED end
  return contents, #contents.tracks - 1, sends, marks
end

function snapshot_save.run(given)
  local api, fields = given.api, given.fields or {}
  local name, code = store.clean_name(fields.name)
  if not name then return refusal(code) end
  local list, bad = store.list(api)
  if not list then return refusal(bad) end
  if store.find(list, name) then return refusal("duplicate_name") end

  local contents, tracks, sends, marks = capture(api)
  local now = given.now or os.time
  local entry = {
    id = store.next_id(list), saved = math.floor(now()), tracks = tracks, sends = sends, marks = marks, name = name,
  }
  store.put(api, list, entry, contents)
  return { status = "ok", name = name, tracks = tracks, sends = sends }
end

return snapshot_save
