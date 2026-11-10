-- The `snapshots` core: list what is saved. Read-only; the index carries each snapshot's name, when it was saved, how
-- many tracks (the Master not counted) and sends (hardware outputs included) it holds and its marks, never its
-- contents, so the reply stays small however large a snapshot is.
--
--   snapshots.run({ api })
--     -> { status = "ok", snapshots = { { name, saved, tracks, sends, solo, master_muted } } }
--      | { status = "refused", error = { code = "unreadable" } }

local store = require("lib.core.snapshot_store")

local snapshots = {}

function snapshots.refusal(code)
  return { status = "refused", error = { code = code } }
end

function snapshots.run(given)
  local list, code = store.list(given.api)
  if not list then return snapshots.refusal(code) end
  local out = {}
  for _, e in ipairs(list) do
    out[#out + 1] = {
      name = e.name, saved = e.saved, tracks = e.tracks, sends = e.sends,
      solo = e.marks & store.MARK_SOLO ~= 0, master_muted = e.marks & store.MARK_MASTER_MUTED ~= 0,
    }
  end
  return { status = "ok", snapshots = out }
end

return snapshots
