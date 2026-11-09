-- The Repack planner.
--
-- A pure function over plain tables (ADR-0001). Nothing here calls `reaper.*`;
-- everything it needs arrives in a snapshot, and the one question it cannot
-- answer from plain data -- where the bar lines fall -- arrives as an injected
-- `tempo` oracle.
--
-- Why the oracle, and why two phases
-- ----------------------------------
-- ADR-0004 makes bar alignment the invariant, which needs time<->bar conversion
-- over a tempo map that includes the Tempo Anchors this run is about to write.
-- Reimplementing REAPER's tempo integration (linear ramps, partial measures) in
-- Lua would be unverifiable from here, so a run instead goes:
--
--   1. `plan_anchors` -- decide Tempo Anchors. Needs no bar math: an anchor
--      records the tempo already in effect and starts a new measure, which is
--      what puts every region start on a bar line.
--   2. the applier writes them.
--   3. `plan_pack` -- Padding and placement, with `tempo` wrapping REAPER's
--      TimeMap functions, which now reflect the anchors.
--
-- Both phases live inside one undo block, so the run is still a single step.
--
-- Placement itself needs no bar math at all. Once a region starts on a bar line
-- and spans a whole number of bars, its tempo slice transplants rigidly: its
-- duration in seconds is invariant, so packing is a cumulative sum and the bar
-- alignment of every later region follows by construction.

local regions = {}

-- Bar lines come back as floats, so an exact equality test would record
-- meaningless sub-nanosecond pads and moves. This guards *computed* values
-- against each other -- pads, places, park offsets -- and stays tight.
local EPSILON = 1e-9

