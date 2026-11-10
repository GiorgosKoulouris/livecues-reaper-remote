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
  phase = 0, fx = 1, automode = 0 }
local SEND_DEFAULTS = { vol = 1, pan = 0, mute = 0, mode = 0, automode = -1 }
-- Automation: a track has `automode` (0 Trim ... 5 Latch Preview), `env = { Volume = n, Pan = n, Mute = n }` (an
-- envelope with n points, absent when not listed) and `inactive = { Mute = true }` for a bypassed one. A send has
-- `automode` (-1 follows the track) and `env = { vol = n, pan = n, mute = n }`; a send's envelope always exists, with
-- 0 points. `spec.override` is the global automation override (-1 none).
local SEND_ENVS = { ["P_ENV:<VOLENV"] = "vol", ["P_ENV:<PANENV"] = "pan", ["P_ENV:<MUTEENV"] = "mute" }

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
    if key == "I_AUTOMODE" then return send.automode end
    if SEND_ENVS[key] then
      local which = SEND_ENVS[key]
      return { points = (send.env or {})[which] or 0, active = "1" }
    end
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

  -- Writing (restore): a written value lands on the fake track, and each write is logged in `api.writes` as
  -- `{ key, value }` so a spec can see what was touched. `api.undo_names` has each closed block's name.
  api.writes, api.undo_names = {}, {}
  function api.GetSetMediaTrackInfo_String(track, key) assert(key == "P_NAME"); return true, track.name end
  function api.SetMediaTrackInfo_Value(track, key, value)
    track[assert(TRACK_KEYS[key], "fake_project: unknown track key " .. key)] = value
    api.writes[#api.writes + 1] = { key = key, value = value }
    return true
  end
  function api.SetTrackSendInfo_Value(track, category, index, key, value)
    list_of(track, category)[index + 1][assert(SEND_KEYS[key], "fake_project: unknown send key " .. key)] = value
    api.writes[#api.writes + 1] = { key = key, value = value }
    return true
  end
  function api.Undo_EndBlock2(_, name) api.undo_names[#api.undo_names + 1] = name end
  function api.GetTrackAutomationMode(track) return track.automode end
  function api.GetGlobalAutomationOverride() return spec.override or -1 end
  function api.GetTrackEnvelopeByName(track, name)
    local points = (track.env or {})[name]
    if not points then return nil end
    return { points = points, active = (track.inactive or {})[name] and "0" or "1" }
  end
  function api.CountEnvelopePoints(env) return env.points end
  function api.GetSetEnvelopeInfo_String(env) return true, env.active end
  function api.PreventUIRefresh() end
  function api.TrackList_AdjustWindows() end
  function api.UpdateArrange() end

  return api
end

return fake_project
