-- A minimal fake REAPER for the bridge specs: the project path, tracks and the Master with their values, sends and
-- hardware outputs, project ExtState and the dirty flag.
--
--   local api = fake_project.new({
--     path = "C:/Show/Gig.rpp",
--     tracks = {
--       { name = "Kick", vol = 0.5, sends = { { to = "Bus", vol = 0.7 } }, outputs = { { vol = 1 } } },
--       { name = "Bus" },
--     },
--     master = { vol = 0.9, mute = 1 },
--   })
--
-- Track values default to REAPER's (unity volume, centre pan, nothing muted). GUID of track N is "{GUID-N}" unless
-- `guid` is given; the Master's is "{MASTER}". Sends name their destination in `to` (first track of that name).
-- `api.ext` is the project ExtState (`api.ext[section][key]`), `api.dirty` counts `MarkProjectDirty` calls and
-- `api.undo_blocks` counts undo blocks opened (saving must open none).
local fake_project = {}

local TRACK_KEYS = {
  D_VOL = "vol", D_PAN = "pan", D_WIDTH = "width", D_DUALPANL = "dual_l", D_DUALPANR = "dual_r",
  I_PANMODE = "pan_mode", B_MUTE = "mute", I_SOLO = "solo", B_PHASE = "phase", I_FXEN = "fx",
}
local SEND_KEYS = { D_VOL = "vol", D_PAN = "pan", B_MUTE = "mute", I_SENDMODE = "mode" }
local TRACK_DEFAULTS = { vol = 1, pan = 0, width = 1, dual_l = -1, dual_r = 1, pan_mode = 0, mute = 0, solo = 0,
  phase = 0, fx = 1 }
local SEND_DEFAULTS = { vol = 1, pan = 0, mute = 0, mode = 0 }

local function filled(given, defaults)
  local out = {}
  for key, value in pairs(defaults) do out[key] = value end
  for key, value in pairs(given or {}) do out[key] = value end
  return out
end

function fake_project.new(spec)
  local tracks = {}
  for index, given in ipairs(spec.tracks or {}) do
    local track = filled(given, TRACK_DEFAULTS)
    track.name = given.name or ""
    track.guid = given.guid or ("{GUID-%d}"):format(index)
    track.sends, track.outputs = {}, {}
    tracks[index] = track
  end
  local master = filled(spec.master, TRACK_DEFAULTS)
  master.name, master.guid, master.sends, master.outputs = "MASTER", "{MASTER}", {}, {}

  local function by_name(name)
    for _, track in ipairs(tracks) do
      if track.name == name then return track end
    end
    error("fake_project: no track named " .. tostring(name))
  end
  local function populate(track, given)
    for _, send in ipairs(given.sends or {}) do
      local made = filled(send, SEND_DEFAULTS)
      made.dest = by_name(send.to)
      track.sends[#track.sends + 1] = made
    end
    for _, output in ipairs(given.outputs or {}) do
      track.outputs[#track.outputs + 1] = filled(output, SEND_DEFAULTS)
    end
  end
  for index, given in ipairs(spec.tracks or {}) do populate(tracks[index], given) end
  populate(master, spec.master or {})

  local api = { tracks = tracks, ext = spec.ext or {}, dirty = 0, undo_blocks = 0 }

  function api.EnumProjects() return nil, spec.path or "" end
  function api.CountTracks() return #tracks end
  function api.GetTrack(_, index) return tracks[index + 1] end
  function api.GetMasterTrack() return master end
  function api.GetTrackGUID(track) return track.guid end

  function api.GetMediaTrackInfo_Value(track, key)
    return assert(track[assert(TRACK_KEYS[key], "fake_project: unknown track key " .. key)])
  end

  local function list_of(track, category)
    return category == 0 and track.sends or track.outputs
  end
  function api.GetTrackNumSends(track, category) return #list_of(track, category) end
  function api.GetTrackSendInfo_Value(track, category, index, key)
    local send = list_of(track, category)[index + 1]
    if key == "P_DESTTRACK" then return send.dest end
    return assert(send[assert(SEND_KEYS[key], "fake_project: unknown send key " .. key)])
  end

  function api.GetProjExtState(_, section, key)
    local value = (api.ext[section] or {})[key]
    if value == nil then return 0, "" end
    return 1, value
  end
  function api.SetProjExtState(_, section, key, value)
    api.ext[section] = api.ext[section] or {}
    api.ext[section][key] = value ~= "" and value or nil
    return 0
  end
  function api.MarkProjectDirty() api.dirty = api.dirty + 1 end
  function api.Undo_BeginBlock2() api.undo_blocks = api.undo_blocks + 1 end

  return api
end

return fake_project
