-- The words for Apply: what LCRR_Arrange_Apply shows, and the run-log entry
-- lib/core/apply.lua writes, built from structured plans and results.
--
-- Pure: no `reaper.*`. The log lines live here rather than in the core because
-- they are wording; the core decides *when* they are written (before the
-- applier runs, so a run that fails halfway still has its record).

local effects = require("lib.text.effects")
local refusals = require("lib.text.refusals")

local text = {}

text.TITLE = "Apply Arrangement"

text.IMPORT_QUESTION = "This project has no Arrangements yet. Import an Arrangement file?"
text.IMPORT_PICKER_TITLE = "Import an Arrangement file"

--- What the script shows when an error is raised during the run: plain
--- instructions. The raw error is in the run log (`failure_line`).
function text.failure()
  return refusals.failure()
end

-- track_index is 0-based, as REAPER's own enumeration is, while its UI
-- counts from 1 -- printing the raw index sends the reader one track off
-- by one. Envelope points can also carry the master track's
-- sentinel index (project.MASTER_TRACK_INDEX, -1), which is not a track at
-- all and must not be rendered as "track 0".
local function describe_track_number(track_index)
  if track_index < 0 then
    return "the master track"
  end
  return ("track %d"):format(track_index + 1)
end

--- The run-log heading for a Repack to `name`.
function text.heading(name)
  return ("%s -- %q"):format(text.TITLE, name)
end

--- The run-log line for a run that failed after its plan was logged (issue 10).
-- The plan logged above it is what the run *meant* to do; this says it stopped,
-- so the log is not read as a record of a finished run.
-- @param err any the error the applier raised
-- @return string
function text.failure_line(err)
  return ("  RUN FAILED: %s -- every step after the failing one was not done, and what came "
    .. "before it was. All of it is one REAPER undo step."):format(tostring(err))
end

