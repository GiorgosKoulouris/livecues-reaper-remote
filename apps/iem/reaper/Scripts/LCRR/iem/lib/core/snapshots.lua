-- The `snapshots` core: list what is saved. Read-only; the index carries each snapshot's name, when it was saved and
-- how many mixes and sends it holds, never its contents, so the reply stays small however large a snapshot is.
--
--   snapshots.run({ api })
--     -> { status = "ok", snapshots = { { name, saved, mixes, sends } } }
--      | { status = "refused", error = { code = "unreadable" } }

local tracks = require("lib.core.tracks")
local store = require("lib.core.snapshot_store")

local snapshots = {}

function snapshots.run(given)
  local list, code = store.list(given.api)
  if not list then return tracks.refusal(code) end
  local out = {}
  for _, e in ipairs(list) do
    out[#out + 1] = { name = e.name, saved = e.saved, mixes = e.mixes, sends = e.sends }
  end
  return { status = "ok", snapshots = out }
end

return snapshots
