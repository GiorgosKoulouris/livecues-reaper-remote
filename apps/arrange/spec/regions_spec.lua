local regions = require("lib.regions")

-- A constant 120 bpm 4/4 grid: one bar every 2 seconds. Real bar lines come
-- from REAPER via an injected oracle (see ADR-0004 and the tempo decision in
-- lib/regions.lua); this fake makes the arithmetic checkable by hand.
local function bars_every(seconds)
  local function at_or_before(time)
    return math.floor(time / seconds + 1e-9) * seconds
  end

  return {
    next_bar_at_or_after = function(time)
      local bars = time / seconds
      local whole = math.floor(bars + 1e-9)
      if bars - whole < 1e-9 then
        return whole * seconds
      end
      return (whole + 1) * seconds
    end,
    -- The two directional primitives Headroom resolution needs (ADR-0006 keeps
    -- both in the oracle rather than letting the planner do bar arithmetic).
    bar_at_or_before = at_or_before,
    bar_after = function(time) return at_or_before(time) + seconds end,
    tempo_at = function() return 120, 4, 4 end,
  }
end

local grid = bars_every(2)

-- An oracle that never Pads: every time is already on a bar line. Lets a spec
-- assert against real transcribed positions from the live project without
-- Padding rounding them to a synthetic grid first.
local unpadded = {
  next_bar_at_or_after = function(time) return time end,
  tempo_at = function() return 120, 4, 4 end,
}

local function region(name, start_time, end_time, number)
  return { name = name, number = number or 1, start_time = start_time, end_time = end_time }
end

local function item(position, length, track_index, timebase_safe, track_name)
  if timebase_safe == nil then
    timebase_safe = true
  end
  return { position = position, length = length, track_index = track_index or 1,
    track_name = track_name, timebase_safe = timebase_safe }
end

local function envelope_point(position, track_index, envelope_name, overrides)
  local point = {
    position = position,
    track_index = track_index or 1,
    track_name = nil,
    envelope_name = envelope_name or "Volume",
    value = 0.5,
    shape = 0,
    tension = 0,
    selected = false,
  }
  for key, value in pairs(overrides or {}) do
    point[key] = value
  end
  return point
end

local function place_named(plan, name)
  for _, place in ipairs(plan.places) do
    if place.name == name then
      return place
    end
  end
  return nil
end

local function snapshot(overrides)
  local snap = {
    project_path = [[D:\P\Song.RPP]],
    regions = {},
    markers = {},
    items = {},
    tempo_markers = {},
  }
  for key, value in pairs(overrides or {}) do
    snap[key] = value
  end
  return snap
end

describe("regions.plan_anchors", function()
  it("writes a Tempo Anchor at every region start", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 4, 10, 1), region("Maze", 12, 20, 2) },
    }), grid)

    assert.are.equal(2, #plan.anchors)
    assert.are.equal(4, plan.anchors[1].time)
    assert.are.equal("Intro", plan.anchors[1].region_name)
    assert.are.equal(12, plan.anchors[2].time)
  end)

  it("orders anchors by time regardless of region order in the snapshot", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Late", 50, 60, 9), region("Early", 4, 10, 1) },
    }), grid)

    assert.are.equal("Early", plan.anchors[1].region_name)
    assert.are.equal("Late", plan.anchors[2].region_name)
  end)

  -- ADR-0004 says an explicit tempo *and* time-signature marker, so the plan
  -- carries both rather than leaving the applier to re-derive them.
  it("records the tempo and time signature in effect at the region start", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 4, 10, 1) },
    }), grid)

    assert.are.equal(120, plan.anchors[1].bpm)
    assert.are.equal(4, plan.anchors[1].timesig_num)
    assert.are.equal(4, plan.anchors[1].timesig_denom)
  end)

  -- Mid-ramp the tempo in effect is not any marker's bpm, so the value comes
  -- from the oracle rather than from the nearest tempo marker.
  it("takes the tempo from the oracle, not from the nearest tempo marker", function()
    local ramping = {
      next_bar_at_or_after = grid.next_bar_at_or_after,
      tempo_at = function(time) return 100 + time, 7, 8 end,
    }
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 4, 10, 1) },
      tempo_markers = { { position = 0, bpm = 100, starts_measure = true } },
    }), ramping)

    assert.are.equal(104, plan.anchors[1].bpm)
    assert.are.equal(7, plan.anchors[1].timesig_num)
  end)

  -- ADR-0004 says every region start, with no exemption -- docs/decisions.md lists
  -- this among the decisions not to quietly soften. Idempotence is the applier's
  -- job: it replaces a marker at a position rather than adding one.
  it("anchors a region even when it already starts a measure", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 4, 10, 1), region("Maze", 12, 20, 2) },
      tempo_markers = { { position = 4, bpm = 120, starts_measure = true } },
    }), grid)

    assert.are.equal(2, #plan.anchors)
    assert.are.equal("Intro", plan.anchors[1].region_name)
  end)

  it("is empty for a project with no regions", function()
    local plan = regions.plan_anchors(snapshot(), grid)
    assert.are.same({}, plan.anchors)
    assert.is_true(plan.is_empty)
  end)

  -- This is what makes a *parked* region keep its own tempo (issue #7), and it
  -- is easy to mistake for over-reach and "fix". Phase 1 anchors every region
  -- in the project, including ones no Arrangement places. Phase 2 then finds
  -- that anchor sitting inside no placed region and parks it by the same
  -- offset as the region it marks, so the anchor travels with it for free.
  -- Anchoring only the arranged regions would leave a parked region inheriting
  -- whatever tempo the Packed Block left in effect -- the exact failure Tempo
  -- Anchors exist to prevent, aimed at the one category that would be exempt.
  it("anchors regions no Arrangement places, so a parked region keeps its own tempo", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 10, 20, 1), region("Outtake", 40, 50, 2) },
      tempo_markers = { { position = 0, bpm = 100 } },
    }), grid)

    local anchored = {}
    for _, anchor in ipairs(plan.anchors) do
      anchored[anchor.region_name] = anchor.time
    end
    assert.are.equal(40, anchored["Outtake"])
  end)

  -- SetTempoTimeSigMarker demands a lineartempo flag, and both constant answers
  -- are wrong somewhere: always-square flattens a ramp the anchor lands inside
  -- (moving the grid downstream, dragging beat-based material), always-linear
  -- invents a ramp in a project that had none. The flag in effect preserves the
  -- curve either way.
  it("inherits lineartempo from the marker in effect at the region start", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 10, 20, 1) },
      tempo_markers = {
        { position = 0, bpm = 100, lineartempo = false },
        { position = 5, bpm = 120, lineartempo = true },
      },
    }), grid)

    assert.is_true(plan.anchors[1].lineartempo)
  end)

  it("does not inherit lineartempo from a marker after the region start", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 10, 20, 1) },
      tempo_markers = {
        { position = 5, bpm = 120, lineartempo = false },
        { position = 15, bpm = 140, lineartempo = true },
      },
    }), grid)

    assert.is_false(plan.anchors[1].lineartempo)
  end)

  it("takes the flag of a marker sitting exactly on the region start", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 10, 20, 1) },
      tempo_markers = {
        { position = 0, bpm = 100, lineartempo = false },
        { position = 10, bpm = 120, lineartempo = true },
      },
    }), grid)

    assert.is_true(plan.anchors[1].lineartempo)
  end)

  it("defaults lineartempo to false when no marker precedes the region", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 10, 20, 1) },
    }), grid)

    assert.is_false(plan.anchors[1].lineartempo)
  end)

  -- Issue #19. A region start and a tempo marker a few microseconds apart are
  -- two independently authored numbers describing the same instant, and asking
  -- the oracle about the instant *fractionally before* the marker answers with
  -- the previous region's tempo. The applier then replaces the real marker
  -- with that value -- its lookup matches within the same tolerance -- so the
  -- region ends up running at its predecessor's tempo and beat-attached
  -- material slides out of it. The oracle stays the source everywhere else;
  -- this is a narrowing of that rule, not a reversal of it.
  --
  -- The fake oracle below is the disagreement made explicit: it answers with
  -- the tempo in force *before* the marker, exactly as REAPER does when asked
  -- about a time 2e-5s earlier than the marker sitting at the region start.
  local function oracle_answering(bpm, num, denom)
    return {
      next_bar_at_or_after = grid.next_bar_at_or_after,
      tempo_at = function() return bpm, num or 4, denom or 4 end,
    }
  end

  it("takes the bpm of a marker sitting microseconds after the region start", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Darkness of Blue", 800.52495786, 900, 1) },
      tempo_markers = {
        { position = 643.51563, bpm = 107, timesig_num = 4, timesig_denom = 4 },
        { position = 800.52497839, bpm = 112, timesig_num = 4, timesig_denom = 4 },
      },
    }), oracle_answering(107))

    assert.are.equal(112, plan.anchors[1].bpm)
  end)

  it("takes the bpm of a marker sitting microseconds before the region start", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Darkness of Blue", 800.52497839, 900, 1) },
      tempo_markers = {
        { position = 643.51563, bpm = 107, timesig_num = 4, timesig_denom = 4 },
        { position = 800.52495786, bpm = 112, timesig_num = 4, timesig_denom = 4 },
      },
    }), oracle_answering(107))

    assert.are.equal(112, plan.anchors[1].bpm)
  end)

  it("takes the bpm of a marker sitting exactly on the region start", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 10, 20, 1) },
      tempo_markers = {
        { position = 0, bpm = 107, timesig_num = 4, timesig_denom = 4 },
        { position = 10, bpm = 112, timesig_num = 4, timesig_denom = 4 },
      },
    }), oracle_answering(112))

    assert.are.equal(112, plan.anchors[1].bpm)
  end)

  -- A real tempo change shortly before a region is not a description of the
  -- region's own start, so it must not be copied onto it.
  it("ignores a marker further from the region start than the tolerance", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 10, 20, 1) },
      tempo_markers = {
        { position = 10 - regions.BOUNDARY_TOLERANCE * 10, bpm = 112,
          timesig_num = 4, timesig_denom = 4 },
      },
    }), oracle_answering(107))

    assert.are.equal(107, plan.anchors[1].bpm)
  end)

  it("keeps the oracle's ramped reading when no marker is near the region start", function()
    local ramping = {
      next_bar_at_or_after = grid.next_bar_at_or_after,
      tempo_at = function(time) return 100 + time, 4, 4 end,
    }
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 4, 10, 1) },
      tempo_markers = { { position = 0, bpm = 100, timesig_num = 4, timesig_denom = 4 } },
    }), ramping)

    assert.are.equal(104, plan.anchors[1].bpm)
  end)

  -- The oracle deliberately disagrees on every field here, so there is no
  -- reading of a pass that leaves the source ambiguous.
  it("takes the time signature and linear flag of the coincident marker too", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 10, 20, 1) },
      tempo_markers = {
        { position = 10.00002, bpm = 112, timesig_num = 7, timesig_denom = 8, lineartempo = true },
      },
    }), oracle_answering(107, 4, 4))

    assert.are.equal(112, plan.anchors[1].bpm)
    assert.are.equal(7, plan.anchors[1].timesig_num)
    assert.are.equal(8, plan.anchors[1].timesig_denom)
    assert.is_true(plan.anchors[1].lineartempo)
  end)

  -- A tempo-only marker carries no time signature, and REAPER reports that as
  -- `-1/-1` (`0/0` reaching `SetTempoTimeSigMarker` means "keep the previous
  -- signature" -- research §4.4a). Copying either onto an Anchor writes a
  -- marker that does not start a measure, which is the one thing ADR-0004 asks
  -- a Tempo Anchor to do: the region start would stop being a bar line. The
  -- marker's *tempo* is still the better answer, so only the signature falls
  -- back. Measured -- 16 of the live project's 19 anchors are this shape.
  it("falls back to the oracle's time signature when the marker carries none", function()
    for _, absent in ipairs({ -1, 0 }) do
      local plan = regions.plan_anchors(snapshot({
        regions = { region("Darkness of Blue", 800.52495786, 900, 1) },
        tempo_markers = {
          { position = 800.52497839, bpm = 112, timesig_num = absent, timesig_denom = absent },
        },
      }), oracle_answering(107, 4, 4))

      assert.are.equal(112, plan.anchors[1].bpm)
      assert.are.equal(4, plan.anchors[1].timesig_num)
      assert.are.equal(4, plan.anchors[1].timesig_denom)
    end
  end)

  -- ...and such an anchor is not redundant, because writing it does change the
  -- map: the marker gains the time signature that makes the region start a
  -- measure. It settles on the second run, when the marker carries it.
  it("does not judge an anchor redundant when only the marker's signature is absent", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 10, 20, 1) },
      tempo_markers = {
        { position = 10.00002, bpm = 112, timesig_num = -1, timesig_denom = -1, lineartempo = false },
      },
    }), oracle_answering(112, 4, 4))

    assert.is_false(plan.anchors[1].redundant)
  end)

  it("takes the nearest marker when two fall inside the tolerance", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 10, 20, 1) },
      tempo_markers = {
        { position = 10 - 8e-5, bpm = 107, timesig_num = 4, timesig_denom = 4 },
        { position = 10 + 2e-5, bpm = 112, timesig_num = 4, timesig_denom = 4 },
      },
    }), oracle_answering(90))

    assert.are.equal(112, plan.anchors[1].bpm)
  end)

  -- Two markers equidistant from the start is a coin toss the module already
  -- has a convention for: the earlier one, as when it collapses a cluster of
  -- boundaries to its earliest member. Asserted rather than left to whichever
  -- order the snapshot happened to arrive in.
  it("resolves a tie between two equidistant markers to the earlier one", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 10, 20, 1) },
      tempo_markers = {
        { position = 10 + 2e-5, bpm = 112, timesig_num = 4, timesig_denom = 4 },
        { position = 10 - 2e-5, bpm = 107, timesig_num = 4, timesig_denom = 4 },
      },
    }), oracle_answering(90))

    assert.are.equal(107, plan.anchors[1].bpm)
  end)

  -- The consequence that earns ADR-0004's idempotence claim back: an anchor
  -- over a coincident marker already carrying these values changes nothing, so
  -- a repeat Repack of an already-packed project still creates no undo point.
  it("judges an anchor over a coincident marker carrying these values redundant", function()
    local plan = regions.plan_anchors(snapshot({
      regions = { region("Intro", 10, 20, 1) },
      tempo_markers = {
        { position = 10.00002, bpm = 112, timesig_num = 4, timesig_denom = 4, lineartempo = false },
      },
    }), oracle_answering(107))

    assert.is_true(plan.anchors[1].redundant)
    assert.is_true(plan.is_noop)
  end)
