-- The `move_to_end` core: the IEMs folder and its mixes go to the end of the
-- track list, in order, with depths, sends and GUIDs kept
-- (`ReorderSelectedTracks`, suite CONTEXT.md). It runs only when asked, and
-- only when tracks sit after the folder. The track selection the engineer had
-- is put back afterwards. One undo step.
--
--   move_to_end.run({ api, fields = { guid } })     -- the folder's GUID
--     -> { status = "ok" }
--      | { status = "refused", error = { code } }
--   codes: track_gone, not_the_folder, nothing_to_move

local tracks = require("lib.core.tracks")
local undo = require("lib.core.undo")

local move_to_end = {}

function move_to_end.run(given)
  local api = given.api
  local list = tracks.scan(api)

  local target = tracks.find_by_guid(list, (given.fields or {}).guid or "")
  if not target then return tracks.refusal("track_gone") end
  local folder = tracks.find_folder(list)
  if not folder or folder.entry ~= target then return tracks.refusal("not_the_folder") end
  if folder.last >= #list - 1 then return tracks.refusal("nothing_to_move") end

  undo.run(api, "IEM Setup: move IEMs folder to end", function()
    local was_selected = {}
    for _, entry in ipairs(list) do
      was_selected[entry.guid] = api.IsTrackSelected(entry.track)
      api.SetTrackSelected(entry.track, entry.index >= folder.index and entry.index <= folder.last)
    end
    api.ReorderSelectedTracks(#list, 0)
    for _, entry in ipairs(list) do
      api.SetTrackSelected(entry.track, was_selected[entry.guid])
    end
  end)
  return { status = "ok" }
end

return move_to_end
