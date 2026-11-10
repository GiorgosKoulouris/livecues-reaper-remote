-- The `create` core: a new mix, by name only. The first one also makes the
-- `IEMs` folder at the end of the track list; later ones go inside it, after
-- the folder's last member. Master send is off on the folder and the mix, both
-- take the shared colour, and REAPER's folder depth is set by hand (it does not
-- repair it, suite CONTEXT.md): the old last member stops closing the folder
-- and the new mix closes it. All of it is one undo step.
--
-- `copy` (optional, the GUID of a mix) gives the new mix the same sends as that mix, in the same undo step: the
-- source, level, pan, mute and signal point of each. Not its output. A send from another mix or from the IEMs
-- folder is not copied (those are not sources). The copied mix is checked before the block opens.
--
--   create.run({ api, fields = { name, copy? } })
--     -> { status = "ok", guid, folder_created }
--      | { status = "refused", error = { code = "empty_name" | "duplicate_name" | "track_gone" | "not_a_mix" } }

local tracks = require("lib.core.tracks")
local undo = require("lib.core.undo")
local cell = require("lib.core.cell")
local cue = require("lib.core.cue")

local create = {}

--- The sends of the mix to copy that come from a source, as { track, vol, pan, muted, mode }.
local function sends_to_copy(api, list, from)
  local found = {}
  for index = 0, api.GetTrackNumSends(from.track, -1) - 1 do
    local track = api.GetTrackSendInfo_Value(from.track, -1, index, "P_SRCTRACK")
    local entry = tracks.find_by_guid(list, api.GetTrackGUID(track))
    if entry and tracks.is_source(list, entry) then
      found[#found + 1] = {
        track = track,
        vol = api.GetTrackSendInfo_Value(from.track, -1, index, "D_VOL"),
        pan = api.GetTrackSendInfo_Value(from.track, -1, index, "D_PAN"),
        muted = api.GetTrackSendInfo_Value(from.track, -1, index, "B_MUTE"),
        mode = api.GetTrackSendInfo_Value(from.track, -1, index, "I_SENDMODE"),
      }
    end
  end
  return found
end

function create.run(given)
  local api = given.api
  local list = tracks.scan(api)
  local name, code = tracks.check_name(list, (given.fields or {}).name, nil)
  if not name then
    return tracks.refusal(code)
  end

  local copies = {}
  local copy_guid = (given.fields or {}).copy
  if copy_guid and copy_guid ~= "" then
    local from, why = tracks.find_mix(list, copy_guid)
    if not from then return tracks.refusal(why) end
    copies = sends_to_copy(api, list, from)
  end

  local colour = tracks.colour(api)
  local folder = tracks.find_folder(list)
  local result = { status = "ok", folder_created = folder == nil }

  undo.run(api, "IEM Setup: create mix", function()
    local at, depth = tracks.open_slot(api, list, folder, colour)
    local mix = tracks.new_track(api, at, tracks.MIX_PREFIX .. name, depth, colour)
    result.guid = api.GetTrackGUID(mix)
    for _, send in ipairs(copies) do
      cell.copy_send(api, send.track, mix, send)
    end
    -- A cue track already in the project gets the new mix's send, in this same step.
    local cue_entry = tracks.find_cue(list)
    if cue_entry then cue.add_send(api, mix, cue_entry.track) end
  end)

  return result
end

return create