end)

describe("regions.plan_pack tempo slices", function()
  -- Placement is a cumulative sum of unchanged durations, which is only valid
  -- if each region's tempo slice moves with it (ADR-0006).
  it("moves the tempo markers inside a placed region by the same delta", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        tempo_markers = {
          { position = 10, bpm = 120, timesig_num = 4, timesig_denom = 4, lineartempo = false },
          { position = 13, bpm = 90, timesig_num = 3, timesig_denom = 4, lineartempo = true },
        },
      }), { "A" }, grid))

    assert.are.equal(2, #plan.tempo_moves)
    for _, move in ipairs(plan.tempo_moves) do
      assert.are.equal(-10, move.delta)
      assert.are.equal("A", move.region_name)
      assert.are.equal("region", move.kind)
    end
    assert.are.equal(0, plan.tempo_moves[1].to)
    assert.are.equal(120, plan.tempo_moves[1].bpm)
    assert.are.equal(3, plan.tempo_moves[2].to)
    assert.are.equal(90, plan.tempo_moves[2].bpm)
    assert.are.equal(3, plan.tempo_moves[2].timesig_num)
    assert.is_true(plan.tempo_moves[2].lineartempo)
  end)

  -- Issue #4/#12: a tempo marker in a gap belongs to no region, so once
  -- Repack closes the gap it would otherwise be silently left behind under
  -- whatever region lands on top of its old position. It parks instead,
  -- translated by the same shared offset as the rest of Parked Material
  -- (CONTEXT.md) -- deleting it outright was rejected because issue #10
  -- shows that can slide beat-based material downstream of it.
  it("parks a tempo marker that belongs to no region, by the shared park offset", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        tempo_markers = { { position = 20, bpm = 90, timesig_num = 4, timesig_denom = 4 } },
      }), { "A" }, grid))

    assert.are.equal(1, #plan.tempo_moves)
    local move = plan.tempo_moves[1]
    assert.are.equal("park", move.kind)
    assert.are.equal(20, move.from)
    -- Region A (10..16) moves to 0..6, so packed_end is 6; PARK_GAP is the
    -- distance beyond that Parked Material sits.
    assert.are.equal(regions.PARK_GAP + 6, move.to)
    assert.are.equal(90, move.bpm)
  end)

  -- Parked Material already clear of the Packed Block is left where it is
  -- (mirrors the same rule for regions/markers/items, "does not pull parked
  -- material earlier").
  it("does not park a tempo marker already clear of the packed block", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        -- Beyond packed_end (6) + PARK_GAP, so the clamp applies. Expressed
        -- in terms of the constant rather than as a literal: PARK_GAP is a
        -- tuning value and has already been raised once, which silently turned
        -- a literal here into a marker that was no longer clear at all.
        tempo_markers = { { position = regions.PARK_GAP + 100, bpm = 90 } },
      }), { "A" }, grid))

    assert.are.same({}, plan.tempo_moves)
  end)

  it("plans no tempo move for a region that does not move", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1) },
        tempo_markers = { { position = 0, bpm = 120 } },
      }), { "A" }, grid))

    assert.are.same({}, plan.tempo_moves)
  end)

  -- A homeless tempo marker travels with everything else Parked, by the same
  -- shared offset (CONTEXT.md), even though it is written through
  -- tempo_moves rather than left sitting in plan.parks.
  it("shifts a homeless tempo marker by the same offset as everything else parked", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("X", 20, 26, 2) },
        tempo_markers = { { position = 40, bpm = 90 } },
      }), { "A" }, grid))

    assert.are.equal(1, #plan.tempo_moves)
    assert.are.equal("park", plan.tempo_moves[1].kind)

    local park_x
    for _, park in ipairs(plan.parks) do
      if park.name == "X" then
        park_x = park
      end
    end
    assert.are.equal(plan.tempo_moves[1].to - plan.tempo_moves[1].from, park_x.delta)
  end)
end)

