-- The `cue` core: the cue track IEM Mix listens through (spec: IEM Mix, "Listen"). REAPER has no per-mix cue, so the
-- cue track is one track named `IEM-Cue` (exact, case-sensitive; it must not start with `IEM_`, so it never becomes a
-- mix) inside the IEMs folder with master send off, and every mix sends to it, post-fader at level 0 (silent until
-- the page raises one send to listen). Its hardware output, the engineer's headphones, is set by the `output`
-- command, which accepts this track as well as a mix.
--
--   cue.run({ api })
--     -> { status = "ok", changed, created, guid, added }
--
-- One undo step ("IEM Setup: create cue"): the track when it is missing (placed with `tracks.open_slot`, as `create`
-- places a mix), then a send from every mix that has none to it. Running it again adds only what is missing; with
-- nothing missing it is `changed: false` and leaves no undo step. `create` and `adopt` use `cue.add_send` to give a new
-- mix its send in their own step.

local tracks = require("lib.core.tracks")
local undo = require("lib.core.undo")

local cue = {}

cue.SEND_MODE = 0   -- post-fader
cue.SEND_LEVEL = 0  -- linear gain: silent

--- The GUIDs of the tracks that already send to the cue track.
function cue.senders(api, cue_track)
  local found = {}
  for index = 0, api.GetTrackNumSends(cue_track, -1) - 1 do
    found[api.GetTrackGUID(api.GetTrackSendInfo_Value(cue_track, -1, index, "P_SRCTRACK"))] = true
  end
  return found
end

--- A send mix -> cue track, post-fader at level 0 (REAPER's default level is 0 dB, so both are set).
function cue.add_send(api, mix_track, cue_track)
  local index = api.CreateTrackSend(mix_track, cue_track)
  api.SetTrackSendInfo_Value(mix_track, 0, index, "I_SENDMODE", cue.SEND_MODE)
  api.SetTrackSendInfo_Value(mix_track, 0, index, "D_VOL", cue.SEND_LEVEL)
end

--- The mixes (entries of `list`) with no send to the cue track.
function cue.missing(api, list, cue_entry)
  local have = cue.senders(api, cue_entry.track)
  local found = {}
  for _, entry in ipairs(list) do
    if tracks.is_mix_name(entry.name) and not have[entry.guid] then found[#found + 1] = entry end
  end
  return found
end

function cue.run(given)
  local api = given.api
  local list = tracks.scan(api)
  local existing = tracks.find_cue(list)
  local missing = existing and cue.missing(api, list, existing) or nil
  if existing and #missing == 0 then
    return { status = "ok", changed = false, created = false, guid = existing.guid, added = 0 }
  end

  local result = { status = "ok", changed = true, created = existing == nil }
  local colour = tracks.colour(api)
  undo.run(api, "IEM Setup: create cue", function()
    local track = existing and existing.track
    if not existing then
      local at, depth = tracks.open_slot(api, list, tracks.find_folder(list), colour)
      track = tracks.new_track(api, at, tracks.CUE_NAME, depth, colour)
      missing = {}
      for _, entry in ipairs(list) do
        if tracks.is_mix_name(entry.name) then missing[#missing + 1] = entry end
      end
    end
    result.guid = api.GetTrackGUID(track)
    for _, entry in ipairs(missing) do cue.add_send(api, entry.track, track) end
    result.added = #missing
  end)
  return result
end

return cue
