-- The `create` core: a new mix, by name only. The first one also makes the
-- `IEMs` folder at the end of the track list; later ones go inside it, after
-- the folder's last member. Master send is off on the folder and the mix, both
-- take the shared colour, and REAPER's folder depth is set by hand (it does not
-- repair it, suite CONTEXT.md): the old last member stops closing the folder
-- and the new mix closes it. All of it is one undo step.
--
--   create.run({ api, fields = { name } })
--     -> { status = "ok", guid, folder_created }
--      | { status = "refused", error = { code = "empty_name" | "duplicate_name" } }

local tracks = require("lib.core.tracks")
local undo = require("lib.core.undo")

local create = {}

local function new_track(api, at, name, depth, colour)
  api.InsertTrackAtIndex(at, false)
  local track = api.GetTrack(0, at)
  api.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  api.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", depth)
  api.SetMediaTrackInfo_Value(track, "B_MAINSEND", 0)
  tracks.set_colour(api, track, colour)
  return track
end

function create.run(given)
  local api = given.api
  local list = tracks.scan(api)
  local name, code = tracks.check_name(list, (given.fields or {}).name, nil)
  if not name then
    return tracks.refusal(code)
  end

  local colour = tracks.colour(api)
  local folder = tracks.find_folder(list)
  local result = { status = "ok", folder_created = folder == nil }

  undo.run(api, "IEM Setup: create mix", function()
    local at, depth
    if not folder then
      -- At the end of the list, so nothing is swallowed; the mix follows it.
      new_track(api, #list, tracks.FOLDER_NAME, 1, colour)
      at, depth = #list + 1, -1
    elseif folder.open and folder.last > folder.index then
      -- The old last member closed the folder (and maybe parents of it): the
      -- new one takes over that closing.
      local last = list[folder.last + 1]
      depth = math.min(last.depth, -1)
      api.SetMediaTrackInfo_Value(last.track, "I_FOLDERDEPTH", 0)
      at = folder.last + 1
    elseif folder.open then
      at, depth = folder.index + 1, -1 -- an open folder with nothing in it
    else
      -- An emptied folder is a plain track: open it, and let the mix close it
      -- along with whatever the folder itself used to close.
      depth = folder.depth - 1
      api.SetMediaTrackInfo_Value(folder.entry.track, "I_FOLDERDEPTH", 1)
      at = folder.index + 1
    end
    local mix = new_track(api, at, tracks.MIX_PREFIX .. name, depth, colour)
    result.guid = api.GetTrackGUID(mix)
  end)

  return result
end

return create