describe("regions.plan_pack automation anchors", function()
  -- An oracle that reports a distinct value per time, so a spec can tell which
  -- bound each anchor was evaluated at.
  local function values(map)
    return { value_at = function(_, _, time) return map[time] or 0 end }
  end

  -- The problem these exist for, in miniature. "B" has no automation point of
  -- its own: its level is whatever "A" established before it. Repack puts "B"
  -- first, so without an anchor it would inherit whatever now precedes it.
  it("anchors both bounds of every placed region with the value already in effect there", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1), region("B", 20, 26, 2) },
        -- 0.3 is in effect across "A", 0.7 across "B".
        envelope_points = {
          envelope_point(8, 3, "Volume", { value = 0.3 }),
          envelope_point(18, 3, "Volume", { value = 0.7 }),
        },
      }), { "B", "A" }, unpadded, values({})))

    local anchored = {}
    for _, anchor in ipairs(plan.envelope_anchors) do
      anchored[#anchored + 1] = ("%s@%.0f=%.1f"):format(anchor.region_name, anchor.to, anchor.value)
    end
    -- "B" packs to 0..6, "A" follows at 6..12. Each region keeps the value it
    -- had on the *original* timeline, which is the whole point: swapping their
    -- order must not make either inherit the other's.
    assert.are.same({ "B@0=0.7", "B@6=0.7", "A@6=0.3", "A@12=0.3" }, anchored)
  end)

  -- A ramp can never legitimately begin at a region bound, so every anchor is
  -- square. A real run wrote them linear, and an end anchor holding 1 ramped
  -- down to the 0 the following region set 115s later instead of stepping.
  it("makes every anchor square, whichever bound it sits on", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        envelope_points = { envelope_point(4, 3, "Volume", { shape = 0 }) },
      }), { "A" }, unpadded, values({})))

    assert.are.equal(2, #plan.envelope_anchors)
    for _, anchor in ipairs(plan.envelope_anchors) do
      assert.are.equal(1, anchor.shape)
    end
  end)

  -- The Transpose regression. A ramp crossing a region bound interpolates
  -- between two songs the Repack is about to separate, so sampling it yields a
  -- number nobody wrote -- real data produced 0.49848908, 0.49833384,
  -- 0.49787437 ... where 0.5 was the authored value. The originating point's
  -- value cancels the doomed ramp and gives back what was written.
  it("takes the last authored value at a bound, not a sample of a ramp crossing it", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        -- 0.5 authored well before the region, ramping linearly to a point
        -- well after it: at both bounds the oracle would report a midpoint.
        envelope_points = {
          envelope_point(0, 3, "Volume", { value = 0.5, shape = 0 }),
          envelope_point(100, 3, "Volume", { value = 0.72, shape = 0 }),
        },
      }), { "A" }, unpadded, values({ [10] = 0.49848908, [16] = 0.49833384 })))

    for _, anchor in ipairs(plan.envelope_anchors) do
      assert.are.equal(0.5, anchor.value)
    end
  end)

  -- The regression that made the two bounds asymmetric. Region membership is
  -- half-open, so a point exactly on a region's *end* is not inside it -- it
  -- moves with the next region, parks, or is dropped. Suppressing the end
  -- anchor because that point exists left a real region ramping 265s into the
  -- next song, once the point was dropped.
  it("anchors a region end even when a point sits exactly on it", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        envelope_points = {
          envelope_point(10, 3, "Volume", { value = 0.3 }), -- on the start: inside, travels
          envelope_point(16, 3, "Volume", { value = 0.8 }), -- on the end: NOT inside
        },
      }), { "A" }, unpadded, values({})))

    assert.are.equal(1, #plan.envelope_anchors)
    local anchor = plan.envelope_anchors[1]
    assert.are.equal("end", anchor.edge)
    -- The value the region *ends* on is the last one strictly inside it, not
    -- the one on the bound, which belongs to whatever comes next.
    assert.are.equal(0.3, anchor.value)
  end)

  -- Real automation is authored as step pairs: two points at one time, the
  -- second being the value actually in effect afterwards (track 14's Transpose
  -- steps 0.495 -> 0.72 this way).
  it("takes the last of a step pair as the value in effect", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        envelope_points = {
          envelope_point(4, 3, "Volume", { value = 0.495 }),
          envelope_point(4, 3, "Volume", { value = 0.72 }),
        },
      }), { "A" }, unpadded, values({})))

    assert.are.equal(2, #plan.envelope_anchors)
    for _, anchor in ipairs(plan.envelope_anchors) do
      assert.are.equal(0.72, anchor.value)
    end
  end)

  -- With no point before the bound the value is the envelope's own default,
  -- which the points cannot express -- the one case the oracle still answers.
  it("falls back to the oracle when no point precedes the bound", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        envelope_points = { envelope_point(30, 3, "Volume", { value = 0.9 }) },
      }), { "A" }, unpadded, values({ [10] = 0.25, [16] = 0.25 })))

    assert.are.equal(2, #plan.envelope_anchors)
    for _, anchor in ipairs(plan.envelope_anchors) do
      assert.are.equal(0.25, anchor.value)
    end
  end)

  -- Adjacent placed regions share a bound, so two anchors land on one time.
  -- That is a zero-length segment, which is how REAPER expresses a step -- and
  -- a step is exactly what a song change wants.
  it("lets the end anchor of one region and the start anchor of the next share a time", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1), region("B", 20, 26, 2) },
        envelope_points = {
          envelope_point(8, 3, "Volume", { value = 0.9 }),
          envelope_point(18, 3, "Volume", { value = 0.1 }),
        },
      }), { "A", "B" }, unpadded, values({})))

    local at_six = {}
    for _, anchor in ipairs(plan.envelope_anchors) do
      if anchor.to == 6 then at_six[#at_six + 1] = anchor.value end
    end
    assert.are.same({ 0.9, 0.1 }, at_six)
  end)

  -- Overwriting a deliberate point with an evaluated one would be a silent
  -- edit of the user's automation, not a rescue of it.
  it("plans no anchor on a bound that already carries a point of its own", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        envelope_points = { envelope_point(10, 3, "Volume") },
      }), { "A" }, unpadded, values({})))

    assert.are.equal(1, #plan.envelope_anchors)
    assert.are.equal(16, plan.envelope_anchors[1].from)
  end)

  -- ...but only when nothing else is going to clear that time. Packing makes
  -- consecutive placed regions share a bound, so on a second Repack of an
  -- already-packed project every interior bound holds the previous run's
  -- anchors. Suppressing the start anchor there does not protect them:
  -- apply.envelope_anchors clears a time before writing it, so the earlier
  -- region's end anchor would delete them and stand alone -- replacing the value
  -- in effect from that bound with the one from the region before it.
  it("still anchors a start that shares its bound with the previous region's end", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        -- Already packed and already anchored: the shape a second run sees.
        regions = { region("A", 0, 6, 1), region("B", 6, 12, 2) },
        envelope_points = {
          envelope_point(6, 3, "Volume", { value = 0.2 }),
          envelope_point(6, 3, "Volume", { value = 0.8 }),
        },
      }), { "A", "B" }, unpadded, values({})))

    local at_six = {}
    for _, anchor in ipairs(plan.envelope_anchors) do
      if anchor.to == 6 then
        at_six[#at_six + 1] = anchor.edge
      end
    end

    -- Both, in this order: the step at a shared bound is two points, and the
    -- second is the value in effect going forward.
    assert.are.same({ "end", "start" }, at_six)
  end)

  -- An envelope with no points has no automation to preserve, and anchoring it
  -- would author automation the project never had.
  it("plans no anchors at all when the project has no envelope points", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("A", 10, 16, 1) } }), { "A" }, unpadded, values({})))

    assert.are.same({}, plan.envelope_anchors)
  end)

  it("plans no anchors when no automation oracle is injected", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        envelope_points = { envelope_point(12, 3, "Volume") },
      }), { "A" }, unpadded))

    assert.are.same({}, plan.envelope_anchors)
  end)
end)

