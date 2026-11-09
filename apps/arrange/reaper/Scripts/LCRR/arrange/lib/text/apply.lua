-- The words for Apply: what LCRR_Arrange_Apply shows, and the run-log entry
-- lib/core/apply.lua writes, built from structured plans and results.
--
-- Pure: no `reaper.*`. The log lines live here rather than in the core because
-- they are wording; the core decides *when* they are written (before the
-- applier runs, so a run that fails halfway still has its record).

local validate = require("lib.validate")

local text = {}

text.TITLE = "Apply Arrangement"

text.IMPORT_QUESTION = "This project has no Arrangement sidecar yet. Import one from another file?"
text.IMPORT_PICKER_TITLE = "Import Arrangement sidecar"

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
  for _, request in ipairs(requests) do
    lines[#lines + 1] = ("  %s: %+.3fs"):format(request.name, request.seconds)
  end

  return table.concat({
    ("This Arrangement adjusts the Headroom of %d region(s):"):format(#lines),
    "",
    table.concat(lines, "\n"),
    "",
    "Headroom is RELATIVE: it moves each region's end from where it is now, so applying this "
      .. "Arrangement a second time moves those ends a second time. Every other part of a "
      .. "Repack can be run repeatedly without changing the result; this cannot.",
    "",
    "Each end is rounded to the nearest bar line, so a request under half a bar resolves to no "
      .. "change. The run log records what each one actually resolved to.",
    "",
    "Yes    -- repack, and apply the Headroom above.",
    "No     -- repack only, treating every Headroom as zero.",
    "Cancel -- do nothing. Nothing has been written yet.",
  }, "\n")
end

--- What a finished run tells the user.
--
-- Categories that permanently change the project beyond repositioning --
-- Padding, anchors, drops -- are called out separately rather than folded
-- into the counts, because each adds or removes something the project
-- afterwards cannot be read back to explain.
-- @param result table lib/core/apply.lua's `run` result with status "ok"
function text.summary(result)
  local name, plan, anchor_plan = result.name, result.plan, result.anchor_plan
  if result.noop then
    return ("Arrangement %q already matches the timeline. Nothing to do."):format(name)
  end

  local summary = ("Applied %q: %d region(s), %d marker(s), %d tempo marker(s), %d envelope point(s) "
    .. "and %d item(s) moved, %d cut(s) made.")
    :format(name, #plan.places, #plan.marker_moves, #plan.tempo_moves, #plan.envelope_moves,
      #plan.item_moves, #plan.splits)

  if anchor_plan.changing > 0 then
    summary = summary .. ("\n\n%d Tempo Anchor(s) were written at region starts (%d of %d region(s) "
      .. "already had one with the right values), so each region carries its own bar grid "
      .. "regardless of what a Repack puts in front of it."):format(
      anchor_plan.changing, #anchor_plan.anchors - anchor_plan.changing, #anchor_plan.anchors)
  end

  -- Headroom first among the permanent effects, because it is the only one the
  -- user asked for by name -- and the only one a second run would do again.
  if #plan.headroom > 0 then
    local lines = {}
    for _, entry in ipairs(plan.headroom) do
      lines[#lines + 1] = ("%s: %+.3fs (%+d bar(s))%s"):format(
        entry.name, entry.resolved, entry.bars,
        entry.resolved == 0 and " -- no change, the request was under half a bar" or "")
    end
    summary = summary .. ("\n\n%d region(s) had their end moved by HEADROOM:\n  %s\n\nThis is "
      .. "relative, not absolute -- applying this Arrangement again would move them again.")
      :format(#plan.headroom, table.concat(lines, "\n  "))
  end

  -- Padding is the one category that puts *silence inside a region's bounds*,
  -- permanently (ADR-0004). The user has not seen it happen before, so it is
  -- reported with the exact amount rather than as a count.
  if #plan.pads > 0 then
    local added, names = 0, {}
    for _, pad in ipairs(plan.pads) do
      added = added + pad.added
      names[#names + 1] = ("%s (+%.3fs)"):format(pad.name, pad.added)
    end
    summary = summary .. ("\n\n%d region(s) were PADDED to the next bar line, adding %.3fs of "
      .. "silence inside their bounds -- permanently, and this does not happen again on a later "
      .. "Repack:\n  %s"):format(#plan.pads, added, table.concat(names, "\n  "))
  end

  if #plan.envelope_anchors > 0 then
    summary = summary .. ("\n\n%d automation anchor(s) were written at region bounds, so each "
      .. "region keeps its own automation values instead of inheriting its new neighbour's. "
      .. "They are listed in the run log."):format(#plan.envelope_anchors)
  end

  -- Parking moves material the Arrangement did not ask for, so it is reported
  -- even though it destroys nothing: an omitted region vanishing from where it
  -- used to sit looks like a deletion until the offset explains it.
  if #plan.parks > 0 then
    local regions_parked = 0
    for _, park in ipairs(plan.parks) do
      if park.kind == "region" then
        regions_parked = regions_parked + 1
      end
    end
    summary = summary .. ("\n\n%d region(s) this Arrangement omits, and %d other piece(s) of "
      .. "material, were PARKED %.3fs later -- beyond the Packed Block, with their internal "
      .. "timing intact. Nothing was deleted; the run log gives the offset, and negating it "
      .. "reverses the parking."):format(regions_parked, #plan.parks - regions_parked, plan.park_delta)
  end

  -- Drops are called out separately, and last, because they are the only
  -- destructive part of a run -- the log beside the .RPP lists each one.
  local discarded = #plan.drops + #plan.envelope_drops
  if discarded > 0 then
    summary = summary .. ("\n\n%d piece(s) of material and %d envelope point(s) touching no region "
      .. "were DISCARDED. They are listed in the run log beside the project; Undo restores them."):format(
      #plan.drops, #plan.envelope_drops)
  end

  return summary
end

-- Why a run stopped, worded. Each takes the refusal's fields.
local ERRORS = {
  project_unsaved = function(err)
    return err.message
  end,
  tempo_env_beats = function(err)
    return err.message
  end,
  no_regions = function()
    return "This project has no regions, so there is no Arrangement to apply."
  end,
  region_names = function(err)
    return table.concat({
      "Cannot apply an Arrangement until every region has a unique, non-empty name:",
      "",
      validate.format_problems(err.problems),
      "",
      "Run 'Find duplicate or unnamed regions' for the full list.",
    }, "\n")
  end,
  sidecar_invalid = function(err)
    return ("The Arrangement sidecar exists but could not be read:\n\n%s"):format(err.error)
  end,
  -- Never shown by the dialog front end, which offers the import instead. Any
  -- other front end names the host action to run.
  sidecar_missing = function()
    return "This project has no Arrangement sidecar yet. Capture an Arrangement, or run "
      .. "'Apply Arrangement' in REAPER to import one."
  end,
  import_unreadable = function(err)
    return ("Could not read %s: %s"):format(err.path, err.error or "unknown error")
  end,
  import_invalid = function(err)
    return ("%s is not a valid Arrangement sidecar:\n\n%s"):format(err.path, err.error)
  end,
  save_failed = function(err)
    return err.error
  end,
  no_arrangements = function()
    return "The Arrangement sidecar has no Arrangements to apply."
  end,
  arrangement_unknown = function(err)
    return ("%q is not a known Arrangement. Available: %s")
      :format(err.name, table.concat(err.available, ", "))
  end,
  arrangement_missing_regions = function(err)
    return ("Arrangement %q names regions this project does not have:\n\n  %s")
      :format(err.name, table.concat(err.missing, "\n  "))
  end,
  plan_refused = function(err)
    return err.error
  end,
  plan_out_of_scope = function(err)
    return ("Arrangement %q needs more than this action can do yet:\n\n%s"):format(err.name, err.error)
  end,
  anchors_moved_items = function(err)
    return table.concat({
      "Writing the Tempo Anchors moved media items, so this run has been stopped before "
        .. "it planned anything against the moved timeline.",
      "",
      "Beat-attached material follows a tempo-map edit, and these items followed one:",
      "",
      validate.format_problems(err.moved),
    }, "\n")
  end,
}

--- A refusal, worded. One that arrives after phase 1 wrote its anchors says
--- so, and that Undo removes them.
function text.error(err)
  local format_one = ERRORS[err.code]
  local message = format_one and format_one(err) or err.code
  if err.anchors_written then
    message = ("%s\n\n%d Tempo Anchor(s) were written before this was detected, and nothing "
      .. "else was. They are one undo step -- Undo removes them."):format(message, err.anchors_written)
  end
  return message
end

return text