--- The run log's body for one Repack: every decision the run made, one line
--- each, in the order the reader needs them.
-- @param snapshot table the snapshot the plan was made from
-- @param anchor_plan table lib/regions.lua's plan_anchors result
-- @param plan table lib/regions.lua's plan_pack result
-- @return table list of lines
function text.log_lines(snapshot, anchor_plan, plan)
  local lines = {}
  local function line(format, ...)
    lines[#lines + 1] = format:format(...)
  end

  -- Which reader the snapshot came through (issue #11). One line, always, so a
  -- run that silently fell back to the discouraged-but-proven enumerator says
  -- so in its own record rather than having to be inferred from a REAPER
  -- version afterwards.
  line("  regions read via %s", snapshot.region_reader)

  -- Tempo Anchors first, because they are phase 1 and everything below is
  -- planned against the grid they create. Redundant ones are logged too, marked,
  -- since "an anchor was already correct here" is part of the record of what the
  -- run decided -- and the project afterwards cannot distinguish an anchor from
  -- a tempo marker the user placed.
  for _, anchor in ipairs(anchor_plan.anchors) do
    line("  tempo anchor (region %q): %.3f = %g bpm %d/%d%s%s",
      anchor.region_name, anchor.time, anchor.bpm, anchor.timesig_num, anchor.timesig_denom,
      anchor.lineartempo and " ramped" or "",
      anchor.redundant and " (already present, rewritten)" or "")
  end
  -- Headroom is the one thing in a run the project afterwards cannot be read
  -- back to explain *at all*: a region is simply a different length, with
  -- nothing recording that it was asked for, by how much, or how many times.
  -- The resolved figures are logged rather than the requested ones, so the line
  -- matches the timeline; the request is kept beside it because a request that
  -- resolved to nothing is the likeliest thing to be asked about.
  for _, entry in ipairs(plan.headroom) do
    line("  HEADROOM %q: end %.3f -> %.3f (%+.3fs, %+d bar(s); asked %+.3fs)%s",
      entry.name, entry.from_end, entry.to_end, entry.resolved, entry.bars, entry.requested,
      entry.resolved == 0 and " -- no change, the request is under half a bar" or "")
  end
  -- Padding permanently grows a region and puts silence inside its bounds
  -- (ADR-0004), so every pad is named with what it added.
  for _, pad in ipairs(plan.pads) do
    line("  PADDED %q: end %.3f -> %.3f (+%.3fs of silence inside the region)",
      pad.name, pad.from_end, pad.to_end, pad.added)
  end
  for _, place in ipairs(plan.places) do
    line("  %s: %.3f -> %.3f (%+.3f)", place.name, place.from_start, place.to_start, place.delta)
  end
  for _, move in ipairs(plan.marker_moves) do
    line("  marker %q: %.3f -> %.3f (%+.3f)", move.name, move.from, move.to, move.delta)
  end
  for _, move in ipairs(plan.tempo_moves) do
    local label = move.kind == "park"
      and "tempo (parked, belonged to no region)"
      or ("tempo (region %q)"):format(move.region_name)
    line("  %s: %.3f -> %.3f (%+.3f)", label, move.from, move.to, move.delta)
  end
  -- Track numbers are logged the way REAPER's UI shows them, from 1, so a
  -- line can be acted on without re-deriving the offset.
  for _, move in ipairs(plan.envelope_moves) do
    line("  envelope (%s %s, %q, region %q): %.3f -> %.3f (%+.3f)",
      describe_track_number(move.track_index), move.track_name or "", move.envelope_name,
      move.region_name, move.from, move.to, move.delta)
  end
  -- Automation Anchors add points that were not there before, so the log is
  -- the only record of which value the run decided each region should carry
  -- at its bounds (lib/regions.lua's `envelope_anchors`).
  -- Marked the same way a Tempo Anchor is, and for a sharper reason since
  -- issue #13: an anchors-only plan is now a run rather than a silent
  -- no-op, so the log has to say which anchors were the reason. Without the
  -- mark every anchor reads alike and a run that happened *because* of one
  -- looks identical to a run that would have happened anyway.
  for _, anchor in ipairs(plan.envelope_anchors) do
    line("  automation anchor (%s %s, %q, region %q): %.3f = %.6f%s",
      describe_track_number(anchor.track_index), anchor.track_name or "",
      anchor.envelope_name, anchor.region_name, anchor.to, anchor.value,
      anchor.redundant and " (already present, rewritten)" or "")
  end
  -- The fade is reported because it is now the suite's own value rather than
  -- REAPER's split preference (ADR-0002, issue #15), and ADR-0002 asks that a
  -- cut edge be predictable from the plan alone. `plan.cut_fade` is one value
  -- for the whole run, so it is stated per line rather than in a header only
  -- because a reader diffing one cut should not have to go looking for it.
  for _, split in ipairs(plan.splits) do
    line("  cut (track %d %s): %.3f (%.3fs fade both edges)", split.track_index + 1,
      split.track_name or "", split.position, plan.cut_fade)
  end
  -- Dropped Material is the only category the project itself will not
  -- record afterwards, so these log lines are the whole record of it.
  for _, drop in ipairs(plan.drops) do
    line("  DROPPED (track %d %s): %.3f..%.3f (%.3fs)", drop.track_index + 1,
      drop.track_name or "", drop.position, drop.position + drop.length, drop.length)
  end
  for _, drop in ipairs(plan.envelope_drops) do
    line("  DROPPED envelope point (%s %s, %q): %.3f",
      describe_track_number(drop.track_index), drop.track_name or "", drop.envelope_name, drop.position)
  end
  for _, move in ipairs(plan.item_moves) do
    line("  item (track %d): %.3f -> %.3f (%+.3f)", move.track_index + 1, move.from, move.to, move.delta)
  end
  -- Parked Material last, and headed by the offset, because that single number
  -- is what makes parking reversible: negating it puts every line below back
  -- (issue #7). Without it in the log, the only record of where this material
  -- came from is Undo, which does not survive the session.
  if #plan.parks > 0 then
    line("  PARKED by %+.3fs (negate to reverse):", plan.park_delta)
    for _, park in ipairs(plan.parks) do
      if park.kind == "region" then
        line("    region %q: %.3f -> %.3f", park.name, park.from, park.to)
      elseif park.kind == "marker" then
        line("    marker %q: %.3f -> %.3f", park.name, park.from, park.to)
      elseif park.kind == "envelope" then
        line("    envelope point (%s %s, %q, region %q): %.3f -> %.3f",
          describe_track_number(park.track_index), park.track_name or "",
          park.envelope_name, park.region_name, park.from, park.to)
      else
        line("    item (track %d): %.3f -> %.3f", park.track_index + 1, park.from, park.to)
      end
    end
  end
  return lines
end

--- The confirmation shown before any region end is moved by a Headroom.
-- @param requests table lib/report.lua's `headroom_requests` (non-empty)
function text.headroom_prompt(requests)
  local lines = {}
  for index = 1, math.min(#requests, refusals.LIMIT) do
    lines[index] = ("  %s: %+.1f s"):format(requests[index].name, requests[index].seconds)
  end
  -- Nothing is logged yet at this point, so the rest is on the page, not in the log.
  if #requests > refusals.LIMIT then
    lines[#lines + 1] = ("  and %d more (see %s)"):format(#requests - refusals.LIMIT, refusals.EDIT_TAB)
  end

  return table.concat({
    ("Apply Headroom to %d %s?"):format(#requests, #requests == 1 and "region" or "regions"),
    "",
    table.concat(lines, "\n"),
    "",
    "Each Apply moves these region ends again.",
    "",
    "Yes - apply with Headroom",
    "No - apply without Headroom",
    "Cancel - do nothing",
  }, "\n")
end

--- What a finished run tells the user: done, the lasting effects, Undo, what
--- to do next. Everything else is in the run log.
-- @param result table lib/core/apply.lua's `run` result with status "ok"
function text.summary(result)
  local name = result.name
  if result.noop then
    return ("Arrangement %q already matches the timeline. Nothing to do."):format(name)
  end

  local parts = { ("Applied %q."):format(name) }
  local lines = effects.lines(effects.from_plan(result.plan), true)
  if #lines > 0 then
    local bullets = {}
    for index, line in ipairs(lines) do
      bullets[index] = "- " .. line
    end
    parts[#parts + 1] = table.concat(bullets, "\n")
  end
  parts[#parts + 1] = "Undo in REAPER takes it back.\nNext: run Verify."
  return table.concat(parts, "\n\n")
end

--- A refusal, worded.
function text.error(err)
  return refusals.error(err) or err.code
end

return text