-- Issue #13. `is_empty` used not to count `envelope_anchors` at all, which
-- kept a repeat Repack a clean no-op but meant a plan whose *only* work was
-- anchors reported "nothing to do" and wrote nothing. Both behaviours are
-- wanted, so the anchors carry a `redundant` flag and `is_empty` counts only
-- the ones that would change something -- the same distinction
-- `plan_anchors` already draws for Tempo Anchors.
describe("regions.plan_pack automation anchor redundancy", function()
  local function values(map)
    return { value_at = function(_, _, time) return map[time] or 0 end }
  end

  -- A square point, which is what an anchor writes. The previous run's
  -- anchors are exactly this shape, so this is what a second Repack meets.
  local function anchor_point(position, value)
    return envelope_point(position, 3, "Volume", { value = value, shape = 1 })
  end

  -- Already packed, so nothing moves and nothing is dropped: the plan's only
  -- work is anchors. Both bounds are bare, so both anchors do something.
  it("is not empty when the only work is anchors that would change something", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1) },
        envelope_points = { envelope_point(3, 3, "Volume") },
      }), { "A" }, unpadded, values({})))

    assert.are.same({}, plan.envelope_moves)
    assert.are.same({}, plan.envelope_drops)
    assert.are.same({}, plan.places)
    assert.are.equal(2, #plan.envelope_anchors)
    for _, anchor in ipairs(plan.envelope_anchors) do
      assert.is_false(anchor.redundant)
    end
    assert.is_false(plan.is_empty)
  end)

  -- The property that made the original omission defensible, and which the
  -- fix must not cost: a second Repack of an already-anchored project has
  -- nothing to do, so it creates no undo point (CLAUDE.md).
  it("stays empty when every anchor would rewrite the value already there", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1) },
        envelope_points = { anchor_point(0, 0.5), anchor_point(6, 0.5) },
      }), { "A" }, unpadded, values({})))

    for _, anchor in ipairs(plan.envelope_anchors) do
      assert.is_true(anchor.redundant)
    end
    assert.is_true(plan.is_empty)
  end)

  -- The real second-Repack shape: consecutive placed regions share a bound,
  -- so the interior bound carries two anchors -- the earlier region's end and
  -- the later one's start. That pair is a deliberate step, and both halves
  -- have to match for the group to count as redundant.
  it("stays empty across a shared bound already holding the step pair", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("B", 6, 12, 2) },
        envelope_points = {
          anchor_point(0, 0.2),
          anchor_point(6, 0.2), anchor_point(6, 0.8), -- A's end, then B's start
          anchor_point(12, 0.8),
        },
      }), { "A", "B" }, unpadded, values({})))

    for _, anchor in ipairs(plan.envelope_anchors) do
      assert.is_true(anchor.redundant, ("anchor %s@%.0f"):format(anchor.region_name, anchor.to))
    end
    assert.is_true(plan.is_empty)
  end)

  it("is not empty when a point at the bound holds a different value", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1) },
        envelope_points = { anchor_point(0, 0.5), anchor_point(6, 0.9) },
      }), { "A" }, unpadded, values({})))

    assert.is_false(plan.is_empty)
  end)

  -- Shape counts as much as value. An anchor is square, and a linear point at
  -- the same time with the same value ramps into the next region instead of
  -- stepping -- the exact bug ADR-0006 records a real run producing.
  it("is not empty when a point at the bound holds the right value but the wrong shape", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1) },
        envelope_points = {
          anchor_point(0, 0.5),
          envelope_point(6, 3, "Volume", { value = 0.5, shape = 0 }),
        },
      }), { "A" }, unpadded, values({})))

    assert.is_false(plan.is_empty)
  end)

  -- One point where the plan writes two is not redundant, because the applier
  -- clears the time and writes the whole group: the missing half of the step
  -- would be created, which is a change.
  it("is not empty when a shared bound holds only half of the step pair", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("B", 6, 12, 2) },
        envelope_points = {
          anchor_point(0, 0.2),
          anchor_point(6, 0.2), -- B's start anchor has no counterpart here
          anchor_point(12, 0.8),
        },
      }), { "A", "B" }, unpadded, values({})))

    assert.is_false(plan.is_empty)
  end)

  -- Where two points share a time the last one wins, so the pair is ordered
  -- data, not a set. Reversing it inverts the value in effect from that bound
  -- -- the same silent flip docs/decisions.md records `apply.envelope_anchors`
  -- being
  -- rewritten to prevent.
  it("is not empty when the step pair at a shared bound is in the wrong order", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("B", 6, 12, 2) },
        envelope_points = {
          anchor_point(0, 0.2),
          anchor_point(6, 0.8), anchor_point(6, 0.2), -- reversed
          anchor_point(12, 0.8),
        },
      }), { "A", "B" }, unpadded, values({})))

    assert.is_false(plan.is_empty)
  end)

  -- ADR-0004 forbids deciding a region does not deserve an anchor. Redundancy
  -- answers a different question -- whether the run has work to do -- and the
  -- applier is still handed every anchor either way.
  it("still plans and hands over every anchor, redundant or not", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1) },
        envelope_points = { anchor_point(0, 0.5), anchor_point(6, 0.5) },
      }), { "A" }, unpadded, values({})))

    assert.is_true(plan.is_empty)
    assert.are.equal(1, #plan.envelope_anchors) -- A's start is covered by its own point
    assert.are.equal(6, plan.envelope_anchors[1].to)
  end)

  -- The pairing of existing points to anchors is in snapshot order, which is
  -- a guess once a point *moves* to a bound -- predicting where REAPER sorts
  -- a moved point among coincident ones would mean modelling its sort. This
  -- pins why that cannot mislead: an Arrangement that actually reorders moves
  -- envelope points, so `envelope_moves` is non-empty and the plan is not
  -- empty whatever redundancy decides. Redundancy only settles `is_empty` in
  -- the case where nothing moves, and there snapshot order is the final order.
  it("is not empty when a reordering Arrangement moves points onto a shared bound", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("B", 6, 12, 2) },
        envelope_points = {
          anchor_point(0, 0.2),
          anchor_point(6, 0.2), anchor_point(6, 0.8),
          anchor_point(12, 0.8),
        },
      }), { "B", "A" }, unpadded, values({})))

    assert.is_true(#plan.envelope_moves > 0, "a reorder must move the points it carries")
    assert.is_false(plan.is_empty)
  end)

  -- A point moving to the bound counts as what will be there, not what is
  -- there now: redundancy is asked of the timeline the plan produces.
  it("judges redundancy against where points land, not where they start", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        envelope_points = { anchor_point(10, 0.5), anchor_point(15, 0.5) },
      }), { "A" }, unpadded, values({})))

    -- "A" packs 10..16 -> 0..6, carrying both points to 0 and 5. The end
    -- anchor at 6 has nothing landing on it, so it is real work.
    assert.are.equal(2, #plan.envelope_moves)
    assert.is_false(plan.is_empty)
  end)
end)

describe("regions.plan_pack: nothing is written for a region that stays put", function()
  -- apply.lift_envelope_points only lifts the points the plan moves, so a point
  -- in a region whose delta is 0 would still follow a tempo write on a
  -- beat-timebase track (docs/decisions.md, issue 10). That is harmless only
  -- while a tempo write never happens without a region move, and while no
  -- tempo or envelope entry has a zero delta. This pins both.
  it("plans no tempo or envelope entry with a zero delta, and none for the region that stays", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("B", 8, 14, 2), region("C", 16, 22, 3) },
        tempo_markers = { { position = 1, bpm = 120 }, { position = 9, bpm = 100 } },
        envelope_points = { envelope_point(2, 1), envelope_point(10, 2) },
      }), { "A", "C", "B" }, grid))

    for _, move in ipairs(plan.tempo_moves) do
      assert.are_not.equal(0, move.delta)
      assert.are_not.equal("A", move.region_name)
    end
    for _, move in ipairs(plan.envelope_moves) do
      assert.are_not.equal(0, move.delta)
      assert.are_not.equal("A", move.region_name)
    end
    assert.is_true(#plan.envelope_moves > 0)
  end)
end)

describe("regions.plan_pack envelope points", function()
  -- Mirrors the tempo transplant: a region only keeps its automation in sync
  -- with its audio if the points inside it move by the same delta (issue #8).
  it("moves an envelope point inside a placed region by the same delta, preserving its shape", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        envelope_points = {
          envelope_point(12, 3, "Volume", { value = 0.75, shape = 1, tension = 0.2, selected = true }),
        },
      }), { "A" }, grid))

    assert.are.equal(1, #plan.envelope_moves)
    local move = plan.envelope_moves[1]
    assert.are.equal(3, move.track_index)
    assert.are.equal("Volume", move.envelope_name)
    assert.are.equal("A", move.region_name)
    assert.are.equal(2, move.to)
    assert.are.equal(-10, move.delta)
    assert.are.equal(0.75, move.value)
    assert.are.equal(1, move.shape)
    assert.are.equal(0.2, move.tension)
    assert.is_true(move.selected)
  end)

  it("plans no envelope move for a region that does not move", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1) }, -- already at the pack origin
        envelope_points = { envelope_point(2, 1) },
      }), { "A" }, grid))

    assert.are.same({}, plan.envelope_moves)
  end)

  -- Mirrors how an item inside an omitted region parks with it rather than
  -- being dropped: the point still belongs to a region, only not one this
  -- run places -- planned only, like the rest of that region's contents
  -- (#7), not applied the way a homeless tempo marker is (ADR-0006 amendment).
  it("parks an envelope point inside a region the Arrangement omits, rather than dropping it", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("Out", 20, 26, 2) },
        envelope_points = { envelope_point(22, 4, "Pan") },
      }), { "A" }, grid))

    assert.are.same({}, plan.envelope_moves)
    assert.are.same({}, plan.envelope_drops)

    local park
    for _, entry in ipairs(plan.parks) do
      if entry.kind == "envelope" then
        park = entry
      end
    end
    assert.is_truthy(park)
    assert.are.equal(4, park.track_index)
    assert.are.equal("Pan", park.envelope_name)
    assert.are.equal("Out", park.region_name)
    assert.are.equal(22, park.from)
  end)

  -- The user's explicit call: unlike a tempo marker, an envelope point
  -- carries no #10-style hazard from being deleted (nothing else's position
  -- depends on an automation value), so a point touching no region at all
  -- follows the general rule (Dropped Material) rather than tempo's parked
  -- exception.
  -- Real REAPER, running the same Arrangement twice: a point sitting exactly on
  -- the last placed region's end was dropped, then an anchor was written back at
  -- the identical time. Net-neutral only because apply.plan happens to order
  -- drops before anchors -- and it made every re-run's plan claim a destructive
  -- drop, in the one category whose log line is the only record of what was lost.
  it("does not drop a point an Automation Anchor is about to occupy", function()
    local automation = { value_at = function() return 0 end }
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1) },
        -- Exactly on the region's end: membership is half-open, so it is inside
        -- no region, and there is no region after it to carry it.
        envelope_points = { envelope_point(6, 1, "Volume") },
      }), { "A" }, grid, automation))

    assert.are.same({}, plan.envelope_drops)

    local anchored = false
    for _, anchor in ipairs(plan.envelope_anchors) do
      if anchor.to == 6 then
        anchored = true
      end
    end
    assert.is_true(anchored, "the region end should still get its own anchor")
  end)

  -- Without the automation oracle no anchors are planned, so nothing protects
  -- the point and the general rule applies again.
  it("still drops that point when no anchors are planned", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1) },
        envelope_points = { envelope_point(6, 1, "Volume") },
      }), { "A" }, grid))

    assert.are.equal(1, #plan.envelope_drops)
    assert.are.equal(6, plan.envelope_drops[1].position)
  end)

  it("drops an envelope point that belongs to no region at all", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        envelope_points = { envelope_point(2, 1, "Volume") }, -- before every region
      }), { "A" }, grid))

    assert.are.same({}, plan.envelope_moves)
    assert.are.equal(1, #plan.envelope_drops)
    assert.are.equal(1, plan.envelope_drops[1].track_index)
    assert.are.equal("Volume", plan.envelope_drops[1].envelope_name)
    assert.are.equal(2, plan.envelope_drops[1].position)

    local kinds = {}
    for _, entry in ipairs(plan.parks) do
      kinds[entry.kind] = true
    end
    assert.is_falsy(kinds.envelope)
  end)

  it("is empty for a project with no envelope points", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("A", 10, 16, 1) } }), { "A" }, grid))

    assert.are.same({}, plan.envelope_moves)
    assert.are.same({}, plan.envelope_drops)
  end)

  it("counts a non-empty envelope_moves towards is_empty", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        envelope_points = { envelope_point(12, 1) },
      }), { "A" }, grid))

    assert.is_false(plan.is_empty)
  end)

  it("counts a non-empty envelope_drops towards is_empty", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        envelope_points = { envelope_point(2, 1) },
      }), { "A" }, grid))

    assert.is_false(plan.is_empty)
  end)
