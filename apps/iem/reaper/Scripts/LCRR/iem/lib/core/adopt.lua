-- The `adopt` core: a stray mix (an `IEM_` track outside the IEMs folder) joins the folder. As one undo step:
--
--   1. it leaves its place: the neighbours' depths are repaired as `delete` does (what it closed goes to the track
--      before it, what it opened to the track that closed it) and its own depth becomes 0, so it can travel;
--   2. it moves to the end of the folder (`ReorderSelectedTracks`, depths travel with it), the folder being created at
--      the end of the list when there is none, with the depth edits `create` makes (`tracks.open_slot`); the
--      engineer's track selection is put back;
--   3. master send off, the shared colour;
--   4. every send it receives becomes post-FX pre-fader (`I_SENDMODE` 3), found from the source's side. Level, pan and
--      mute are kept. This can change what a musician hears (spec).
--
-- Its hardware outputs are not touched, so several outputs stay as they are. Refusals are decided before the block
-- opens: track_gone, not_a_mix, not_a_stray (already in the folder).
--
--   adopt.run({ api, fields = { guid } })
--     -> { status = "ok" }
--      | { status = "refused", error = { code } }

local tracks = require("lib.core.tracks")
local undo = require("lib.core.undo")
local cell = require("lib.core.cell")

local adopt = {}

local function in_folder(folder, entry)
  return folder and folder.open and entry.index > folder.index and entry.index <= folder.last
end

--- Leave the stray's place without leaving a hole in the folder depths around it (as `delete` does).
local function detach(api, list, target)
  tracks.repair_depth(api, list, target)
  api.SetMediaTrackInfo_Value(target.track, "I_FOLDERDEPTH", 0)
end

--- Every send the mix receives becomes post-FX pre-fader.
local function convert_sends(api, mix)
  local done = {}
  for index = 0, api.GetTrackNumSends(mix.track, -1) - 1 do
    local source = api.GetTrackSendInfo_Value(mix.track, -1, index, "P_SRCTRACK")
    local guid = api.GetTrackGUID(source)
    if not done[guid] then
      done[guid] = true
      for _, send in ipairs(cell.sends_between(api, { track = source }, mix)) do
        api.SetTrackSendInfo_Value(source, 0, send, "I_SENDMODE", cell.SEND_MODE)
      end
    end
  end
end

function adopt.run(given)
  local api = given.api
  local list = tracks.scan(api)

  local target, code = tracks.find_mix(list, (given.fields or {}).guid)
  if not target then return tracks.refusal(code) end
  if in_folder(tracks.find_folder(list), target) then return tracks.refusal("not_a_stray") end

  local colour = tracks.colour(api)

  undo.run(api, "IEM Setup: adopt mix", function()
    detach(api, list, target)

    -- Depths changed: read the list again before placing the track.
    list = tracks.scan(api)
    local folder = tracks.find_folder(list)
    -- The old last member closed the folder; open_slot hands that closing to the stray. Kept to write it again after
    -- the reorder: REAPER rewrites folder depths around a reordered track (measured on real REAPER, issue 11).
    local old_last = folder and folder.open and folder.last > folder.index and list[folder.last + 1] or nil
    local at, depth = tracks.open_slot(api, list, folder, colour)

    -- A stray already at its slot needs no move, and a move that changes nothing still makes REAPER rewrite the
    -- depths around it (measured: it put a closing depth on the track after the stray), so skip it.
    if target.index ~= at then
      -- Read again: open_slot may have inserted the folder track, which `list` does not have.
      local was_selected = {}
      local after = tracks.scan(api)
      for _, entry in ipairs(after) do
        was_selected[entry.guid] = api.IsTrackSelected(entry.track)
        api.SetTrackSelected(entry.track, entry.guid == target.guid)
      end
      api.ReorderSelectedTracks(at, 0)
      for _, entry in ipairs(after) do
        api.SetTrackSelected(entry.track, was_selected[entry.guid])
      end
    end

    -- The two depths that make the stray the folder's last member, written after any reorder so REAPER's rewriting
    -- cannot undo them.
    if old_last then api.SetMediaTrackInfo_Value(old_last.track, "I_FOLDERDEPTH", 0) end
    api.SetMediaTrackInfo_Value(target.track, "I_FOLDERDEPTH", depth)
    api.SetMediaTrackInfo_Value(target.track, "B_MAINSEND", 0)
    tracks.set_colour(api, target.track, colour)
    convert_sends(api, target)
  end)
  return { status = "ok" }
end

return adopt
