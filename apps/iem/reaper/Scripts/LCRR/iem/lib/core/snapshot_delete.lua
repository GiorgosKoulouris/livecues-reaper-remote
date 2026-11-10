-- The `snapshot_delete` core: remove a saved snapshot by name. No undo block and no undo step (project ExtState
-- ignores undo); the page's press and hold is the only protection.
--
--   snapshot_delete.run({ api, fields = { name } })
--     -> { status = "ok" } | refused: `empty_name`, `bad_name`, `name_too_long`, `not_found`, `unreadable`

local tracks = require("lib.core.tracks")
local store = require("lib.core.snapshot_store")

local snapshot_delete = {}

function snapshot_delete.run(given)
  local api = given.api
  local name, code = store.clean_name((given.fields or {}).name)
  if not name then return tracks.refusal(code) end
  local list, bad = store.list(api)
  if not list then return tracks.refusal(bad) end
  local entry = store.find(list, name)
  if not entry then return tracks.refusal("not_found") end
  store.remove(api, list, entry)
  return { status = "ok" }
end

return snapshot_delete
