-- The `row` and `column` cores: switch a whole source row, or a whole mix column, on or off (issue 08).
--
--   bulk.row.run({ api, fields = { source, on } })    -- one source, every mix
--   bulk.column.run({ api, fields = { mix, on } })    -- one mix, every source
--     -> { status = "ok", changed, count }
--      | { status = "refused", error = { code } }
--
-- The request carries only the ID of the row's source or the column's mix and `on` ("1" or anything else = off); the
-- bridge works out the other side from the project, so the request stays small however many tracks there are.
-- On adds the missing sends only (post-FX pre-fader, 0 dB, as `cell` does) and leaves every existing send alone: its
-- level, mode and mute. Off removes EVERY send of each pair, with no warning (the page's press-and-hold is the guard).
-- Sends are numbered per source, so removals are grouped by source and run highest index first across all of its pairs
-- (removing one send renumbers every later one of that source).
-- A mix is any `IEM_<name>` track, stray or not; a source is any other track except the IEMs folder, as in `cell`.
-- `changed` is false when nothing needed doing (no undo step); `count` is the sends added or removed.
-- One undo step each ("IEM Setup: switch row on" ...). Refusals are decided before the block opens: `track_gone`,
-- `not_a_source` (row) / `not_a_mix` (column).

local tracks = require("lib.core.tracks")
local cell = require("lib.core.cell")

local bulk = { row = {}, column = {} }

--- Scan, resolve the row's or column's pairs (`resolve(list)` returns the pairs, or nil and a refusal code), refuse
--- before any block opens, then switch.
local function run(given, kind, resolve)
  local api, fields = given.api, given.fields or {}
  local list = tracks.scan(api)
  local pairs_list, code = resolve(list, fields)
  if not pairs_list then return tracks.refusal(code) end
  return cell.switch(api, kind, fields.on == "1", pairs_list)
end

function bulk.row.run(given)
  return run(given, "row", function(list, fields)
    local source = tracks.find_by_guid(list, fields.source or "")
    if not source then return nil, "track_gone" end
    if not tracks.is_source(list, source) then return nil, "not_a_source" end
    local pairs_list = {}
    for _, entry in ipairs(list) do
      if tracks.is_mix_name(entry.name) then pairs_list[#pairs_list + 1] = { source, entry } end
    end
    return pairs_list
  end)
end

function bulk.column.run(given)
  return run(given, "column", function(list, fields)
    local mix, code = tracks.find_mix(list, fields.mix)
    if not mix then return nil, code end
    local pairs_list = {}
    for _, entry in ipairs(list) do
      if tracks.is_source(list, entry) then pairs_list[#pairs_list + 1] = { entry, mix } end
    end
    return pairs_list
  end)
end

return bulk
