-- The `delete` core: a mix goes, with its sends (REAPER removes them with the
-- track). REAPER does not repair folder depth when a track is deleted (suite
-- CONTEXT.md), so the neighbours' depths are fixed in the same undo step:
--
--   * a mix that closed levels (depth < 0) hands them to the track before it,
--     which adds them to its own depth. The folder's previous member then closes
--     the folder; when the folder's only mix goes, the folder (depth 1) ends at
--     0, a plain track, or at a negative depth when the mix closed beyond it.
--     A stray inside some other folder is the same case one level out.
--   * a mix that opened a folder of its own (depth > 0) leaves the track that
--     closed that folder with that many fewer closings to do.
--
-- Only a mix can be deleted, never the folder or a source. Refusals are decided
-- before the undo block opens, so they leave no undo point.
--
--   delete.run({ api, fields = { guid } })
--     -> { status = "ok" }
--      | { status = "refused", error = { code } }
--   codes: track_gone, not_a_mix

local tracks = require("lib.core.tracks")
local undo = require("lib.core.undo")

local delete = {}

local function add_depth(api, entry, extra)
  api.SetMediaTrackInfo_Value(entry.track, "I_FOLDERDEPTH", entry.depth + extra)
end

function delete.run(given)
  local api = given.api
  local list = tracks.scan(api)

  local target, code = tracks.find_mix(list, (given.fields or {}).guid)
  if not target then return tracks.refusal(code) end

  local position = target.index + 1

  undo.run(api, "IEM Setup: delete mix", function()
    if target.depth < 0 and position > 1 then
      add_depth(api, list[position - 1], target.depth)
    elseif target.depth > 0 then
      local level = target.depth
      for next_position = position + 1, #list do
        level = level + list[next_position].depth
        if level <= 0 then
          add_depth(api, list[next_position], target.depth)
          break
        end
      end
    end
    api.DeleteTrack(target.track)
  end)
  return { status = "ok" }
end

return delete