end)

describe("regions.plan_pack padding", function()
  it("extends a region end to the next bar line", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("Intro", 0, 5, 1) } }), { "Intro" }, grid))

    assert.are.equal(1, #plan.pads)
    assert.are.equal(5, plan.pads[1].from_end)
    assert.are.equal(6, plan.pads[1].to_end)
  end)

  -- Padding is idempotent: an already-padded region is a whole number of bars.
  it("does not pad a region that already ends on a bar line", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("Intro", 0, 6, 1) } }), { "Intro" }, grid))

    assert.are.same({}, plan.pads)
  end)

  -- Real region ends miss their bar line by microseconds (lib/regions.lua's
  -- pad_regions comment: the live project's worst is ~1e-5s). At EPSILON that
  -- read as "not aligned" and bought a whole bar of silence, so the threshold
  -- is BOUNDARY_TOLERANCE. These two specs bracket it.
  it("treats a region ending a hair short of a bar line as already aligned", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("Intro", 0, 6 - 1.04e-5, 1) } }), { "Intro" }, grid))

    assert.are.same({}, plan.pads)
  end)

  it("leaves a within-tolerance region end exactly where it was", function()
    local nearly = 6 - 1.04e-5
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("Intro", 0, nearly, 1), region("Next", 8, 10, 2) } }),
      { "Intro", "Next" }, grid))

    -- Packing is a cumulative sum, so "Next" lands exactly on Intro's end. A
    -- nudge onto the computed bar line would show up here as 6.
    assert.are.equal(nearly, place_named(plan, "Next").to_start)
  end)

  it("still pads a genuine partial bar", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("Intro", 0, 5.5, 1) } }), { "Intro" }, grid))

    assert.are.equal(1, #plan.pads)
    assert.are.equal(0.5, plan.pads[1].added)
  end)

  -- Seven of the live project's region pairs are back-to-back. A pad that is
  -- only noise-sized must not abort the run on the overlap check.
  it("does not refuse when a within-tolerance end meets a back-to-back neighbour", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("A", 0, 6 - 1.04e-5, 1), region("B", 6 - 1.04e-5, 8, 2) } }),
      { "A", "B" }, grid))

    assert.are.same({}, plan.pads)
  end)

  it("pads only the regions the Arrangement names", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("Intro", 0, 5, 1), region("Parked", 20, 25, 2) } }),
      { "Intro" }, grid))

    assert.are.equal(1, #plan.pads)
    assert.are.equal("Intro", plan.pads[1].name)
  end)

  -- ADR-0004: regions are never overlapped. Padding into the next region would
  -- capture material that is not this region's.
  it("refuses when padding would overlap the next region", function()
    local plan, err = regions.plan_pack(
      snapshot({ regions = { region("A", 0, 5, 1), region("B", 5.5, 9, 2) } }),
      { "A", "B" }, grid)

    assert.is_nil(plan)
    assert.are.same({ reason = "region_overlap", region = "A", next_region = "B", ends = 6, next_starts = 5.5 }, err)
  end)

  it("refuses when regions already overlap before any padding", function()
    local plan, err = regions.plan_pack(
      snapshot({ regions = { region("A", 0, 8, 1), region("B", 4, 10, 2) } }),
      { "A", "B" }, grid)

    assert.is_nil(plan)
    assert.is_truthy(err)
  end)
end)

describe("regions.plan_pack placement", function()
  it("lays the first region down at the start of the timeline", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("Intro", 10, 16, 1) } }), { "Intro" }, grid))

    assert.are.equal(0, plan.places[1].to_start)
    assert.are.equal(-10, plan.places[1].delta)
  end)

  it("packs regions end to end in Arrangement order, leaving no gaps", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1), region("B", 30, 34, 2), region("C", 50, 58, 3) },
      }),
      { "C", "A", "B" }, grid))

    assert.are.equal("C", plan.places[1].name)
    assert.are.equal(0, plan.places[1].to_start)
    assert.are.equal("A", plan.places[2].name)
    assert.are.equal(8, plan.places[2].to_start)
    assert.are.equal("B", plan.places[3].name)
    assert.are.equal(14, plan.places[3].to_start)
    assert.are.equal(18, plan.packed_end)
  end)

  it("places using padded lengths, not original ones", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("A", 0, 5, 1), region("B", 20, 24, 2) } }),
      { "A", "B" }, grid))

    -- A is padded 5 -> 6, so B lands on the bar line at 6, not at 5.
    assert.are.equal(6, place_named(plan, "B").to_start)
  end)

  -- The plan describes mutations, so a region that is already where it belongs
  -- and needs no Padding contributes nothing to it. "A" is 3 whole bars here,
  -- deliberately: at 0..5 it would be padded to 6, and a pad is itself a
  -- mutation that has to be written (see the next spec).
  it("omits a region that neither moves nor pads", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("A", 0, 6, 1), region("B", 20, 24, 2) } }),
      { "A", "B" }, grid))

    assert.is_nil(place_named(plan, "A"))
    assert.are.equal(1, #plan.places)
  end)

  -- A region already at the cursor but not a whole number of bars: its start
  -- does not move, its end does. apply.places writes a region's bounds, so
  -- without a place entry the pad would be planned and logged but never
  -- written -- which is how Padding could have looked applied and not been.
  it("places a region that only needs padding, with a zero delta", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("A", 0, 5, 1), region("B", 20, 24, 2) } }),
      { "A", "B" }, grid))

    local place = place_named(plan, "A")
    assert.is_not_nil(place)
    assert.are.equal(0, place.delta)
    assert.are.equal(0, place.to_start)
    -- The padded end, not the original one: 5 -> 6.
    assert.are.equal(6, place.length)
    assert.are.equal(1, #plan.pads)
  end)

  -- A zero delta must stay indistinguishable from "did not move" everywhere
  -- else, or a pad-only place would start cutting items and dragging markers.
  it("does not cut, move markers or move items for a pad-only place", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 5, 1) },
        markers = { { name = "mark", number = 3, position = 1 } },
        items = { item(4.5, 3, 1) },
      }), { "A" }, grid))

    assert.are.equal(1, #plan.places)
    assert.are.same({}, plan.splits)
    assert.are.same({}, plan.marker_moves)
    assert.are.same({}, plan.item_moves)
  end)

  it("reports a region the Arrangement names but the project lacks", function()
    local plan, err = regions.plan_pack(
      snapshot({ regions = { region("A", 0, 6, 1) } }), { "A", "Ghost" }, grid)

    assert.is_nil(plan)
    assert.are.same({ reason = "region_missing", name = "Ghost" }, err)
  end)

  -- Repacking an already-packed project must be a no-op, not a rewrite.
  it("is empty when every region is already in place", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("A", 0, 6, 1), region("B", 6, 10, 2) } }),
      { "A", "B" }, grid))

    assert.are.same({}, plan.places)
    assert.is_true(plan.is_empty)
  end)
end)

