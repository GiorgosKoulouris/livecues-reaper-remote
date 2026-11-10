-- The `cue` core: the cue track IEM Mix listens through (spec: IEM Mix, "Listen"). REAPER has no per-mix cue, so the
-- cue track is one track named `IEM-Cue` (exact, case-sensitive; it must not start with `IEM_`, so it never becomes a
-- mix) inside the IEMs folder with master send off, and every mix sends to it, post-fader at level 0 (silent until
-- the page raises one send to listen). Its hardware output, the engineer's headphones, is set by the `output`
-- command, which accepts this track as well as a mix.
--
--   cue.run({ api })
--     -> { status = "ok", changed, created, guid, added, protected }
--
-- One undo step ("IEM Setup: create cue"): the track when it is missing (placed with `tracks.open_slot`, as `create`
-- places a mix), then a send from every mix that has none to it, and solo defeat on the cue track and every mix
-- (`protected` counts the tracks it was turned on for). Running it again adds only what is missing; with nothing
-- missing it is `changed: false` and leaves no undo step. `create` and `adopt` use `cue.join` to set up the cue track
-- (when there is none) and give a new mix its send and solo defeat in their own step.

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

--- Solo defeat (REAPER's `B_SOLO_DEFEAT`): a soloed source elsewhere in the project does not silence the track. Every
--- mix and the cue track have it, so the engineer's solo cannot cut what a musician hears or what Listen plays.
--- Unverified on a real host (CONTEXT.md, "Still unverified"): this one name is the place to correct.
cue.SOLO_DEFEAT = "B_SOLO_DEFEAT"

function cue.is_protected(api, track)
  return api.GetMediaTrackInfo_Value(track, cue.SOLO_DEFEAT) == 1
end

--- Turn solo defeat on. Returns whether it changed anything.
function cue.protect(api, track)
  if cue.is_protected(api, track) then return false end
  api.SetMediaTrackInfo_Value(track, cue.SOLO_DEFEAT, 1)
  return true
end

--- Inside an open undo block: the cue track (made last in the IEMs folder when missing), a send from every mix that has
--- none to it, and solo defeat on the cue track and every mix. Returns the track, the sends added, the tracks changed
--- by solo defeat and whether the track was created.
function cue.ensure(api, colour)
  local list = tracks.scan(api)
  local existing = tracks.find_cue(list)
  local track = existing and existing.track
  if not existing then
    local at, depth = tracks.open_slot(api, list, tracks.find_folder(list), colour)
    track = tracks.new_track(api, at, tracks.CUE_NAME, depth, colour)
    list = tracks.scan(api)
  end
  local have, added, protected = cue.senders(api, track), 0, 0
  if cue.protect(api, track) then protected = protected + 1 end
  for _, entry in ipairs(list) do
    if tracks.is_mix_name(entry.name) then
      if not have[entry.guid] then
        cue.add_send(api, entry.track, track)
        added = added + 1
      end
      if cue.protect(api, entry.track) then protected = protected + 1 end
    end
  end
  return track, added, protected, existing == nil
end

--- Inside an open undo block, for `create` and `adopt`: the new mix gets solo defeat and its send to the cue track.
--- With no cue track one is made (cue.ensure), so the first mix of a project sets up the whole cue.
function cue.join(api, mix_track, colour)
  local existing = tracks.find_cue(tracks.scan(api))
  if not existing then
    cue.ensure(api, colour)
    return
  end
  if not cue.senders(api, existing.track)[api.GetTrackGUID(mix_track)] then
    cue.add_send(api, mix_track, existing.track)
  end
  cue.protect(api, mix_track)
end

function cue.run(given)
  local api = given.api
  local list = tracks.scan(api)
  local existing = tracks.find_cue(list)
  if existing then
    local todo = #cue.missing(api, list, existing) > 0 or not cue.is_protected(api, existing.track)
    for _, entry in ipairs(list) do
      if tracks.is_mix_name(entry.name) and not cue.is_protected(api, entry.track) then todo = true end
    end
    if not todo then
      return { status = "ok", changed = false, created = false, guid = existing.guid, added = 0, protected = 0 }
    end
  end

  local result = { status = "ok", changed = true }
  local colour = tracks.colour(api)
  undo.run(api, "IEM Setup: create cue", function()
    local track, added, protected, created = cue.ensure(api, colour)
    result.created, result.guid = created, api.GetTrackGUID(track)
    result.added, result.protected = added, protected
  end)
  return result
end

return cue
