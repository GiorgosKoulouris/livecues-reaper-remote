-- Show Bar Lines, headless: for every region, where its bounds sit on the bar
-- grid and how much Padding a Repack would add. Asks the real tempo oracle
-- exactly the questions a Repack does, and writes nothing -- not even the run
-- log: this is a diagnostic, and its front end decides where the answer goes.
--
--   local result = bars.run({ api = reaper })

local env_lib = require("lib.core.env")
local regions = require("lib.regions")

local bars = {}

bars.TITLE = "Show bar lines"

--- @return table a refusal with code no_regions, or
---   { status = "ok", region_reader, origin_measure, origin = { bpm, num,
---     denom }, pad_threshold, regions = { { name, start_time, end_time, bpm,
---     num, denom, start_bar, end_bar, pad, pads, on_bar } }, padded,
---     total_pad, project_path }
function bars.run(given)
  local env = env_lib.new(given)
  local snapshot = env.snapshot()

  if #snapshot.regions == 0 then
    return env_lib.refused({ code = "no_regions" })
  end

  local oracle = env.tempo()

  local ordered = {}
  for _, region in ipairs(snapshot.regions) do
    ordered[#ordered + 1] = region
  end
  table.sort(ordered, function(a, b) return a.start_time < b.start_time end)

  -- The measure-index question, answered directly rather than inferred. Both
  -- calls are asked about the timeline origin: whatever index REAPER reports for
  -- time 0 is its base (research/reaper-scripting.md §4.5).
  local _, origin_measure = env.api.TimeMap2_timeToBeats(0, 0)
  local bpm, num, denom = oracle.tempo_at(0)

  local rows, total_pad, padded = {}, 0, 0
  for _, region in ipairs(ordered) do
    local start_bar = oracle.next_bar_at_or_after(region.start_time)
    local end_bar = oracle.next_bar_at_or_after(region.end_time)
    local pad = end_bar - region.end_time
    -- Decided the same way plan_pack decides it, so this cannot disagree with
    -- what a real run would do.
    local pads = pad > regions.BOUNDARY_TOLERANCE
    if pads then
      total_pad = total_pad + pad
      padded = padded + 1
    end

    local start_bpm, start_num, start_denom = oracle.tempo_at(region.start_time)
    rows[#rows + 1] = {
      name = region.name,
      start_time = region.start_time,
      end_time = region.end_time,
      bpm = start_bpm,
      num = start_num,
      denom = start_denom,
      start_bar = start_bar,
      end_bar = end_bar,
      pad = pad,
      pads = pads,
      -- A start off the grid is not a problem to fix here: phase 1's Tempo
      -- Anchor puts every region start on a bar line by starting a new measure
      -- there. It says how much the anchor will change.
      on_bar = math.abs(start_bar - region.start_time) < regions.BOUNDARY_TOLERANCE,
    }
  end

  return {
    status = "ok",
    -- Which reader the snapshot came through (issue #11). Reported by this
    -- action above all, because it is read-only: it is how the new reader can
    -- be checked against a real project without anything being written.
    region_reader = snapshot.region_reader,
    origin_measure = origin_measure,
    origin = { bpm = bpm, num = num, denom = denom },
    pad_threshold = regions.BOUNDARY_TOLERANCE,
    regions = rows,
    padded = padded,
    total_pad = total_pad,
    project_path = snapshot.project_path,
  }
end

return bars