describe("regions.plan_pack splitting", function()
  local function cut_at(plan, index)
    return plan.splits[index] and plan.splits[index].position
  end

  -- ADR-0002: a straddler of a moving region is cut on every track, with no
  -- exemption for an item covering a whole region.
  it("cuts at the end boundary of a moving region an item crosses", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) }, -- moves to 0
        items = { item(14, 5, 3) },           -- 14..19 crosses A's end at 16
      }), { "A" }, grid))

    assert.are.equal(1, #plan.splits)
    assert.are.same({ track_index = 3, track_name = nil, position = 16 }, plan.splits[1])
  end)

  -- Two regions can meet at times that differ by microseconds rather than
  -- exactly. Cutting at both asks REAPER for a piece 8 microseconds long --
  -- 0.39 samples at 48kHz -- which it cannot make. A real run aborted on this:
  -- "the cut on track 3 at 2759.357s did not take". The numbers below are the
  -- live project's, transcribed.
  it("emits one cut where two region bounds are microseconds apart", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = {
          region("What I Deserve", 2482.480929420, 2759.357260960, 3),
          region("God", 2759.357269029, 2996.778758743, 6),
        },
        -- Straddles both bounds, so both would be cut without the dedup.
        items = { item(2700, 120, 2) },
      }), { "What I Deserve", "God" }, unpadded))

    assert.are.equal(1, #plan.splits)
    -- The earlier of the pair, so the cut lands inside the earlier region and
    -- the piece after it is claimed by the later one.
    assert.are.equal(2759.357260960, cut_at(plan, 1))
  end)

  it("keeps the piece after such a cut, in the later region", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = {
          region("What I Deserve", 2482.480929420, 2759.357260960, 3),
          region("God", 2759.357269029, 2996.778758743, 6),
        },
        items = { item(2700, 120, 2) },
      }), { "What I Deserve", "God" }, unpadded))

    -- Neither piece is discarded: the first belongs to "What I Deserve", the
    -- second to "God" despite starting 8.07e-06s before its start.
    assert.are.same({}, plan.drops)
    assert.are.equal(2, #plan.item_moves)
  end)

  it("still cuts at two boundaries that are genuinely apart", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1), region("B", 16.5, 20, 2) },
        items = { item(12, 6, 3) }, -- 12..18 crosses A's end and B's start
      }), { "A", "B" }, unpadded))

    assert.are.equal(2, #plan.splits)
    assert.are.equal(16, cut_at(plan, 1))
    assert.are.equal(16.5, cut_at(plan, 2))
  end)

  -- The amendment to ADR-0002: a region that stays put carries its contents
  -- by not moving them, so cutting its straddlers edits audio for no benefit.
  it("does not cut at the bounds of a region that stays put", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1) }, -- already at the pack origin
        items = { item(4, 5) },             -- 4..9 crosses A's end at 6
      }), { "A" }, grid))

    assert.are.same({}, plan.splits)
    assert.are.same({}, plan.item_moves)
  end)

  it("cuts an item spanning a whole moving region into three", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        items = { item(8, 12) }, -- 8..20, covers A entirely
      }), { "A" }, grid))

    assert.are.equal(2, #plan.splits)
    assert.are.equal(10, cut_at(plan, 1))
    assert.are.equal(16, cut_at(plan, 2))
  end)

  it("cuts at the padded end, not the original end", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 15, 1) }, -- padded out to 16 by the grid
        items = { item(14, 8) },              -- crosses the padded end at 16
      }), { "A" }, grid))

    assert.are.equal(16, cut_at(plan, 1))
  end)

  it("leaves an item wholly inside a moving region uncut", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("A", 10, 16, 1) }, items = { item(11, 2) } }), { "A" }, grid))

    assert.are.same({}, plan.splits)
  end)

  it("leaves an item wholly outside every region uncut", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("A", 10, 16, 1) }, items = { item(0, 2) } }), { "A" }, grid))

    assert.are.same({}, plan.splits)
  end)

  -- An item merely touching a boundary is not straddling it, and cutting
  -- there would leave a zero-length piece.
  it("does not cut an item that ends exactly on a boundary", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("A", 10, 16, 1) }, items = { item(10, 6) } }), { "A" }, grid))

    assert.are.same({}, plan.splits)
  end)

  -- Identity is (track, position): the applier cuts every item on the track
  -- spanning that time, so one entry describes the cut exactly once even
  -- when two items on that track overlap and both cross it.
  it("records one cut per track and position, however many items cross it", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        items = { item(14, 5, 1), item(15, 4, 1), item(14, 5, 2) },
      }), { "A" }, grid))

    assert.are.equal(2, #plan.splits)
    assert.are.same({ 1, 2 }, { plan.splits[1].track_index, plan.splits[2].track_index })
  end)

  it("orders cuts by track, then by position", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 20, 26, 1), region("B", 4, 10, 2) },
        items = { item(0, 30, 7), item(0, 30, 2) },
      }), { "A", "B" }, grid))

    local seen = {}
    for _, split in ipairs(plan.splits) do
      seen[#seen + 1] = { split.track_index, split.position }
    end
    assert.are.same({
      { 2, 4 }, { 2, 10 }, { 2, 20 }, { 2, 26 },
      { 7, 4 }, { 7, 10 }, { 7, 20 }, { 7, 26 },
    }, seen)
  end)

  -- The point of cutting: the piece inside the region travels with it, and
  -- the tail left touching no region is dropped (CONTEXT.md).
  it("moves the piece inside the region and drops the tail", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) }, -- moves to 0, delta -10
        items = { item(14, 5, 3) },           -- 14..19
      }), { "A" }, grid))

    assert.are.equal(1, #plan.item_moves)
    assert.are.same(
      { track_index = 3, from = 14, to = 4, length = 2, delta = -10 }, plan.item_moves[1])

    assert.are.equal(1, #plan.drops)
    assert.are.same(
      { track_index = 3, track_name = nil, position = 16, length = 3 }, plan.drops[1])
    assert.are.same({}, plan.parks)
  end)

  it("carries the middle piece of an item that spans a whole moving region", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        items = { item(8, 12, 3) }, -- 8..20
      }), { "A" }, grid))

    assert.are.equal(1, #plan.item_moves)
    assert.are.same(
      { track_index = 3, from = 10, to = 0, length = 6, delta = -10 }, plan.item_moves[1])
    assert.are.equal(2, #plan.drops) -- 8..10 and 16..20
  end)

  -- A cut can hand a piece straight to the next region rather than to the
  -- Parked Material, when the two regions are back to back -- which is the
  -- shape "Dear Youth"/"Maze" has in the live project.
  it("carries a piece that lands inside the following region, with that region", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 2), region("B", 16, 22, 3) },
        items = { item(14, 4, 3) }, -- 14..18, crosses A's end into B
      }), { "B", "A" }, grid)) -- swapped: B to 0, A to 6

    assert.are.equal(2, #plan.item_moves)
    local by_from = {}
    for _, move in ipairs(plan.item_moves) do
      by_from[move.from] = move
    end
    assert.are.equal(10, by_from[14].to) -- with A: 10..16 -> 6..12
    assert.are.equal(0, by_from[16].to)  -- with B: 16..22 -> 0..6
    assert.are.same({}, plan.parks)
  end)
end)

describe("regions.plan_pack parking", function()
  -- Parked Material moves by a single shared offset that leaves its internal
  -- timing intact (CONTEXT.md).
  it("moves regions the Arrangement omits beyond the Packed Block", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("Out", 20, 26, 2) },
      }), { "A" }, grid))

    assert.are.equal(1, #plan.parks)
    assert.are.equal("region", plan.parks[1].kind)
    assert.are.equal("Out", plan.parks[1].name)
  end)

  -- Loose Items are dropped, not parked (CONTEXT.md, Dropped Material). A
  -- Repack runs on a cleaned-up project, so material touching no region is
  -- spent; only material that still belongs to a region is carried.
  it("drops Loose Items, which lie outside every region", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        items = { item(0, 2) }, -- a count-in before the first region
      }), { "A" }, grid))

    assert.are.same({}, plan.parks)
    assert.are.equal(1, #plan.drops)
    assert.are.equal(0, plan.drops[1].position)
  end)

  -- The dividing line is "touches a region", not "is inside a placed one":
  -- an item in an omitted region still belongs to that region and rides
  -- along with it.
  it("parks an item inside an omitted region rather than dropping it", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("Out", 20, 26, 2) },
        items = { item(22, 2) },
      }), { "A" }, grid))

    assert.are.same({}, plan.drops)
    local kinds = {}
    for _, park in ipairs(plan.parks) do
      kinds[park.kind] = true
    end
    assert.is_true(kinds.item)
    assert.is_true(kinds.region)
  end)

  it("keeps an item merely overlapping a region's edge, rather than dropping it", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("Out", 20, 26, 2) },
        items = { item(18, 4) }, -- 18..22, reaches into the omitted region
      }), { "A" }, grid))

    assert.are.same({}, plan.drops)
  end)

  it("shifts everything parked by one shared offset", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("X", 20, 26, 2), region("Y", 30, 36, 3) },
        items = { item(40, 2) },
      }), { "A" }, grid))

    for _, park in ipairs(plan.parks) do
      assert.are.equal(plan.park_delta, park.delta)
    end
  end)

  it("keeps the relative timing of parked material intact", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("X", 20, 26, 2), region("Y", 30, 36, 3) },
      }), { "A" }, grid))

    local by_name = {}
    for _, park in ipairs(plan.parks) do
      by_name[park.name] = park.from + park.delta
    end
    assert.are.equal(10, by_name["Y"] - by_name["X"])
  end)

  -- Parked material already clear of the Packed Block is left where it is,
  -- rather than being dragged backwards towards it.
  it("does not pull parked material earlier", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("Far", 500, 506, 2) },
      }), { "A" }, grid))

    assert.are.equal(0, plan.park_delta)
    assert.are.same({}, plan.parks)
  end)

  -- The applier routes on `kind` and writes `to` directly rather than adding
  -- the offset itself (lib/apply.lua's split_parks), so every entry has to
  -- carry its own destination -- not just the offset that produced it.
  it("gives every parked entry its destination, not only the offset", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("Out", 20, 26, 2) },
        items = { item(22, 2) },
        markers = { { name = "cue", number = 5, position = 21 } },
      }), { "A" }, grid))

    assert.is_true(#plan.parks > 0)
    for _, park in ipairs(plan.parks) do
      assert.are.equal(park.from + plan.park_delta, park.to)
    end
  end)

  -- A parked region is written with one SetProjectMarker4 carrying both
  -- bounds, so its length has to survive planning. It is never Padded --
  -- Padding keeps the Packed Block bar-aligned, and parked material is not in
  -- it -- so the length is the region's own, unchanged.
  it("carries a parked region's length, so both bounds can be written", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("Out", 20, 26, 2) },
      }), { "A" }, grid))

    assert.are.equal(1, #plan.parks)
    assert.are.equal(6, plan.parks[1].length)
  end)

  it("parks nothing when the Arrangement names every region and no items are loose", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("B", 6, 10, 2) },
        items = { item(1, 2) },
      }), { "A", "B" }, grid))

    assert.are.same({}, plan.parks)
  end)
end)