-- Tolerance for deciding whether a time lies inside a region, in seconds.
-- Separate from EPSILON, and four orders of magnitude looser, because it
-- compares two independently authored numbers rather than two computed ones.
--
-- Real project data is sloppier than IEEE noise. In
-- `spec/fixtures/repack_basic`, an item on track 29 runs 487.62775112175132
-- .. 737.72120906567670 inside region "Sleep Tight", whose end is
-- 737.72120671516768 -- an overhang of 2.35e-06s. One ULP at that magnitude
-- is ~1e-13, so this is not a summation artifact: the item genuinely ends
-- past the region, by 2.35 microseconds. Across that project's 321 items the
-- worst such discrepancy is 3.0e-05s, on both edges. At EPSILON these were
-- refused by the dozen as Straddling Items needing #6, and items starting a
-- few microseconds early were parked as Loose Items.
--
-- 1e-4 leaves ~3x headroom over the worst observed case while staying 50x
-- tighter than CUT_FADE: an overhang this small could not be split into a
-- fragment worth fading, let alone hearing. It is float-noise tolerance and
-- nothing more -- a genuine Straddling Item overruns by musical amounts, and
-- must still refuse.
--
-- Public because membership is not the planner's private business: lib/validate.lua
-- asks the same question of the same regions (issue #12) and has to get the same
-- answer, so the two must not drift apart.
regions.BOUNDARY_TOLERANCE = 1e-4
local BOUNDARY_TOLERANCE = regions.BOUNDARY_TOLERANCE

-- Gap left between the Packed Block and Parked Material, in seconds.
-- CONTEXT.md requires only "beyond the Packed Block"; the exact distance is
-- this suite's choice, fixed here so it is predictable from the plan alone.
--
-- Five minutes, chosen to be longer than any single region in the live project.
-- The gap is the only thing marking where a Repack's output ends and its
-- leftovers begin, and at 30s -- the first value used here -- it read as an
-- ordinary gap between songs at normal zoom. Being wider than the material on
-- either side of it makes it unambiguous instead.
regions.PARK_GAP = 300

-- Fade applied to the edges a split creates, in seconds (ADR-0002). The suite
-- defines this rather than inheriting REAPER's split preference, so behaviour
-- is reproducible across machines. Original outer fades are preserved.
regions.CUT_FADE = 0.005

-- REAPER's envelope point shapes: 0 linear, 1 square, 2 slow start/end,
-- 3 fast start, 4 fast end, 5 bezier. Square is the one that holds a value
-- forward instead of interpolating to the next point, which is what a region
-- bound needs (see `envelope_anchors`).
local SQUARE_SHAPE = 1

-- Which Automation Anchors are written together. `apply.envelope_anchors`
-- clears a time and writes the whole group at once, and `plan_pack` decides
-- redundancy over the same unit -- so the two must agree on what a group *is*.
-- Shared here rather than spelt out twice: the planner would otherwise judge a
-- group the applier never writes, silently, and only where two anchors meet.
-- @param track_index number 0-based, or project.MASTER_TRACK_INDEX
-- @param envelope_name string
-- @param time number the anchor's final position
-- @return string
function regions.anchor_group_key(track_index, envelope_name, time)
  return ("%d\0%s\0%.9f"):format(track_index, envelope_name, time)
end

local function nearly_equal(a, b)
  return math.abs(a - b) < EPSILON
end

-- Does a tempo marker carry a time signature of its own? REAPER's tempo
-- markers hold tempo and signature in one object, and a tempo-only one reports
-- its signature as `-1/-1`. `0/0` is the other absent value, and a meaningful
-- one: passed to `SetTempoTimeSigMarker` it means "keep the previous
-- signature" (research §4.4a).
local function has_timesig(marker)
  return (marker.timesig_num or 0) > 0 and (marker.timesig_denom or 0) > 0
end

-- How a refused item's track is named back to the user, who is about to go
-- and find it. `track_index` is 0-based, matching REAPER's own enumeration,
-- but its UI numbers tracks from 1 -- printing the raw index sends the reader
-- one track off, which happened for real against the live project. The name
-- is what actually makes a track findable in a 32-track session; it is
-- advisory only, since REAPER neither requires nor guarantees one.
local function describe_track(entry)
  local number = ("track %d"):format(entry.track_index + 1)
  if entry.track_name and entry.track_name ~= "" then
    return ("%s %q"):format(number, entry.track_name)
  end
  return number
end

local function by_start_time(a, b)
  return a.start_time < b.start_time
end

local function sorted_by_start(source)
  local ordered = {}
  for _, region in ipairs(source) do
    ordered[#ordered + 1] = region
  end
  table.sort(ordered, by_start_time)
  return ordered
end

--- Phase 1: decide where Tempo Anchors go.
-- An anchor makes a region carry its own bar grid, so it is unaffected by
-- whatever precedes it after a Repack (ADR-0004).
--
-- One is planned at *every* region start, with no skipping of regions that
-- already sit on a measure boundary -- ADR-0004 says every region start, and
-- docs/decisions.md lists that as a decision not to quietly soften. Idempotence comes
-- from the applier replacing a marker at a position rather than adding one, so
-- a repeated Repack rewrites the same values instead of stacking markers.
--
-- An anchor also carries `lineartempo`, taken from the last tempo marker at or
-- before the region start -- **not** hardcoded, and this is the tempo
-- counterpart of the shape question ADR-0006's amendment got wrong twice for
-- Automation Anchors. `SetTempoTimeSigMarker` demands the flag, and the two
-- possible defaults are both wrong somewhere:
--
--   * Always `false` (square) flattens any ramp the anchor lands inside. The
--     ramp's remainder disappears, so the bar grid downstream of the anchor
--     moves and, on a beat-based project, drags material with it -- issue #10's
--     hazard arriving through an insert instead of a delete.
--   * Always `true` invents a ramp in a project that had none, aiming at
--     whatever marker happens to come next.
--
-- Inheriting the flag in effect preserves the existing tempo curve in both
-- cases, which is the point of an anchor: it should change *what the region
-- depends on*, never how the region sounds. Note the ADR's argument against
-- inheritance for *envelope* shapes does not transfer -- there, the preceding
-- point is always strictly outside the region so its ramp always crosses the
-- bound; here the flag is a property of the tempo segment the anchor is being
-- inserted into, and the anchor's job is to subdivide that segment without
-- redrawing it.
--
-- This is unverifiable against the one real project available, whose 69 tempo
-- markers are all square (`spec/fixtures/repack_basic/before.rpp`), so no run
-- can currently tell the three options apart. It is reasoned, not observed.
-- @param snapshot table { regions, tempo_markers }
-- @param tempo table oracle with tempo_at(time) -> bpm, num, denom
-- @return table { anchors = { { time, region_name, bpm, timesig_num,
--   timesig_denom, lineartempo } }, is_empty }
function regions.plan_anchors(snapshot, tempo)
  -- The `lineartempo` in effect at `time`: the last marker at or before it.
  -- Read from the snapshot rather than the oracle because it is plain data --
  -- a stored flag, not something REAPER has to integrate.
  local function linear_at(time)
    local flag, latest = false, nil
    for _, marker in ipairs(snapshot.tempo_markers or {}) do
      if marker.position <= time + BOUNDARY_TOLERANCE
        and (latest == nil or marker.position >= latest) then
        latest, flag = marker.position, marker.lineartempo and true or false
      end
    end
    return flag
  end

  -- The tempo/time-signature marker sitting *on* `time`, or nil (issue #19).
  --
  -- **This is a narrowing of "read through the oracle", not a reversal of it.**
  -- The oracle exists because mid-ramp the tempo in effect is not any marker's
  -- bpm (ADR-0006), and that case is untouched. What this answers is the other
  -- one: a region start and a marker separated by microseconds are two
  -- independently authored numbers describing the same instant, and asking the
  -- oracle about the instant *fractionally before* the marker gets the tempo
  -- the previous region was running at.
  --
  -- Left unhandled that is not a rounding error, it is data loss. The applier's
  -- own marker lookup matches within `BOUNDARY_TOLERANCE`, so it *replaces* the
  -- coincident marker with the anchor rather than adding one beside it: the
  -- region then runs at its predecessor's tempo, and every beat-attached item
  -- inside it slides. Measured on the live project, where six of nineteen
  -- regions are affected and the largest error runs a 160 bpm region at 107 --
  -- 14.82s of musical slip across `Darkness of Blue` alone, and issue #16's
  -- long-unexplained `NES_15` residual. Phase 2 then re-reads the project by
  -- design, sees the drifted positions as the truth, and plans a
  -- self-consistent Repack against them, which is why nothing downstream ever
  -- noticed.
  --
  -- The tolerance is not a new judgement: this module's own `is_redundant` and
  -- the applier's marker lookup already call a marker this close coincident.
  -- Reading the tempo was the lone holdout, and that disagreement -- the
  -- planner deciding it was a different instant, the applier deciding it was
  -- the same one -- is the whole defect.
  --
  -- Nearest wins, ties to the earlier marker, matching how this module already
  -- collapses a cluster of boundaries to its earliest member.
  local function coincident_marker(time)
    local best, best_distance = nil, nil
    for _, marker in ipairs(snapshot.tempo_markers or {}) do
      local distance = math.abs(marker.position - time)
      if distance < BOUNDARY_TOLERANCE
        and (best == nil or distance < best_distance
          or (distance == best_distance and marker.position < best.position)) then
        best, best_distance = marker, distance
      end
    end
    return best
  end

  -- Would writing this anchor change the tempo map at all? True when a marker
  -- is already sitting at that position carrying exactly these values.
  --
  -- **This is not the "skipping" ADR-0004 forbids.** The anchor is still
  -- planned, still logged, and `apply.anchors` still writes every anchor handed
  -- to it -- nothing decides a region does not deserve one. What this answers is
  -- narrower: whether the write would be a no-op. That question has to be
  -- answerable for two reasons, and neither softens the ADR:
  --
  --   * ADR-0004 claims Padding is idempotent, and CLAUDE.md requires a run that
  --     changes nothing to create no undo point. A Repack of an already-packed
  --     project rewrites the same anchor values, so without this it would leave
  --     an undo point behind on every run, for no change.
  --   * A run is two phases *because* the oracle cannot see anchors that have
  --     not been written (ADR-0006). When every anchor is redundant the tempo map
  --     already reflects them, so the current grid *is* the post-anchor grid and
  --     phase 2 can be planned without writing anything first.
  local function is_redundant(anchor)
    for _, marker in ipairs(snapshot.tempo_markers or {}) do
      if math.abs(marker.position - anchor.time) < BOUNDARY_TOLERANCE
        and nearly_equal(marker.bpm or 0, anchor.bpm)
        and marker.timesig_num == anchor.timesig_num
        and marker.timesig_denom == anchor.timesig_denom
        and (marker.lineartempo and true or false) == anchor.lineartempo then
        return true
      end
    end
    return false
  end

  local anchors, changing = {}, 0
  for _, region in ipairs(sorted_by_start(snapshot.regions)) do
    -- Read through the oracle, not from the nearest tempo marker: mid-ramp the
    -- tempo in effect is not any marker's bpm.
    local bpm, timesig_num, timesig_denom = tempo.tempo_at(region.start_time)
    local lineartempo = linear_at(region.start_time)

    -- ...unless a marker is sitting *on* the region start, within the same
    -- tolerance everything else here treats as coincident (issue #19). Then
    -- the marker is the better answer, and the oracle is being asked about the
    -- instant fractionally before it -- see `coincident_marker`.
    local coincident = coincident_marker(region.start_time)
    if coincident then
      bpm = coincident.bpm or bpm
      lineartempo = coincident.lineartempo and true or false
      -- The signature only when the marker actually carries one. A tempo-only
      -- marker reports `-1/-1`, and `0/0` reaching `SetTempoTimeSigMarker`
      -- means "keep the previous signature" (research §4.4a) -- copying either
      -- onto an anchor writes a marker that does not start a measure, and
      -- starting one is the whole reason ADR-0004 puts an anchor at every
      -- region start. Measured: 16 of the live project's 19 region starts sit
      -- on a tempo-only marker, so this is the common case, not the edge.
      -- The oracle's reading is the signature *in effect* there, which is the
      -- right thing to make explicit.
      if has_timesig(coincident) then
        timesig_num = coincident.timesig_num
        timesig_denom = coincident.timesig_denom
      end
    end

    local anchor = {
      time = region.start_time,
      region_name = region.name,
      bpm = bpm,
      timesig_num = timesig_num,
      timesig_denom = timesig_denom,
      lineartempo = lineartempo,
    }
    anchor.redundant = is_redundant(anchor)
    if not anchor.redundant then
      changing = changing + 1
    end
    anchors[#anchors + 1] = anchor
  end

  return {
    anchors = anchors,
    is_empty = #anchors == 0,
    -- True when writing these anchors would leave the tempo map exactly as it
    -- is -- see `is_redundant`. Distinct from `is_empty`, which means there was
    -- nothing to anchor in the first place.
    is_noop = changing == 0,
    changing = changing,
  }
end

-- Mark each Automation Anchor with whether writing it would change the
-- envelope at all, and return how many would. (Issue #13.)
--
-- **This is not the "skipping" ADR-0004 forbids**, for the same reasons
-- `plan_anchors`' `is_redundant` is not: every bound still gets its anchor,
-- planned, logged and handed to the applier, which writes all of them. What
-- this answers is narrower -- whether the *run* has work to do -- and it has
-- to be answerable because `is_empty` used not to count anchors at all. That
-- kept a repeat Repack a clean no-op, at the cost of a plan whose only work
-- was anchors reporting "nothing to do" and writing nothing: an already-packed
-- project that gains automation inside a region got no anchors on it, and no
-- indication of the omission.
--
-- **Decided per time, not per anchor, because that is the unit the applier
-- works in.** `apply.envelope_anchors` clears a time and writes the whole
-- group, so the question is whether the group it would write equals the points
-- that will be sitting there -- ordered, since where two points share a time
-- the last one wins, and a shared bound's step pair is exactly that case.
--
-- Every disagreement resolves to "not redundant", which costs an undo point
-- for a write that changes nothing. The opposite error is silence, which is
-- what this issue was filed about.
--
-- **On ordering.** Existing points are paired with anchors in snapshot order,
-- which is REAPER's own -- the same assumption `value_at_bound`'s tie-break
-- rests on. For a point that *moves* to a bound that order is a guess, because
-- predicting where REAPER sorts a moved point among coincident ones would mean
-- modelling its sort. It cannot mislead: if any envelope point moves at all
-- then `envelope_moves` is non-empty, so the plan is not empty whatever this
-- decides. The only case where redundancy actually settles `is_empty` is the
-- one where nothing moves -- and there snapshot order *is* the final order.
-- @param anchors table plan.envelope_anchors, mutated to carry `redundant`
-- @param snapshot table the project snapshot
-- @param drops table the plan's final envelope_drops
-- @param region_holding function position -> arranged region name or nil
-- @param any_region_holding function position -> any region name or nil
-- @param moved_by table region name -> delta
-- @return number how many anchors would change something
local function mark_redundant_anchors(
  anchors, snapshot, drops, region_holding, any_region_holding, moved_by)
  local dropped = {}
  for _, drop in ipairs(drops) do
    dropped[("%d\0%s\0%.6f")
      :format(drop.track_index, drop.envelope_name, drop.position)] = true
  end

  -- Where a point ends up, or nil if it will not be anywhere an anchor can be.
  -- Parked points are `nil` rather than computed: parking moves material a
  -- whole `PARK_GAP` beyond the Packed Block, while every anchor sits on an
  -- arranged region's bound inside it, so the two cannot coincide.
  local function final_position(point)
    local holder = region_holding(point.position)
    if holder then
      return point.position + (moved_by[holder] or 0)
    end
    if any_region_holding(point.position) then
      return nil
    end
    if dropped[("%d\0%s\0%.6f")
      :format(point.track_index, point.envelope_name, point.position)] then
      return nil
    end
    -- Kept out of the drops by `plan_pack`'s `anchored_at`: an anchor claims
    -- this time, so the point is still there for that anchor to replace.
    return point.position
  end

  local groups, group_order = {}, {}
  for _, anchor in ipairs(anchors) do
    local key = regions.anchor_group_key(anchor.track_index, anchor.envelope_name, anchor.to)
    if not groups[key] then
      groups[key] = { anchors = {}, existing = {}, time = anchor.to,
        track_index = anchor.track_index, envelope_name = anchor.envelope_name }
      group_order[#group_order + 1] = key
    end
    local here = groups[key].anchors
    here[#here + 1] = anchor
  end

  for _, point in ipairs(snapshot.envelope_points or {}) do
    local lands_at = final_position(point)
    if lands_at then
      for _, key in ipairs(group_order) do
        local group = groups[key]
        if group.track_index == point.track_index
          and group.envelope_name == point.envelope_name
          and math.abs(group.time - lands_at) < BOUNDARY_TOLERANCE then
          group.existing[#group.existing + 1] = point
        end
      end
    end
  end

  local changing = 0
  for _, key in ipairs(group_order) do
    local group = groups[key]
    local redundant = #group.existing == #group.anchors
    for index = 1, #group.anchors do
      local anchor, point = group.anchors[index], group.existing[index]
      -- `selected` is deliberately not compared. The applier writes every
      -- anchor unselected, so a selected point at a bound does differ from
      -- what would be written -- but only in UI state, and counting it would
      -- make a second Repack stop being a no-op purely because the user had
      -- clicked a point. Tension *is* compared: it is curve, not chrome.
      -- Both are compared against what the applier actually writes (literal
      -- `0` tension, `SQUARE_SHAPE`), not against the anchor's own fields.
      if not (redundant
        and nearly_equal(point.value or 0, anchor.value or 0)
        and (point.shape or 0) == (anchor.shape or SQUARE_SHAPE)
        and nearly_equal(point.tension or 0, 0)) then
        redundant = false
      end
    end
    for _, anchor in ipairs(group.anchors) do
      anchor.redundant = redundant
      if not redundant then
        changing = changing + 1
      end
    end
  end

  return changing
end

-- Pad each region the Arrangement names out to the next bar line, and confirm
-- the result does not run into whatever follows it on the timeline.
--
-- "Already on a bar line" is decided at BOUNDARY_TOLERANCE, not EPSILON, and
-- that choice is load-bearing rather than cosmetic. The oracle's answer is a
-- bar line REAPER computed; a region end is a number a human dragged. Comparing
-- them is the same mixed-provenance comparison `contains` makes, so it needs the
-- same tolerance -- measured against the live project, region ends miss their
-- exact bar line by up to ~1e-5s, which is 10,000x EPSILON and musically zero.
--
-- At EPSILON those misses were not "already aligned", so the oracle returned the
-- *next* bar and Padding added a **whole bar** -- 1.4 to 2.4s at this project's
-- tempos. Measured on `spec/fixtures/live_session`: "Intro" is 69.60001s where
-- 29 bars at 100bpm is 69.60000s, a 1.04e-5s overhang, which produced a 2.0s pad
-- out of nothing. Four regions (Intro, Prophets, Low Fall, NES_19) padded
-- spuriously, 6.8s of silence in total, and "Intro"'s pad then ran into
-- "Sundown" -- which starts at exactly "Intro"'s end -- aborting the whole
-- Repack on the overlap check below. It also broke ADR-0004's idempotence claim:
-- a padded region is only "a whole number of bars" to within the same noise, so
-- at EPSILON every re-run pads it again.
--
-- Nothing real is missed by the looser test: a genuine partial bar is a musical
-- amount, four orders of magnitude above this tolerance. Measured by the real
-- oracle on that project, the eight genuine pads run from 0.211s to 1.836s.
-- (The pad sizes quoted above were estimated in this container and turned out
-- to be wrong (CLAUDE.md, "Traps": do not compute bar positions here). What the estimate did establish, and what the
-- real run confirmed, is the *class* of error this tolerance prevents: a
-- spurious whole-bar pad on a region that is already aligned.)
local function pad_regions(ordered, in_arrangement, tempo)
  local pads, bounds = {}, {}

  for _, region in ipairs(ordered) do
    local end_time = region.end_time
    if in_arrangement[region.name] then
      local padded = tempo.next_bar_at_or_after(region.end_time)
      if padded - region.end_time > BOUNDARY_TOLERANCE then
        pads[#pads + 1] = {
          name = region.name,
          number = region.number,
          from_end = region.end_time,
          to_end = padded,
          added = padded - region.end_time,
        }
        end_time = padded
      end
      -- Within tolerance the region is treated as already bar-aligned and its
      -- end is left exactly where it was, rather than nudged onto the computed
      -- bar line. Nudging would rewrite every region bound in the project by a
      -- few microseconds on every run -- invisible, unrequested, and enough to
      -- move a bound across an item edge that `contains` had just decided about.
    end
    bounds[region.name] = { start_time = region.start_time, end_time = end_time }
  end

  -- ADR-0004: region audio is never overlapped. Padding into a neighbour would
  -- capture material belonging to that neighbour.
  --
  -- Tolerance here matches the pad decision above, and for the same reason: this
  -- compares a computed bar line against an authored region start. Seven of the
  -- live project's region pairs are back-to-back (gaps of 0 to 8e-6s), so at
  -- EPSILON a noise-level overhang would abort a Repack that pads nothing.
  for index = 1, #ordered - 1 do
    local this, next_region = ordered[index], ordered[index + 1]
    if bounds[this.name].end_time - next_region.start_time > BOUNDARY_TOLERANCE then
      return nil, nil, ("Region %q ends at %.3f, past the start of region %q at %.3f. "):format(
        this.name, bounds[this.name].end_time, next_region.name, next_region.start_time)
        .. "Repack cannot overlap regions -- separate them and run again."
    end
  end

  return pads, bounds
end

-- The boundaries a Repack has to cut at: the start and end of every region
-- this run actually moves.
--
-- ADR-0002 as originally written cut at *every* region boundary, on every
-- track, guarded by nothing. That was amended (see the ADR): a region staying
-- put carries its contents by not moving them, so cutting its straddlers
-- edits audio for no benefit this run can point at. Cutting only at moving
-- regions' bounds keeps every split traceable to a move in the same plan.
--
-- A straddler of a *moving* region is still cut unconditionally -- every
-- track, no exemption for an item covering a whole region. That half of
-- ADR-0002 is intact.
--
-- **Boundaries closer together than BOUNDARY_TOLERANCE are one boundary.** Two
-- regions can meet at times that differ by microseconds rather than exactly --
-- in the live project, "What I Deserve" ends at 2759.357260960 and "I'm gonna
-- tell God everything" starts at 2759.357269029, 8.07e-06s later, and
-- "Sundown"/"What I Deserve" meet 1.95e-06s apart. Emitting both as cuts asks
-- REAPER to carve a piece 8 microseconds long: **0.39 samples at 48kHz**, which
-- it cannot represent. A real run on the live project did exactly that and
-- aborted -- "the cut on track 3 at 2759.357s did not take" -- with the first
-- cut applied and the second impossible, leaving the project one item further
-- along than it started.
--
-- Collapsing them is the same judgement BOUNDARY_TOLERANCE encodes everywhere
-- else: at this distance two independently authored numbers are the same
-- instant, and no item can straddle the gap between them in any meaningful way.
-- The earliest of a cluster wins, which keeps the cut inside the earlier region
-- and lets `contains` place the piece after it in the later one -- the later
-- region's start is within tolerance, so it claims the piece, and the earlier
-- region's end is not, so it does not.
local function moving_boundaries(ordered, bounds, moved_by)
  local times = {}
  for _, region in ipairs(ordered) do
    if (moved_by[region.name] or 0) ~= 0 then
      local bound = bounds[region.name]
      times[#times + 1] = bound.start_time
      times[#times + 1] = bound.end_time
    end
  end
  table.sort(times)

  local distinct = {}
  for _, time in ipairs(times) do
    if #distinct == 0 or time - distinct[#distinct] > BOUNDARY_TOLERANCE then
      distinct[#distinct + 1] = time
    end
  end
  return distinct
end

-- Where this item has to be cut, ascending and deduplicated. Adjacent regions
-- share a boundary time, so the same cut can arrive twice.
local function cuts_in(item, boundaries)
  local item_end = item.position + item.length
  local cuts = {}
  for _, boundary in ipairs(boundaries) do
    -- Strictly inside: an item merely touching a boundary is not straddling,
    -- and cutting there would make a zero-length piece.
    -- The last test is a tolerance, not equality, for the reason
    -- `moving_boundaries` explains: two boundaries a few microseconds apart are
    -- one boundary, and cutting at both asks for a sub-sample fragment. It is
    -- belt-and-braces now that the boundary list arrives deduplicated, and it
    -- stays because this is the last gate before a cut is emitted.
    if boundary - item.position > BOUNDARY_TOLERANCE
      and item_end - boundary > BOUNDARY_TOLERANCE
      and (#cuts == 0 or boundary - cuts[#cuts] > BOUNDARY_TOLERANCE) then
      cuts[#cuts + 1] = boundary
    end
  end
  return cuts
end

-- The pieces those cuts leave, left to right. With no cuts this is the item
-- itself, so callers can treat every item uniformly.
local function pieces_of(item, cuts)
  local pieces, from = {}, item.position
  for _, cut in ipairs(cuts) do
    pieces[#pieces + 1] = { position = from, length = cut - from }
    from = cut
  end
  pieces[#pieces + 1] = { position = from, length = (item.position + item.length) - from }
  return pieces
end

-- Half-open [start, end): back-to-back regions never both claim a position,
-- which region_holding relies on to assign it to exactly one of them.
local function contains(bound, position)
  return position - bound.start_time > -BOUNDARY_TOLERANCE
    and bound.end_time - position > BOUNDARY_TOLERANCE
end

-- Does this span touch any region at all -- including regions the Arrangement
-- omits, which `contains`/`region_holding` deliberately ignore?
--
-- This is the test that decides whether material is Dropped or Parked
-- (CONTEXT.md), so it is deliberately the widest possible reading of "inside
-- a region": anything overlapping any region, by more than float noise,
-- survives. Only material touching no region whatsoever is discarded.
local function overlaps_any_region(ordered, bounds, position, length)
  local span_end = position + length
  for _, region in ipairs(ordered) do
    local bound = bounds[region.name]
    if span_end - bound.start_time > BOUNDARY_TOLERANCE
      and bound.end_time - position > BOUNDARY_TOLERANCE then
      return true
    end
  end
  return false
end

-- A Headroom this many bars from where the region already ends is treated as a
-- typo rather than an instruction. The number itself is arbitrary and generous
-- -- 4096 bars is over two hours at any usable tempo -- but the guard is not:
-- `bars_moved` walks the grid one bar at a time, so a Headroom of 1e9 seconds
-- would sit in that loop for as long as REAPER let it, inside an undo block,
-- with no message.
local MAX_HEADROOM_BARS = 4096

-- How many bars separate two bar lines, signed, counting forward from the
-- earlier one. Reported alongside the seconds because seconds are what the user
-- typed and bars are what they hear.
--
-- Deliberately only ever steps *forward*: `bar_after` is the one directional
-- primitive the oracle offers, and asking for a "previous bar" would mean
-- either a third oracle call or bar arithmetic here, which ADR-0006 forbids.
local function bars_moved(tempo, from, to)
  local step = to > from and 1 or -1
  local at = step > 0 and from or to
  local target = step > 0 and to or from
  local bars = 0
  while target - at > BOUNDARY_TOLERANCE do
    at = tempo.bar_after(at)
    bars = bars + 1
    if bars > MAX_HEADROOM_BARS then
      return nil
    end
  end
  return bars * step
end

-- The bar line nearest `target`, ties resolved away from `from`.
--
-- The tie is a real decision even though it is measure-zero in practice: at
-- exactly half a bar, `round()` goes away from zero, so a request to grow gets
-- the later line and a request to shrink the earlier one. Resolving toward
-- `from` instead would silently turn "half a bar longer" into no change.
local function nearest_bar(tempo, target, from)
  local before = tempo.bar_at_or_before(target)
  local after = tempo.next_bar_at_or_after(target)
  local back, forward = target - before, after - target
  if math.abs(back - forward) < EPSILON then
    return target >= from and after or before
  end
  return back < forward and before or after
end

-- How far back a region's end may legally come.
--
-- **A shrink may only remove silence**, so this covers the last of *anything*
-- inside the region, not just the last item -- a plain marker, an envelope
-- point and a tempo marker all travel with the region under the frozen
-- membership `plan_pack` decides against original bounds, and any one of them
-- left past a shrunk end would land inside whatever the Repack puts next.
-- Rounded up to a bar line, because the new end has to be one.
--
-- The floor is never below one bar after the region start. A region with no
-- content at all would otherwise be shrinkable to nothing, which is not a way
-- to remove a region -- dropping it from the Arrangement parks it, and that is
-- the existing answer.
local function shrink_floor(snapshot, bound, tempo)
  local floor = tempo.bar_after(bound.start_time)

  local function raise_to(time)
    local bar = tempo.next_bar_at_or_after(time)
    if bar > floor then
      floor = bar
    end
  end

  -- Items are taken by overlap rather than by `contains`, and clamped to the
  -- region's end. An item straddling either bound is cut there, so the piece
  -- that belongs to this region runs to whichever comes first -- its own end or
  -- the region's. Clamping is what makes a region whose audio runs right to its
  -- end unshrinkable, which is correct.
  for _, item in ipairs(snapshot.items or {}) do
    local item_end = item.position + item.length
    if item_end - bound.start_time > BOUNDARY_TOLERANCE
      and bound.end_time - item.position > BOUNDARY_TOLERANCE then
      raise_to(math.min(item_end, bound.end_time))
    end
  end

  for _, marker in ipairs(snapshot.markers or {}) do
    if contains(bound, marker.position) then
      raise_to(marker.position)
    end
  end
  for _, point in ipairs(snapshot.envelope_points or {}) do
    if contains(bound, point.position) then
      raise_to(point.position)
    end
  end
  for _, marker in ipairs(snapshot.tempo_markers or {}) do
    if contains(bound, marker.position) then
      raise_to(marker.position)
    end
  end

  return floor
end

-- Resolve each region's requested Headroom into an adjustment to the length it
-- is laid down with (CONTEXT.md, Headroom).
--
-- **Measured from the *padded* end, not the raw one**, and that is forced
-- rather than chosen: a Headroom of `0` has to change nothing, and from a raw
-- end a nearest-bar rule would round *down* and trim audio off a region nobody
-- asked to shorten. Padding first and adjusting from there makes `0` exactly
-- today's behaviour, which is what lets the feature be adopted one region at a
-- time.
--
-- **The result is a change to the length, never to `bounds`.** Membership,
-- Straddling Item cuts and Dropped Material are all still decided against the
-- region's original bounds, so a grown region cannot capture the following
-- region's material, and the overlap refusal in `pad_regions` -- which would
-- otherwise abort on any project whose regions sit back to back -- never fires
-- on a Headroom.
--
-- @return table extra -- region name -> seconds added to its packed length
-- @return table entries -- one per region asked for a non-zero Headroom, in
--   Arrangement order, carrying what was asked and what it resolved to
local function resolve_headroom(snapshot, arrangement, bounds, by_name, tempo)
  local requested = arrangement.headroom or {}
  local extra, entries, refusals = {}, {}, {}

  for _, name in ipairs(arrangement) do
    local wanted = requested[name] or 0
    if wanted ~= 0 then
      local bound = bounds[name]
      -- Clamped at the region's start before the oracle is asked anything. A
      -- shrink larger than the region is a typo, and it refuses on the floor
      -- below either way -- but unclamped it would first ask REAPER where the
      -- bar lines are at a negative time, which is not a question the tempo map
      -- is defined for and not one worth discovering inside an undo block.
      local target = math.max(bound.start_time, bound.end_time + wanted)
      local new_end = nearest_bar(tempo, target, bound.end_time)

      if new_end < bound.end_time - BOUNDARY_TOLERANCE then
        local floor = shrink_floor(snapshot, bound, tempo)
        if new_end < floor - BOUNDARY_TOLERANCE then
          refusals[#refusals + 1] = ("  %q: asked for %+.3fs, but its end cannot come back past "
            .. "%.3f -- the largest shrink it can take is %.3fs")
            :format(name, wanted, floor, bound.end_time - floor)
        end
      end

      local moved = new_end - bound.end_time
      if math.abs(moved) <= BOUNDARY_TOLERANCE then
        moved = 0
      end

      local bars = bars_moved(tempo, bound.end_time, bound.end_time + moved)
      if not bars then
        refusals[#refusals + 1] = ("  %q: a Headroom of %+.3fs is more than %d bars from where "
          .. "the region ends, which is almost certainly a typo")
          :format(name, wanted, MAX_HEADROOM_BARS)
        bars = 0
      end

      extra[name] = moved
      entries[#entries + 1] = {
        name = name,
        number = by_name[name].number,
        requested = wanted,
        -- Reported even when it is zero, rather than the region being omitted.
        -- A request under half a bar resolves to no change at all, and that is
        -- the likeliest "nothing happened" a user will meet.
        resolved = moved,
        bars = bars,
        from_end = bound.end_time,
        to_end = bound.end_time + moved,
      }
    end
  end

  if #refusals > 0 then
    return nil, nil, table.concat({
      "Repack cannot apply the Headroom this Arrangement asks for:",
      table.concat(refusals, "\n"),
      "A shrink may only ever remove silence -- it never cuts into a region's contents, and "
        .. "never leaves a region shorter than one bar.",
    }, "\n")
  end

  return extra, entries
end

--- Phase 2: plan Padding, placement and parking.
-- The snapshot must be re-read *after* phase 1's anchors are applied, so that
-- the tempo oracle and `snapshot.tempo_markers` both reflect them.
-- @param snapshot table { regions, markers, items, tempo_markers, envelope_points }
-- @param arrangement table ordered list of Region Names
-- @param tempo table oracle with next_bar_at_or_after(time) -> time
-- @return table|nil plan, string|nil error
function regions.plan_pack(snapshot, arrangement, tempo, automation)
  local by_name = {}
  for _, region in ipairs(snapshot.regions) do
    by_name[region.name] = region
  end

  local in_arrangement = {}
  for _, name in ipairs(arrangement) do
    if not by_name[name] then
      return nil, ("Arrangement names region %q, which this project does not have."):format(name)
    end
    in_arrangement[name] = true
  end

  local ordered = sorted_by_start(snapshot.regions)

  local pads, bounds, err = pad_regions(ordered, in_arrangement, tempo)
  if not pads then
    return nil, err
  end

  -- Headroom rides on top of Padding and changes only the length each region is
  -- laid down with -- `bounds` stays the original, padded geometry that every
  -- membership question below is answered against. See `resolve_headroom`.
  local extra, headroom, headroom_err = resolve_headroom(snapshot, arrangement, bounds, by_name, tempo)
  if not extra then
    return nil, headroom_err
  end

  -- Sequential placement, left to right, from the start of the timeline.
  --
  -- A region is placed when either bound changes, not only when it moves. The
  -- second case is Padding on a region that is already where it belongs: its
  -- start is already at the cursor but its end has been extended, and
  -- `apply.places` is what writes a region's bounds (one `SetProjectMarker4`
  -- carrying both), so without a place entry the pad would be planned, logged,
  -- reported to the user -- and never written. `plan.pads` stays the record of
  -- *why* an end changed; `plan.places` is the instruction that changes it.
  --
  -- Such an entry has `delta == 0`, which every consumer already treats as "did
  -- not move": no cuts at its bounds (`moving_boundaries`), no marker or item
  -- moves, nothing carried. That is right -- a region that stays put carries its
  -- contents by leaving them alone, and extending an end only ever takes in more
  -- of the gap after it.
  --
  -- A Headroom arrives here and nowhere else: it is added to the length the
  -- region is laid down with, so its end moves in the Packed Block only. The
  -- comparison below is therefore against the end the region will *have* rather
  -- than its padded end in source coordinates -- which is the same test as
  -- before wherever no Headroom was asked for.
  local places, cursor = {}, 0
  for _, name in ipairs(arrangement) do
    local bound = bounds[name]
    local length = bound.end_time - bound.start_time + (extra[name] or 0)
    local original = by_name[name]
    if not nearly_equal(bound.start_time, cursor)
      or not nearly_equal(cursor + length, original.end_time) then
      places[#places + 1] = {
        name = name,
        number = by_name[name].number,
        from_start = bound.start_time,
        from_end = bound.end_time,
        to_start = cursor,
        delta = cursor - bound.start_time,
        length = length,
      }
    end
    cursor = cursor + length
  end
  local packed_end = cursor

  local moved_by = {}
  for _, place in ipairs(places) do
    moved_by[place.name] = place.delta
  end

  -- Parked Material: everything the Repack did not place, gathered up and
  -- shifted by one shared offset so its internal timing survives (CONTEXT.md).
  local parked, earliest = {}, nil
  local function park(entry)
    parked[#parked + 1] = entry
    if not earliest or entry.from < earliest then
      earliest = entry.from
    end
  end

  for _, region in ipairs(ordered) do
    if not in_arrangement[region.name] then
      park({
        kind = "region",
        name = region.name,
        number = region.number,
        from = region.start_time,
        -- Carried so the applier can rewrite both bounds: SetProjectMarker4
        -- takes a start and an end, and a region translated rigidly keeps its
        -- length. Derived from the region rather than `bounds`, which holds
        -- Padded ends for placed regions only -- a parked region is never
        -- Padded, because Padding exists to keep the Packed Block bar-aligned
        -- and parked material is not in it.
        length = region.end_time - region.start_time,
      })
    end
  end

  local function region_holding(position)
    for _, region in ipairs(ordered) do
      if in_arrangement[region.name] and contains(bounds[region.name], position) then
        return region.name
      end
    end
    return nil
  end

  -- Same question as region_holding, but over every region regardless of
  -- Arrangement membership -- the "does this still belong to a region at
  -- all" test overlaps_any_region already asks for a span, asked here for a
  -- single point instead. Used only to classify an envelope point
  -- region_holding could not place: one still inside a region (an omitted
  -- one) parks with it; one inside none is genuinely homeless.
  local function any_region_holding(position)
    for _, region in ipairs(ordered) do
      if contains(bounds[region.name], position) then
        return region.name
      end
    end
    return nil
  end

  -- Transplant each placed region's tempo slice along with it. This is what
  -- makes the cumulative-seconds placement above legitimate: a region only
  -- keeps its duration, and only stays bar-aligned, if the tempo points inside
  -- it move by the same delta (ADR-0004, ADR-0006). A Tempo Anchor sits exactly
  -- on a region start, so `region_holding` picks it up as part of that region.
  --
  -- A marker `region_holding` cannot place belongs to no region -- a gap the
  -- Repack is about to close, or a region the Arrangement omits. Left alone it
  -- would end up inside whatever region lands on top of its old position,
  -- silently changing that region's tempo, so it parks instead: translated by
  -- the same shared offset as the rest of Parked Material (CONTEXT.md), never
  -- deleted. Deleting it was considered and rejected -- issue #10 shows a
  -- deleted tempo marker can slide any beat-based material downstream of it,
  -- which on this project (28/32 tracks beat-based) is not a theoretical risk.
  -- This is why tempo markers, unlike plain markers, are pushed into
  -- `tempo_moves` (which this run's applier writes) rather than left to sit in
  -- `parked` (`plan.parks`, still #7's unapplied territory) -- "park" cannot
  -- mean "planned but not written" for the one category whose write is not
  -- optional. The concrete `to` position for these is filled in once
  -- `park_delta` is known, below.
  local tempo_moves = {}
  for _, marker in ipairs(snapshot.tempo_markers or {}) do
    local holder = region_holding(marker.position)
    if holder then
      local delta = moved_by[holder] or 0
      if delta ~= 0 then
        tempo_moves[#tempo_moves + 1] = {
          kind = "region",
          region_name = holder,
          from = marker.position,
          to = marker.position + delta,
          delta = delta,
          bpm = marker.bpm,
          timesig_num = marker.timesig_num,
          timesig_denom = marker.timesig_denom,
          lineartempo = marker.lineartempo,
        }
      end
    else
      park({
        kind = "tempo",
        from = marker.position,
        bpm = marker.bpm,
        timesig_num = marker.timesig_num,
        timesig_denom = marker.timesig_denom,
        lineartempo = marker.lineartempo,
      })
    end
  end

  -- Transplant each placed region's envelope points along with it -- issue
  -- #8, the same half-open region_holding rule tempo markers and plain
  -- markers already use, so the boundary convention cannot drift between
  -- categories.
  --
  -- Unlike a tempo marker, an envelope point carries none of issue #10's
  -- hazard: nothing else's position is derived from an automation value, so
  -- there is no reason to give a homeless point tempo's "always applied,
  -- even when parked" exception. A point region_holding cannot place is
  -- classified the same way an item is: still inside some region (an
  -- omitted one) it belongs to that region and parks with it, unapplied
  -- like the rest of that region's contents (#7); inside none at all it is
  -- genuinely spent, like a Loose Item, and is dropped outright
  -- (`envelope_drops`, `apply.envelope_drops` -- the user's explicit call,
  -- over parking it like a tempo marker, precisely because no hazard argues
  -- for the exception here).
  local envelope_moves, envelope_drops = {}, {}
  for _, point in ipairs(snapshot.envelope_points or {}) do
    local holder = region_holding(point.position)
    if holder then
      local delta = moved_by[holder] or 0
      if delta ~= 0 then
        envelope_moves[#envelope_moves + 1] = {
          track_index = point.track_index,
          track_name = point.track_name,
          envelope_name = point.envelope_name,
          region_name = holder,
          from = point.position,
          to = point.position + delta,
          delta = delta,
          value = point.value,
          shape = point.shape,
          tension = point.tension,
          selected = point.selected,
        }
      end
    else
      local any_holder = any_region_holding(point.position)
      if any_holder then
        park({
          kind = "envelope",
          track_index = point.track_index,
          track_name = point.track_name,
          envelope_name = point.envelope_name,
          region_name = any_holder,
          from = point.position,
          value = point.value,
          shape = point.shape,
          tension = point.tension,
          selected = point.selected,
        })
      else
        envelope_drops[#envelope_drops + 1] = {
          track_index = point.track_index,
          track_name = point.track_name,
          envelope_name = point.envelope_name,
          position = point.position,
        }
      end
    end
  end

  -- Automation Anchors: a point written at both bounds of every placed
  -- region, carrying the value that envelope *already* holds there.
  --
  -- The problem they solve is the automation equivalent of the one ADR-0004's
  -- Tempo Anchors solve for tempo. Real automation is sparse: a value set at
  -- one song's start persists through the next song, which carries no point of
  -- its own. That is correct only while the two stay adjacent. A Repack
  -- reorders them, so the second song inherits whatever now precedes it --
  -- silently, with no plan entry naming it -- and a ramp can form straight
  -- across a song boundary. Anchoring both bounds makes each region's
  -- automation self-contained, so its values stop depending on what happens to
  -- sit in front of it.
  --
  -- This also stops `envelope_drops` being lossy. A point outside every region
  -- is deleted as Dropped Material, but it may have been the thing
  -- *establishing* a value some later region relied on. Evaluating before
  -- anything moves captures that value at the bounds first, so what the drop
  -- removes is genuinely spent.
  --
  -- The value comes from an injected oracle, not from interpolating
  -- `snapshot.envelope_points` here: REAPER's shapes include bezier and
  -- slow start/end, and reimplementing that in Lua is the same mistake
  -- ADR-0006 rejected for bar math. Absent the oracle no anchors are planned,
  -- which is what keeps this optional for callers that do not want them.
  --
  -- Anchors are expressed at their *final* positions, and applied after every
  -- envelope point has moved, so they are immune to the move ordering
  -- entirely. Adjacent placed regions share a bound, so the end anchor of one
  -- and the start anchor of the next land on the same time -- which is exactly
  -- how REAPER expresses a step, and exactly what a song change wants.
  local envelope_anchors = {}
  local changing_envelope_anchors = 0
  if automation then
    local envelopes, seen = {}, {}
    for _, point in ipairs(snapshot.envelope_points or {}) do
      local key = point.track_index .. "\0" .. point.envelope_name
      if not seen[key] then
        seen[key] = true
        envelopes[#envelopes + 1] = point
      end
    end

    -- **Only a region *start* can already be covered by a point of its own,
    -- and this asymmetry is the whole reason it has to be spelt out.** Region
    -- membership is half-open, `[start, end)` -- the same rule every other
    -- category here uses. So a point exactly on a region's start is inside it
    -- and travels with it, and anchoring there would duplicate a deliberate
    -- value. A point exactly on a region's *end* is **not** inside it: it
    -- belongs to the next region, parks, or is dropped. It is never still
    -- there afterwards, so an end bound always needs its own anchor.
    --
    -- Treating both bounds alike was a real failure. Track 14's Transpose is
    -- authored as step pairs -- two points at one time, 0.495 then 0.72 --
    -- and region "The pain you leave behind" ended exactly on such a pair at
    -- 5619.164. Both points were dropped as Material touching no region, and
    -- the suppressed end anchor left the region's last value ramping 265s into
    -- the next song's 0.696.
    local function start_is_already_pointed(envelope, time)
      for _, point in ipairs(snapshot.envelope_points or {}) do
        if point.track_index == envelope.track_index
          and point.envelope_name == envelope.envelope_name
          and math.abs(point.position - time) < BOUNDARY_TOLERANCE then
          return true
        end
      end
      return false
    end

    -- **Both anchors are square, and both take the last authored value rather
    -- than an interpolated one.** Both halves of that were got wrong once
    -- each, against real data, so both are stated with their counter-example.
    --
    -- *Square*, because a point's shape governs the segment after it and a
    -- ramp can never legitimately start at a region bound. Writing anchors
    -- linear made a run ramp an end anchor's 1 down to the 0 the following
    -- region set 115s later. Inheriting "the shape already in effect" at a
    -- region *start* looks more careful and is not: the last point at or
    -- before a start is either exactly on it (where no anchor is planned at
    -- all) or strictly before the region -- so it is always outside, and its
    -- ramp always crosses the bound. There is no intra-region ramp to
    -- preserve here.
    --
    -- *Last authored value*, because a ramp crossing a region bound is
    -- meaningless once the Repack separates its endpoints: it interpolated
    -- between two songs that are no longer adjacent. Sampling it yields a
    -- number nobody wrote. Real data: track 14's Transpose points are 0.5,
    -- 0.689 and 0.72 with linear shapes and multi-song gaps, and evaluating
    -- at each region bound produced 0.49848908, 0.49833384, 0.49787437 ... --
    -- a staircase of near-0.5 values, none of them authored, each region
    -- ramping from one to the next. Taking the originating point's value
    -- instead cancels the cross-region ramp and gives back the 0.5 that was
    -- actually written.
    --
    -- The oracle is still what answers when *no* point precedes the bound,
    -- since the value there is the envelope's own default, which is not
    -- derivable from the points at all.
    -- `>=` rather than `>` on the tie-break, deliberately: real automation is
    -- authored as step pairs, two points at one time (track 14's Transpose has
    -- 0.495 immediately followed by 0.72). The *last* of them is the value
    -- actually in effect going forward, so later entries at the same position
    -- must win. Points arrive in REAPER's own sorted order, so "later in the
    -- snapshot" is "later in the envelope".
    --
    -- An end bound is exclusive for the same half-open reason above: a point
    -- sitting exactly on a region's end belongs to the next region, so the
    -- value this region ends on is the last one strictly inside it.
    local function value_at_bound(envelope, time, inclusive)
      local limit = inclusive and (time + BOUNDARY_TOLERANCE) or (time - BOUNDARY_TOLERANCE)
      local value, latest = nil, nil
      for _, point in ipairs(snapshot.envelope_points or {}) do
        if point.track_index == envelope.track_index
          and point.envelope_name == envelope.envelope_name
          and point.position <= limit
          and (latest == nil or point.position >= latest) then
          latest, value = point.position, point.value
        end
      end
      if latest == nil then
        return automation.value_at(envelope.track_index, envelope.envelope_name, time)
      end
      return value
    end

    -- Candidates first, suppression second. The two cannot be decided in one
    -- pass, because whether a start anchor may be suppressed depends on whether
    -- some *other* anchor lands on the same final time.
    local candidates = {}
    for _, name in ipairs(arrangement) do
      local bound, delta = bounds[name], moved_by[name] or 0
      -- An end anchor sits on the bound the region will actually have, so a
      -- Headroom moves it along with the end. A start anchor does not: the
      -- adjustment is at the end only. The *value* still comes from the
      -- original bound either way -- it is what the envelope held there before
      -- anything moved.
      local tail = extra[name] or 0
      for _, envelope in ipairs(envelopes) do
        for _, edge in ipairs({ { bound.start_time, "start" }, { bound.end_time, "end" } }) do
          local time, which = edge[1], edge[2]
          candidates[#candidates + 1] = {
            track_index = envelope.track_index,
            track_name = envelope.track_name,
            envelope_name = envelope.envelope_name,
            region_name = name,
            edge = which,
            from = time,
            to = time + delta + (which == "end" and tail or 0),
            value = value_at_bound(envelope, time, which == "start"),
            shape = SQUARE_SHAPE,
            envelope = envelope,
          }
        end
      end
    end

    -- Which final times an *end* anchor claims. `apply.envelope_anchors` clears
    -- a time before writing the anchors planned for it, so a start anchor
    -- suppressed at a time an end anchor also claims would not leave the existing
    -- point alone -- the end anchor would delete it and stand alone, collapsing
    -- the two-point step into one.
    --
    -- That is not hypothetical: packing makes consecutive placed regions share a
    -- bound, so on a *second* Repack of an already-packed project every interior
    -- bound holds the previous run's anchors. `start_is_already_pointed` would
    -- see them, suppress every start anchor, and each shared bound would keep
    -- only the earlier region's end value -- silently replacing the value in
    -- effect from that bound with the one from the region before it.
    local end_claimed = {}
    for _, candidate in ipairs(candidates) do
      if candidate.edge == "end" then
        end_claimed[("%d\0%s\0%.6f"):format(
          candidate.track_index, candidate.envelope_name, candidate.to)] = true
      end
    end

    for _, candidate in ipairs(candidates) do
      -- ADR-0006: only a region *start* can already be covered by a point of its
      -- own, and where it is, the authored value must not be overwritten by a
      -- derived one -- unless this plan is going to clear that time anyway.
      local suppressed = candidate.edge == "start"
        and start_is_already_pointed(candidate.envelope, candidate.from)
        and not end_claimed[("%d\0%s\0%.6f"):format(
          candidate.track_index, candidate.envelope_name, candidate.to)]
      if not suppressed then
        candidate.envelope = nil
        envelope_anchors[#envelope_anchors + 1] = candidate
      end
    end

    -- A point an anchor is about to occupy is not Dropped Material, even though
    -- the half-open membership rule says it belongs to no region.
    --
    -- The case is narrow and entirely self-inflicted: the **last** placed
    -- region's end bound. Membership is `[start, end)`, so a point exactly on it
    -- is inside no region, and with no region following there is nothing to carry
    -- it -- so it was classified as touching no region and dropped. But that
    -- point is usually an anchor a *previous* Repack wrote, and this run plans an
    -- anchor at the very same time. Real REAPER, running the same Arrangement
    -- twice: `DROPPED envelope point (track 1 Gtr, "Mute"): 32.000`, immediately
    -- followed by an anchor written back at 32.000.
    --
    -- That was net-neutral only because `apply.plan` happens to run drops before
    -- anchors. Resting a "delete" and a "write" at the same instant on the
    -- applier's ordering is exactly the kind of coupling that turns into data
    -- loss when someone reorders it for an unrelated reason -- and it made every
    -- re-run's plan claim a destructive drop it did not mean, in the one category
    -- whose log line is the only record of what was destroyed (CONTEXT.md).
    local function anchored_at(drop)
      for _, anchor in ipairs(envelope_anchors) do
        if anchor.track_index == drop.track_index
          and anchor.envelope_name == drop.envelope_name
          -- A dropped point does not move, so its final position is where it
          -- already is; an anchor's `to` is final too.
          and math.abs(anchor.to - drop.position) < BOUNDARY_TOLERANCE then
          return true
        end
      end
      return false
    end

    local kept = {}
    for _, drop in ipairs(envelope_drops) do
      if not anchored_at(drop) then
        kept[#kept + 1] = drop
      end
    end
    envelope_drops = kept

    -- Runs last, because it is asked of the plan's *outcome*: the moves and
    -- drops above decide what will be sitting at each bound by the time the
    -- anchors are written.
    changing_envelope_anchors = mark_redundant_anchors(
      envelope_anchors, snapshot, envelope_drops, region_holding, any_region_holding, moved_by)
  end

  local marker_moves = {}
  for _, marker in ipairs(snapshot.markers or {}) do
    local holder = region_holding(marker.position)
    if holder then
      local delta = moved_by[holder] or 0
      if delta ~= 0 then
        marker_moves[#marker_moves + 1] = {
          name = marker.name,
          number = marker.number,
          from = marker.position,
          to = marker.position + delta,
          delta = delta,
        }
      end
    else
      park({ kind = "marker", name = marker.name, number = marker.number, from = marker.position })
    end
  end

  -- Every item is cut at the bounds of the regions this run moves, and each
  -- resulting piece is then classified on its own. That ordering is what
  -- makes the rest of this simple: after cutting, a piece is either wholly
  -- inside one moving region or wholly outside every one of them, so it
  -- either travels by that region's delta or it is a Loose Item.
  --
  -- Material touching no region at all is **dropped**, not parked
  -- (CONTEXT.md, Dropped Material): the tail a cut leaves beyond a region's
  -- end, and any item that was already lying outside every region. A Repack
  -- is run on a project that has been cleaned up, so material outside every
  -- region is spent, and carrying it forward only clutters the result.
  --
  -- Anything that *does* touch a region survives. An item inside a region the
  -- Arrangement omits still parks alongside that region, exactly like a
  -- marker -- `region_holding` recognises only in_arrangement regions, so
  -- such an item lands here with no holder, and `overlaps_any_region` is what
  -- tells it apart from genuinely orphaned material.
  --
  -- Pieces are identified by track and position, never by index into the
  -- snapshot: splitting reindexes a track's items, so an index captured here
  -- would be stale by the time the applier moves anything. This is also why
  -- the applier re-locates by position rather than trusting what
  -- SplitMediaItem hands back (research/reaper-scripting.md §4.3a).
  --
  -- A piece on a timebase this suite cannot confirm safe to reposition
  -- (project.lua's `timebase_safe`, §4.1c) still refuses, rather than
  -- risking a silent stretch. Splitting does not make that safe.
  local item_moves, loose_items, splits, drops = {}, {}, {}, {}
  local straddling, unsafe = {}, {}
  local boundaries = moving_boundaries(ordered, bounds, moved_by)
  local split_seen = {}

  for _, item in ipairs(snapshot.items or {}) do
    local cuts = cuts_in(item, boundaries)

    for _, cut in ipairs(cuts) do
      -- Two items overlapping on one track can need the same cut; the
      -- applier cuts every item on the track that spans the position, so
      -- one entry per track and position describes it exactly once.
      local key = ("%d@%.17g"):format(item.track_index, cut)
      if not split_seen[key] then
        split_seen[key] = true
        splits[#splits + 1] = {
          track_index = item.track_index,
          track_name = item.track_name,
          position = cut,
        }
      end
    end

    for _, piece in ipairs(pieces_of(item, cuts)) do
      local holder = region_holding(piece.position)

      if not holder then
        local entry = { track_index = item.track_index, track_name = item.track_name,
          position = piece.position, length = piece.length }
        if overlaps_any_region(ordered, bounds, piece.position, piece.length) then
          loose_items[#loose_items + 1] = entry
        else
          drops[#drops + 1] = entry
        end
      else
        local delta = moved_by[holder] or 0

        -- delta == 0 means the region is already in place; nothing to do.
        if delta ~= 0 then
          local bound = bounds[holder]
          local fully_inside = (piece.position - bound.start_time > -BOUNDARY_TOLERANCE)
            and (bound.end_time - (piece.position + piece.length) > -BOUNDARY_TOLERANCE)

          if not fully_inside then
            -- Unreachable by construction: every bound of a moving region is
            -- in `boundaries`, so a piece inside one cannot cross out of it.
            -- Kept as a guard because being wrong here means mis-placing
            -- audio, and a refusal is the cheapest possible failure.
            straddling[#straddling + 1] = { track_index = item.track_index,
              track_name = item.track_name, position = piece.position, region_name = holder }
          elseif item.timebase_safe == false then
            unsafe[#unsafe + 1] = { track_index = item.track_index,
              track_name = item.track_name, position = piece.position, region_name = holder }
          else
            item_moves[#item_moves + 1] = {
              track_index = item.track_index,
              from = piece.position,
              to = piece.position + delta,
              length = piece.length,
              delta = delta,
            }
          end
        end
      end
    end
  end

  if #straddling > 0 or #unsafe > 0 then
    local lines = {}
    for _, s in ipairs(straddling) do
      lines[#lines + 1] = ("  %s, %.3fs: still crosses a boundary of region %q after cutting -- "
        .. "this is a bug in the planner, not something to fix in the project")
        :format(describe_track(s), s.position, s.region_name)
    end
    for _, u in ipairs(unsafe) do
      lines[#lines + 1] = ("  %s, %.3fs: timebase is not confirmed safe to reposition (region %q)")
        :format(describe_track(u), u.position, u.region_name)
    end
    return nil, table.concat({
      "Repack cannot move every item this Arrangement's regions carry:",
      table.concat(lines, "\n"),
    }, "\n")
  end

  for _, item in ipairs(loose_items) do
    park({
      kind = "item",
      track_index = item.track_index,
      from = item.position,
      length = item.length,
    })
  end

  local park_delta = 0
  if earliest then
    -- Never drag parked material backwards: material already clear of the
    -- Packed Block stays where the user left it.
    park_delta = math.max(0, (packed_end + regions.PARK_GAP) - earliest)
  end

  if nearly_equal(park_delta, 0) then
    park_delta = 0
    parked = {}
  else
    for _, entry in ipairs(parked) do
      entry.delta = park_delta
      -- Every parked kind moves the same way, so every entry carries its
      -- destination the same way -- the applier routes on `kind` alone and
      -- never re-derives a position from the offset.
      entry.to = entry.from + park_delta
    end
  end

  -- Fold the homeless tempo markers gathered above into tempo_moves, now that
  -- park_delta is known, and drop them out of `parked`: they are written this
  -- run (apply.tempo_moves), unlike everything else `parked` still holds, so
  -- leaving them there too would double-report the same move as both applied
  -- and pending.
  do
    local remaining = {}
    for _, entry in ipairs(parked) do
      if entry.kind == "tempo" then
        tempo_moves[#tempo_moves + 1] = {
          kind = "park",
          from = entry.from,
          to = entry.from + entry.delta,
          delta = entry.delta,
          bpm = entry.bpm,
          timesig_num = entry.timesig_num,
          timesig_denom = entry.timesig_denom,
          lineartempo = entry.lineartempo,
        }
      else
        remaining[#remaining + 1] = entry
      end
    end
    parked = remaining
  end

  -- Ascending by track, then position, so the applier's cuts on one track run
  -- left to right and the log reads in timeline order. Drops are ordered the
  -- same way: the log is the only record of what was discarded, so it has to
  -- be readable.
  local function by_track_then_position(a, b)
    if a.track_index ~= b.track_index then
      return a.track_index < b.track_index
    end
    return a.position < b.position
  end
  table.sort(splits, by_track_then_position)
  table.sort(drops, by_track_then_position)
  table.sort(envelope_drops, by_track_then_position)

  return {
    splits = splits,
    -- The fade the split edges *should* get (ADR-0002). Still unapplied: the
    -- D_FADEINLEN/D_FADEOUTLEN keys could not be confirmed from any reachable
    -- source (research/reaper-scripting.md §4.3a), so split edges currently
    -- inherit REAPER's own split preference. Recorded in the plan because the
    -- intent is settled even though the write is not.
    cut_fade = regions.CUT_FADE,
    drops = drops,
    pads = pads,
    -- One entry per region the Arrangement asked for a non-zero Headroom, in
    -- Arrangement order, whether or not it resolved to a change. `plan.places`
    -- is still the instruction that moves the end; this is the record of why.
    headroom = headroom,
    places = places,
    tempo_moves = tempo_moves,
    envelope_moves = envelope_moves,
    envelope_drops = envelope_drops,
    envelope_anchors = envelope_anchors,
    marker_moves = marker_moves,
    item_moves = item_moves,
    parks = parked,
    park_delta = park_delta,
    packed_end = packed_end,
    -- Anchors that would change nothing do not count as work -- see the
    -- redundancy pass above. Every other category counts by length, because
    -- a planned move or drop is by construction a change; only anchors are
    -- planned unconditionally, at every bound, on every run.
    is_empty = #splits == 0 and #drops == 0 and #pads == 0 and #places == 0
      and #tempo_moves == 0 and #envelope_moves == 0 and #envelope_drops == 0
      and #marker_moves == 0 and #item_moves == 0 and #parked == 0
      and changing_envelope_anchors == 0,
    -- How many anchors would actually write a different value or shape. The
    -- applier is still handed all of them (ADR-0004).
    changing_envelope_anchors = changing_envelope_anchors,
  }
end

return regions
