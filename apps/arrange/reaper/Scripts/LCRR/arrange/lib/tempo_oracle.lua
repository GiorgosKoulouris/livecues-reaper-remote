-- The real tempo oracle: where bar lines come from (ADR-0006).
--
-- `lib/regions.lua` is a pure planner and cannot answer two questions, because
-- both need REAPER's own tempo integration -- linear ramps, partial measures,
-- `/8` signatures -- over a tempo map that includes the Tempo Anchors the run
-- is about to write:
--
--   * `next_bar_at_or_after(time)` -- where does Padding extend a region to?
--   * `tempo_at(time)` -- what tempo and time signature does a Tempo Anchor
--     carry? Mid-ramp this is not any marker's bpm, so reading the nearest
--     marker writes the wrong anchor.
--
-- ADR-0006 rejected reimplementing that integration in Lua: it would be
-- unverifiable from a container REAPER cannot be reached from, precisely where
-- it is most likely to be wrong. So this module is deliberately thin -- it asks
-- REAPER and translates, and holds **no bar arithmetic of its own**. Adding any
-- would defeat the point of the ADR; if a future change seems to need some, that
-- is a sign the wrong `TimeMap` call is being used.
--
-- This is the only file in `lib/` that calls `reaper.*` outside `lib/apply.lua`,
-- and it does so read-only. ADR-0001 confines `reaper.*` to thin appliers; an
-- oracle is the other half of the same pattern -- the planner's dependency is a
-- parameter, injected, and faked in specs.
--
-- API facts are researched in `research/reaper-scripting.md` §4.5, taken verbatim
-- from the v7.78 reference (the version this suite runs against) and from Cockos's
-- own SDK header. Read that before changing a call here; the section also records
-- why the obvious-looking `TimeMap2_GetDividedBpmAtTime` is the wrong function.

local tempo_oracle = {}