describe("regions.plan_pack markers", function()
  it("carries a plain marker inside a region along with it", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        markers = { { name = "cue", number = 5, position = 12 } },
      }), { "A" }, grid))

    assert.are.equal(1, #plan.marker_moves)
    assert.are.equal("cue", plan.marker_moves[1].name)
    assert.are.equal(2, plan.marker_moves[1].to)
  end)

  it("parks a marker that lies outside every region", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        markers = { { name = "stray", number = 5, position = 8 } },
      }), { "A" }, grid))

    assert.are.same({}, plan.marker_moves)
    assert.are.equal(1, #plan.parks)
    assert.are.equal("marker", plan.parks[1].kind)
    assert.are.equal("stray", plan.parks[1].name)
  end)

  -- Every song in the real project carries a marker at the region start.
  it("moves a marker sharing a region's start position", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        markers = { { name = "A", number = 5, position = 10 } },
      }), { "A" }, grid))

    assert.are.equal(0, plan.marker_moves[1].to)
  end)
end)

describe("regions.plan_pack item moves", function()
  it("moves an item fully inside a moving region, by the region's delta", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        items = { item(12, 2, 3) }, -- 12..14, inside A(10..16); A moves by -10
      }), { "A" }, grid))

    assert.are.equal(1, #plan.item_moves)
    assert.are.same({ track_index = 3, from = 12, to = 2, length = 2, delta = -10 }, plan.item_moves[1])
    assert.are.same({}, plan.parks)
  end)

  it("does not move an item whose region does not move", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1) }, -- already at the pack origin
        items = { item(1, 2) },
      }), { "A" }, grid))

    assert.are.same({}, plan.item_moves)
  end)

  -- An item merely touching both of a region's edges is fully inside, not
  -- straddling (same rule split_times uses).
  it("moves an item that exactly fills a moving region", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        items = { item(10, 6) },
      }), { "A" }, grid))

    assert.are.equal(1, #plan.item_moves)
  end)

  -- Regression: real REAPER data is sloppier than IEEE noise, and at the old
  -- EPSILON of 1e-9 this project refused dozens of items as straddling. Every
  -- number below is transcribed from spec/fixtures/repack_basic/after.rpp --
  -- the item ends 2.35e-06s past the region, which is 0.11 samples at 48kHz
  -- and nothing anyone could split, hear or have placed on purpose.
  it("moves an item overhanging a region's end by microseconds, not refuses it", function()
    local plan, err = regions.plan_pack(
      snapshot({
        regions = { region("Sleep Tight", 436.03896372451351, 737.72120671516768, 13) },
        items = { item(487.62775112175132, 250.09345794392539, 29) },
      }), { "Sleep Tight" }, unpadded)

    assert.is_nil(err)
    assert.are.equal(1, #plan.item_moves)
    assert.are.equal(487.62775112175132 - 436.03896372451351, plan.item_moves[1].to)
    -- split_times must agree with the classifier, or the plan would describe
    -- a split at a boundary the same run says nothing crosses.
    assert.are.same({}, plan.splits)
    assert.are.same({}, plan.parks)
  end)

  -- The same tolerance on the other edge, and the reason `contains` widened
  -- with `fully_inside`: at 1e-9 this item failed region_holding, so it was
  -- not refused but silently parked as a Loose Item -- moved the wrong way,
  -- by the park offset, with nothing in the plan flagging it.
  it("carries an item starting microseconds before its region, not parks it", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("I'm gonna tell God everything", 2759.3572690293126, 2996.7787587426892, 6) },
        items = { item(2759.3572553550107, 100, 3) },
      }), { "I'm gonna tell God everything" }, unpadded))

    assert.are.equal(1, #plan.item_moves)
    assert.are.same({}, plan.parks)
  end)

  -- The tolerance is float-noise tolerance, not a policy change on what
  -- counts as straddling: an overhang an order of magnitude past it is a real
  -- Straddling Item, and gets cut rather than carried whole.
  it("cuts an item overhanging by more than the boundary tolerance", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        items = { item(14, 2.001) }, -- ends at 16.001, 1ms past A's end
      }), { "A" }, grid))

    assert.are.equal(1, #plan.splits)
    assert.are.equal(16, plan.splits[1].position)
    assert.are.equal(2, plan.item_moves[1].length)
  end)

  -- A straddler of a region that never moves is left whole -- the amendment
  -- to ADR-0002, and the reason `moving_boundaries` exists.
  it("does not cut a straddling item in a region that does not move", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1) },
        items = { item(4, 5) }, -- straddles A's end at 6, but A does not move
      }), { "A" }, grid))

    assert.are.same({}, plan.item_moves)
  end)

  -- project.lua's timebase_safe is the only guard against a confirmed
  -- REAPER hazard (research/reaper-scripting.md §4.1c): moving an item under
  -- full beat-attachment stretches its content.
  it("refuses to move a fully-inside item whose timebase is not confirmed safe", function()
    local plan, err = regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        items = { item(12, 2, 1, false) },
      }), { "A" }, grid)

    assert.is_nil(plan)
    assert.are.equal("items_unsafe", err.reason)
  end)

  it("moves a fully-inside item whose timebase is confirmed safe", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        items = { item(12, 2, 1, true) },
      }), { "A" }, grid))

    assert.are.equal(1, #plan.item_moves)
  end)

  -- Against the live project a refusal named "track 5" for an item on
  -- REAPER's track 6, and the tracks were searched one off for a whole round
  -- trip. track_index is 0-based because REAPER's enumeration is; its UI is
  -- not, and the message is read in the UI.
  it("names a refused item's track the way REAPER's UI numbers it, from 1", function()
    local _, err = regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        items = { item(12, 2, 5, false, "KickDrummer") },
      }), { "A" }, grid)

    assert.are.equal(5, err.items[1].track_index)
    assert.are.equal("KickDrummer", err.items[1].track_name)
  end)

  it("names a refused item's track by number alone when it has no name", function()
    local _, err = regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        items = { item(12, 2, 5, false, "") },
      }), { "A" }, grid)

    assert.are.equal(5, err.items[1].track_index)
  end)

  it("reports every unsafe item together, not just the first", function()
    local plan, err = regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        items = { item(11, 2, 1, false), item(13, 2, 2, false) },
      }), { "A" }, grid)

    assert.is_nil(plan)
    assert.are.equal(2, #err.items)
  end)

  -- Cutting a straddler does not make it safe to reposition: the piece that
  -- has to travel is still on a timebase that would stretch it (§4.1c).
  it("still refuses a cut piece whose timebase is not confirmed safe", function()
    local plan, err = regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        items = { item(14, 5, 1, false) }, -- 14..19, crosses A's end
      }), { "A" }, grid)

    assert.is_nil(plan)
    assert.are.equal("items_unsafe", err.reason)
  end)

  -- Mirrors how a marker inside an omitted region is parked, not dropped
  -- (region_holding only recognises in_arrangement regions) -- an item's
  -- host region existing but being omitted from the Arrangement must not
  -- fall through every category silently.
  it("parks an item inside a region the Arrangement omits, like its region", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 0, 6, 1), region("Out", 20, 26, 2) },
        items = { item(22, 2) }, -- inside "Out", which is omitted
      }), { "A" }, grid))

    local kinds = {}
    for _, park in ipairs(plan.parks) do
      kinds[park.kind] = (kinds[park.kind] or 0) + 1
    end
    assert.are.equal(1, kinds.region)
    assert.are.equal(1, kinds.item)
    assert.are.same({}, plan.item_moves)
  end)

  it("counts a non-empty item_moves towards is_empty", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("A", 10, 16, 1) },
        items = { item(12, 2) },
      }), { "A" }, grid))

    assert.is_false(plan.is_empty)
  end)
end)

