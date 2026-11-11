-- The `colour` core: the one colour of the folder and every mix in it. It is
-- stored in the project (so it survives a reload and rides with the .rpp) and
-- applied to the folder, the mixes inside it and the cue track; a stray mix is left alone
-- until it is adopted. One undo step.
--
--   colour.run({ api, fields = { colour = "rrggbb" } })
--     -> { status = "ok", colour } | { status = "refused", error = { code = "bad_colour" } }

local tracks = require("lib.core.tracks")
local undo = require("lib.core.undo")

local colour = {}

function colour.run(given)
  local api = given.api
  local hex = (given.fields or {}).colour
  if not tracks.valid_colour(hex) then
    return tracks.refusal("bad_colour")
  end
  hex = hex:lower()

  local list = tracks.scan(api)
  local folder = tracks.find_folder(list)

  undo.run(api, "IEM Setup: change colour", function()
    api.SetProjExtState(0, tracks.EXT_SECTION, tracks.EXT_COLOUR, hex)
    if not folder then return end
    tracks.set_colour(api, folder.entry.track, hex)
    for position = folder.index + 2, folder.last + 1 do
      local entry = list[position]
      if tracks.is_mix_name(entry.name) then tracks.set_colour(api, entry.track, hex) end
    end
    -- The cue track is part of the IEM set and wears the same colour, wherever it sits.
    local cue = tracks.find_cue(list)
    if cue then tracks.set_colour(api, cue.track, hex) end
  end)

  return { status = "ok", colour = hex }
end

return colour
