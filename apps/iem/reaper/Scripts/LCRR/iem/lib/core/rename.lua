-- The `rename` core: a mix gets another name. The prefix is the bridge's, never
-- typed. An empty name, or one another mix already has, is refused; two mixes
-- that already share a name can be renamed apart. Naming a mix what it already
-- is changes nothing and opens no undo step.
--
--   rename.run({ api, fields = { guid, name } })
--     -> { status = "ok", changed }
--      | { status = "refused", error = { code } }
--   codes: track_gone, not_a_mix, empty_name, duplicate_name

local tracks = require("lib.core.tracks")
local undo = require("lib.core.undo")

local rename = {}

function rename.run(given)
  local api = given.api
  local fields = given.fields or {}
  local list = tracks.scan(api)

  local target, code = tracks.find_mix(list, fields.guid)
  if not target then return tracks.refusal(code) end

  -- Its own name, even one a duplicate shares, is no change.
  local typed = (fields.name or ""):match("^%s*(.-)%s*$")
  if tracks.MIX_PREFIX .. typed == target.name then return { status = "ok", changed = false } end

  local name, why = tracks.check_name(list, fields.name, target)
  if not name then return tracks.refusal(why) end

  local full = tracks.MIX_PREFIX .. name

  undo.run(api, "IEM Setup: rename mix", function()
    api.GetSetMediaTrackInfo_String(target.track, "P_NAME", full, true)
  end)
  return { status = "ok", changed = true }
end

return rename