-- Headroom: the per-region end adjustment an Arrangement carries (CONTEXT.md).
--
-- This is the primary seam for the whole feature -- the planner is a pure
-- function over plain tables with an injected oracle, so every case below is a
-- literal snapshot and a literal Arrangement. The grid is `bars_every(2)`: one
-- bar every 2 seconds, so half a bar is 1 second and the arithmetic checks by
-- hand.
describe("regions.plan_pack Headroom", function()
  local function arrangement(names, headroom)
    local list = {}
    for _, name in ipairs(names) do
      list[#list + 1] = name
    end
    list.headroom = headroom
    return list
  end

  local function headroom_named(plan, name)
    for _, entry in ipairs(plan.headroom) do
      if entry.name == name then
        return entry
      end
    end
    return nil
  end

  -- Adopting the feature has to cost nothing until it is asked for, so this
  -- pins the zero case against the plan the same project produces with no
  -- Headroom table at all.
  it("a Headroom of zero produces exactly today's plan", function()
    local snap = snapshot({ regions = { region("Intro", 0, 4, 1), region("Maze", 4, 8, 2) } })

    local without = assert(regions.plan_pack(snap, { "Intro", "Maze" }, grid))
    local with_zero = assert(regions.plan_pack(
      snap, arrangement({ "Intro", "Maze" }, { Intro = 0, Maze = 0 }), grid))

    assert.are.same(without.places, with_zero.places)
    assert.are.same({}, with_zero.headroom)
    assert.is_true(with_zero.is_empty)
  end)

  it("grows a region's end to the nearest bar line", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("Intro", 0, 4, 1), region("Maze", 4, 8, 2) } }),
      arrangement({ "Intro", "Maze" }, { Intro = 4 }), grid))

    local entry = assert(headroom_named(plan, "Intro"))
    assert.are.equal(4, entry.requested)
    assert.are.equal(4, entry.resolved)
    assert.are.equal(2, entry.bars)
    assert.are.equal(4, entry.from_end)
    assert.are.equal(8, entry.to_end)
  end)

  -- The user typed seconds; the grid decides what that is worth. `+5` on a
  -- 2-second bar is two and a half bars, and the nearest line is at three.
  it("rounds a request that is not a whole number of bars", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("Intro", 0, 4, 1) } }),
      arrangement({ "Intro" }, { Intro = 5 }), grid))

    local entry = assert(headroom_named(plan, "Intro"))
    assert.are.equal(6, entry.resolved)
    assert.are.equal(3, entry.bars)
  end)

  -- The most likely "nothing happened" report there is, which is why the entry
  -- is still reported rather than the region being dropped from the list.
  it("resolves a request under half a bar to no change, and still reports it", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("Intro", 0, 4, 1) } }),
      arrangement({ "Intro" }, { Intro = 0.5 }), grid))

    local entry = assert(headroom_named(plan, "Intro"))
    assert.are.equal(0.5, entry.requested)
    assert.are.equal(0, entry.resolved)
    assert.are.equal(0, entry.bars)
    assert.is_true(plan.is_empty)
  end)

  it("shrinks a region's end by whole bars", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("Intro", 0, 8, 1) },
        items = { item(0, 2) },
      }),
      arrangement({ "Intro" }, { Intro = -4 }), grid))

    local entry = assert(headroom_named(plan, "Intro"))
    assert.are.equal(-4, entry.resolved)
    assert.are.equal(-2, entry.bars)
    assert.are.equal(4, place_named(plan, "Intro").length)
  end)

  -- Growth happens in the Packed Block only: `bounds` -- and so every
  -- membership question -- stays on the region's original geometry. The
  -- following region is then laid against the *grown* end, with no gap.
  it("grows only in the packed timeline, and packs the next region against it", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("Intro", 0, 4, 1), region("Maze", 4, 8, 2) } }),
      arrangement({ "Intro", "Maze" }, { Intro = 4 }), grid))

    assert.are.equal(0, place_named(plan, "Intro").to_start)
    assert.are.equal(8, place_named(plan, "Intro").length)
    assert.are.equal(8, place_named(plan, "Maze").to_start)
    assert.are.equal(12, plan.packed_end)
  end)

  -- The reason the growth is confined to the Packed Block. Both regions are
  -- back to back here, which is what `pad_regions`' overlap refusal exists to
  -- catch -- it must not fire on a Headroom.
  it("grows a region whose neighbour starts immediately after it", function()
    local plan = regions.plan_pack(
      snapshot({ regions = { region("Intro", 0, 4, 1), region("Maze", 4, 8, 2) } }),
      arrangement({ "Intro", "Maze" }, { Intro = 8 }), grid)

    assert.is_truthy(plan)
  end)

  it("does not capture the following region's material into a grown region", function()
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("Intro", 0, 4, 1), region("Maze", 4, 8, 2) },
        items = { item(5, 1) },
      }),
      arrangement({ "Intro", "Maze" }, { Intro = 4 }), grid))

    -- The item belongs to Maze, so it travels by Maze's delta (4 -> 8), not by
    -- Intro's (which is zero).
    assert.are.equal(1, #plan.item_moves)
    assert.are.equal(5, plan.item_moves[1].from)
    assert.are.equal(9, plan.item_moves[1].to)
  end)

  -- The floor covers the last of *anything* in the region, one kind per case,
  -- because each was a separate way for material to end up past a shrunk end
  -- and inside whatever the Repack puts next.
  local content_kinds = {
    { "an item", { items = { item(0, 5) } } },
    { "a plain marker", { markers = { { name = "cue", number = 3, position = 5 } } } },
    { "an envelope point", { envelope_points = { envelope_point(5) } } },
    { "a tempo marker", { tempo_markers = { { position = 5, bpm = 120,
      timesig_num = 4, timesig_denom = 4 } } } },
  }

  for _, case in ipairs(content_kinds) do
    local label, contents = case[1], case[2]

    it(("refuses a shrink that would leave %s past the region's end"):format(label), function()
      local overrides = { regions = { region("Intro", 0, 8, 1) } }
      for key, value in pairs(contents) do
        overrides[key] = value
      end

      local plan, err = regions.plan_pack(
        snapshot(overrides), arrangement({ "Intro" }, { Intro = -6 }), grid)

      assert.is_nil(plan)
      -- The content ends at 5, so the end may come back no further than the bar
      -- line at 6 -- a shrink of 2 seconds.
      assert.are.equal("headroom", err.reason)
      assert.are.equal("Intro", err.problems[1].name)
      assert.are.equal("shrink_too_far", err.problems[1].kind)
      assert.are.equal(2, err.problems[1].most)
    end)

    it(("allows a shrink that stops at the bar line after %s"):format(label), function()
      local overrides = { regions = { region("Intro", 0, 8, 1) } }
      for key, value in pairs(contents) do
        overrides[key] = value
      end

      local plan = assert(regions.plan_pack(
        snapshot(overrides), arrangement({ "Intro" }, { Intro = -2 }), grid))

      assert.are.equal(-2, headroom_named(plan, "Intro").resolved)
    end)
  end

  -- A region whose audio runs right to its end cannot shrink at all: the piece
  -- inside it is cut at the bound, so the floor is the bound.
  it("refuses any shrink on a region whose content runs to its end", function()
    local plan, err = regions.plan_pack(
      snapshot({
        regions = { region("Intro", 0, 8, 1) },
        items = { item(0, 8) },
      }),
      arrangement({ "Intro" }, { Intro = -2 }), grid)

    assert.is_nil(plan)
    assert.are.equal(0, err.problems[1].most)
  end)

  -- Shrinking is not a way to remove a region. Dropping it from the Arrangement
  -- parks it, and that is the existing answer.
  it("never shrinks an empty region below one bar", function()
    local plan, err = regions.plan_pack(
      snapshot({ regions = { region("Break", 0, 8, 1) } }),
      arrangement({ "Break" }, { Break = -8 }), grid)

    assert.is_nil(plan)
    assert.are.equal("Break", err.problems[1].name)
    assert.are.equal(6, err.problems[1].most)
  end)

  it("shrinks an empty region down to exactly one bar", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("Break", 0, 8, 1) } }),
      arrangement({ "Break" }, { Break = -6 }), grid))

    assert.are.equal(2, place_named(plan, "Break").length)
  end)

  -- One check is one round trip: the user fixes every number in a single edit.
  it("names every offending region in one refusal", function()
    local plan, err = regions.plan_pack(
      snapshot({
        regions = { region("Intro", 0, 8, 1), region("Maze", 8, 16, 2) },
        items = { item(0, 5), item(8, 5) },
      }),
      arrangement({ "Intro", "Maze" }, { Intro = -6, Maze = -6 }), grid)

    assert.is_nil(plan)
    assert.are.equal("Intro", err.problems[1].name)
    assert.are.equal("Maze", err.problems[2].name)
  end)

  -- A Headroom is added on top of Padding, not instead of it: `0` has to mean
  -- "whatever Padding does", which is only true if the adjustment is measured
  -- from the padded end.
  it("measures a Headroom from the padded end, not the raw one", function()
    local plan = assert(regions.plan_pack(
      snapshot({ regions = { region("Intro", 0, 5, 1) } }),
      arrangement({ "Intro" }, { Intro = 2 }), grid))

    -- Padding takes 5 to 6; the Headroom then takes 6 to 8.
    assert.are.equal(6, plan.pads[1].to_end)
    assert.are.equal(6, headroom_named(plan, "Intro").from_end)
    assert.are.equal(8, headroom_named(plan, "Intro").to_end)
    assert.are.equal(8, place_named(plan, "Intro").length)
  end)

  -- A typo of a few orders of magnitude would otherwise sit in the bar-counting
  -- walk inside an undo block, with no message.
  it("refuses a Headroom absurdly far from where the region ends", function()
    local plan, err = regions.plan_pack(
      snapshot({ regions = { region("Intro", 0, 4, 1) } }),
      arrangement({ "Intro" }, { Intro = 1e9 }), grid)

    assert.is_nil(plan)
    assert.are.equal("too_large", err.problems[1].kind)
  end)

  -- An Automation Anchor at a region end sits on the bound the region will
  -- actually have, so it has to travel with the Headroom.
  it("puts the end Automation Anchor on the adjusted end", function()
    local automation = { value_at = function() return 0.25 end }
    local plan = assert(regions.plan_pack(
      snapshot({
        regions = { region("Intro", 0, 4, 1) },
        envelope_points = { envelope_point(1) },
      }),
      arrangement({ "Intro" }, { Intro = 4 }), grid, automation))

    local ends = {}
    for _, anchor in ipairs(plan.envelope_anchors) do
      if anchor.edge == "end" then
        ends[#ends + 1] = anchor.to
      end
    end
    assert.are.same({ 8 }, ends)
  end)
end)

describe("regions.plan_pack Headroom clamping", function()
  -- The oracle is asked about bar lines at times REAPER's tempo map may not
  -- define, so the request is clamped before it ever reaches one.
  it("never asks the oracle about a time before the region start", function()
    local asked = {}
    local watched = {
      next_bar_at_or_after = function(time)
        asked[#asked + 1] = time
        return grid.next_bar_at_or_after(time)
      end,
      bar_at_or_before = function(time)
        asked[#asked + 1] = time
        return grid.bar_at_or_before(time)
      end,
      bar_after = function(time)
        asked[#asked + 1] = time
        return grid.bar_after(time)
      end,
      tempo_at = grid.tempo_at,
    }

    local list = { "Intro" }
    list.headroom = { Intro = -1000 }
    local plan = regions.plan_pack(
      snapshot({ regions = { region("Intro", 4, 12, 1) } }), list, watched)

    assert.is_nil(plan)
    for _, time in ipairs(asked) do
      assert.is_true(time >= 4, ("oracle asked about %.3f, before the region start"):format(time))
    end
  end)
end)