-- Time comparisons here mirror lib/regions.lua's BOUNDARY_TOLERANCE, and for the
-- same reason: a bar line REAPER computed is being compared against a region end
-- a human dragged. Real project data misses exact bar lines by microseconds, and
-- at a tighter tolerance an already-aligned region reads as needing a whole extra
-- bar of Padding (lib/regions.lua's `pad_regions` comment has the measurements).
--
-- Taken from `lib/regions.lua` rather than redeclared, so the two cannot drift:
-- the oracle deciding "already on a bar line" and the planner deciding "worth
-- padding" have to agree, or a pad of nearly-zero length gets planned.
local regions = require("lib.regions")
local TOLERANCE = regions.BOUNDARY_TOLERANCE

-- How far the measure-bracket search below will walk before giving up. A wrong
-- measure-index base costs one step; anything beyond a couple means an
-- assumption in §4.5 is wrong, and looping forever inside a REAPER action would
-- hang the DAW with no message.
local MAX_MEASURE_PROBE = 8

--- Build an oracle bound to a project.
-- @param api table the reaper API table (injected so specs can fake it)
-- @param proj ReaProject|number project, 0 for the active one
-- @return table { next_bar_at_or_after, tempo_at }
function tempo_oracle.new(api, proj)
  proj = proj or 0

  -- The seconds position at which `measure` starts.
  --
  -- TimeMap_GetMeasureInfo's *return value* is that time in seconds -- "Return
  -- the time in seconds of the measure start" (§4.5, verbatim). The QN outputs
  -- are not needed, so there is no round trip through TimeMap2_QNToTime.
  local function measure_start(measure)
    return (api.TimeMap_GetMeasureInfo(proj, measure))
  end

  -- Which measure contains `time`, as an index `measure_start` agrees with.
  --
  -- **Measured: REAPER numbers measures from 0, and the two calls share the
  -- base** (§4.5, issue #14 -- `LCRR_Arrange_ShowBarLines` on `repack_bars`, REAPER
  -- 7.78/win64, 2026-08-05). Neither the v7.78 reference nor the SDK header
  -- states it, so this is an observation on one version rather than a
  -- documented guarantee. An off-by-one would be **silent**: Padding would add
  -- a whole bar to every region -- 1.4 to 2.4 s at the live project's tempos
  -- -- and then abort the run on any back-to-back region pair.
  --
  -- So the base is not trusted anyway. `measures` is taken as a starting guess
  -- and the bracket `measure_start(m) <= time < measure_start(m + 1)` is
  -- *verified*, stepping until it holds. Whichever base REAPER uses, the
  -- bracket is the definition of "the measure containing `time`", so this is
  -- correct under either -- and it also absorbs any rounding at a measure
  -- boundary, which the measurement above does not make unnecessary.
  --
  -- Kept now as belt-and-braces against a known base rather than a guard
  -- against an unknown one. `MAX_MEASURE_PROBE` should therefore never be
  -- reached; if it ever is, the base has moved and §4.5 is stale.
  -- `LCRR_Arrange_ShowBarLines.lua` still prints the raw index alongside the
  -- corrected one, which is how the base was read off in the first place.
  local function measure_containing(time)
    local _, measures = api.TimeMap2_timeToBeats(proj, time)
    local measure = measures or 0

    for _ = 1, MAX_MEASURE_PROBE do
      local this_start = measure_start(measure)
      if this_start - time > TOLERANCE then
        measure = measure - 1
      elseif time - measure_start(measure + 1) > -TOLERANCE then
        measure = measure + 1
      else
        return measure, this_start
      end
    end

    -- Deliberately an error rather than a best guess. A silently wrong measure
    -- pads every region by a bar; the caller (a script) turns this into a
    -- ShowMessageBox abort, which is the convention for a precondition failure
    -- (CLAUDE.md) and leaves the project untouched.
    error(("tempo oracle could not bracket a measure around %.6fs after %d probes -- "):format(
      time, MAX_MEASURE_PROBE)
      .. "see research/reaper-scripting.md §4.5 on TimeMap measure indexing", 0)
  end

  --- The first bar line at or after `time`.
  -- Returns `time` itself when it is already on a bar line, to within
  -- TOLERANCE, which is what makes Padding idempotent (ADR-0004).
  local function next_bar_at_or_after(time)
    local measure, this_start = measure_containing(time)
    if time - this_start <= TOLERANCE then
      -- Already on this measure's line. Return REAPER's own value for it rather
      -- than `time`, so a bound that is a few microseconds off snaps to the grid
      -- when it is genuinely being padded -- `pad_regions` discards a difference
      -- this small anyway, so this only matters to callers that want the true
      -- bar line, like the diagnostic script.
      return this_start
    end
    return measure_start(measure + 1)
  end

  --- The bar line at or before `time` -- the start of the measure it sits in.
  --
  -- The other side of `next_bar_at_or_after`, and needed for exactly one
  -- question: which of the two bar lines bracketing a target is *nearest* it,
  -- which is how a Headroom request in seconds resolves to a bar line
  -- (lib/regions.lua). Without it the planner could only ever round up, and a
  -- shrink has no upward answer.
  --
  -- Still no bar arithmetic here, per this module's own rule: the measure
  -- bracket `measure_containing` already established *is* the answer.
  local function bar_at_or_before(time)
    local _, this_start = measure_containing(time)
    return this_start
  end

  --- The first bar line strictly after `time`.
  --
  -- `next_bar_at_or_after` cannot answer this, because on a bar line it
  -- returns that line. Two callers need the next one instead: the one-bar
  -- floor under a shrink, measured from a region start that is itself a bar
  -- line, and counting how many bars a resolved Headroom actually moved.
  local function bar_after(time)
    local measure = measure_containing(time)
    return measure_start(measure + 1)
  end

  --- The tempo and time signature in effect at `time`.
  -- One call: `TimeMap_GetTimeSigAtTime` returns the *effective* values, which
  -- is what a Tempo Anchor mid-ramp needs.
  --
  -- **It is `void` in C, so there is no `retval`** -- the Lua form returns
  -- exactly three values and the first is `timesig_num` (§4.5). Reading it as
  -- `retval, num, denom` would shift every field and write anchors with a
  -- time signature made of a tempo.
  --
  -- Returned in the order `lib/regions.lua`'s `plan_anchors` expects,
  -- bpm first, which is *not* the order REAPER returns them in.
  local function tempo_at(time)
    local timesig_num, timesig_denom, bpm = api.TimeMap_GetTimeSigAtTime(proj, time)
    return bpm, timesig_num, timesig_denom
  end

  return {
    next_bar_at_or_after = next_bar_at_or_after,
    bar_at_or_before = bar_at_or_before,
    bar_after = bar_after,
    tempo_at = tempo_at,
  }
end

return tempo_oracle
