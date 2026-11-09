-- The golden-fixture spec for bar alignment (ADR-0005, ADR-0006, issue #4).
--
-- ADR-0006 says Padding cannot be trusted until a golden fixture pair exists,
-- because a wrong `TimeMap` wrapper and a wrong planner are indistinguishable
-- without one. This is the half that does not need REAPER: the real fixture's
-- geometry, through the real planner, against a prediction written by hand in
-- `spec/fixtures/repack_bars/expected_plan.lua`.
--
-- The other half is a human running the action on `repack_bars/before.rpp` and
-- diffing the saved result. Until that happens, what is proven here is that the
-- planner is self-consistent and matches the arithmetic in the fixture's
-- README -- not that REAPER agrees about where the bar lines are. That is
-- exactly the gap `LCRR_Arrange_ShowBarLines.lua` exists to close.
--
-- Geometry is transcribed rather than parsed, following
-- spec/apply_arrangement_fixture_spec.lua: a general `.RPP` parser is ADR-0005's
-- concern, not a spec's.

local regions = require("lib.regions")
local sidecar = require("lib.sidecar")
local report = require("lib.report")

local FIXTURE = "spec/fixtures/repack_bars/"

local function load_lua(path)
  local handle = assert(io.open(path, "r"), "fixture file missing: " .. path)
  local source = handle:read("a")
  handle:close()
  return source
end

local EXPECTED = assert(load(load_lua(FIXTURE .. "expected_plan.lua")))()
local ARRANGEMENTS = assert(sidecar.parse(load_lua(FIXTURE .. "before.arrangements.lua")))

-- The fixture's bar grid, from its three tempo markers. This is the one thing a
-- spec has to model rather than read, because REAPER is what computes it in
-- production (ADR-0006) -- so it is written as a search over accumulated bars,
-- the same shape as spec/tempo_oracle_spec.lua's fake, rather than as a formula
-- that could accidentally agree with a bug in the planner.
local function fixture_oracle()
  local lines, t = {}, 0
  while t < 32 - 1e-9 do
    lines[#lines + 1] = t
    t = t + 2
  end
  t = 32
  while t < 48 - 1e-9 do
    lines[#lines + 1] = t
    t = t + 8 / 3
  end
  t = 48
  while t <= 120 do
    lines[#lines + 1] = t
    t = t + 2
  end

  return {
    next_bar_at_or_after = function(time)
      for _, line in ipairs(lines) do
        if line - time > -regions.BOUNDARY_TOLERANCE then
          return line
        end
      end
      error("fixture grid does not reach " .. time)
    end,
    tempo_at = function(time)
      if time >= 48 - 1e-9 then
        return 90, 3, 4
      elseif time >= 32 - 1e-9 then
        return 90, 4, 4
      end
      return 120, 4, 4
    end,
  }
end

-- The envelope's own default, for the one anchor no point precedes. Marked
-- "oracle" in the expected plan so the spec cannot silently accept a real value
-- there.
local ORACLE_DEFAULT = 0.25
local automation = {
  value_at = function() return ORACLE_DEFAULT end,
}

-- Transcribed from spec/fixtures/repack_bars/before.rpp.
local function snapshot()
  return {
    project_path = FIXTURE .. "before.rpp",
    regions = {
      { name = "Alpha", number = 1, start_time = 0, end_time = 8 },
      { name = "Bravo", number = 2, start_time = 12, end_time = 21 },
      { name = "Charlie", number = 3, start_time = 32, end_time = 40 },
      { name = "Delta", number = 4, start_time = 48, end_time = 53 },
    },
    markers = {
      { name = "Alpha", number = 5, position = 0 },
      { name = "verse", number = 6, position = 34 },
    },
    items = {
      { position = 2, length = 2, track_index = 0, track_name = "Gtr", timebase_safe = true },
      { position = 11, length = 3, track_index = 0, track_name = "Gtr", timebase_safe = true },
      { position = 30, length = 12, track_index = 1, track_name = "Keys", timebase_safe = true },
      { position = 9, length = 1, track_index = 2, track_name = "Perc", timebase_safe = true },
      { position = 49, length = 2, track_index = 2, track_name = "Perc", timebase_safe = true },
    },
    -- What REAPER is expected to report for the three TEMPOENVEX points. The
    -- signature on the first two is the effective 4/4; only the third carries an
    -- explicit one in the file.
    tempo_markers = {
      { position = 0, bpm = 120, timesig_num = 4, timesig_denom = 4, lineartempo = false },
      { position = 32, bpm = 90, timesig_num = 4, timesig_denom = 4, lineartempo = false },
      { position = 48, bpm = 90, timesig_num = 3, timesig_denom = 4, lineartempo = false },
    },
    envelope_points = {
      { position = 1, track_index = 0, track_name = "Gtr", envelope_name = "Mute",
        value = 1, shape = 1, tension = 0, selected = false },
      { position = 3, track_index = 0, track_name = "Gtr", envelope_name = "Mute",
        value = 0, shape = 1, tension = 0, selected = false },
      { position = 9.5, track_index = 0, track_name = "Gtr", envelope_name = "Mute",
        value = 1, shape = 1, tension = 0, selected = false },
      { position = 33, track_index = 0, track_name = "Gtr", envelope_name = "Mute",
        value = 0, shape = 1, tension = 0, selected = false },
    },
  }
end

-- Compare only the fields the prediction names, so the expected plan stays
-- readable instead of restating every field of every entry.
local function assert_matches(expected, actual, label)
  assert.are.equal(#expected, #actual,
    ("%s: expected %d entr(ies), got %d"):format(label, #expected, #actual))
  for index, want in ipairs(expected) do
    local got = actual[index]
    for key, value in pairs(want) do
      if value == "oracle" then
        value = ORACLE_DEFAULT
      end
      if type(value) == "number" then
        assert.is_true(math.abs(got[key] - value) < 1e-9,
          ("%s[%d].%s: expected %s, got %s"):format(label, index, key, value, tostring(got[key])))
      else
        assert.are.equal(value, got[key],
          ("%s[%d].%s"):format(label, index, key))
      end
    end
  end
end

describe("repack_bars fixture, Reordered arrangement", function()
  local oracle = fixture_oracle()
  local arrangement = assert(ARRANGEMENTS.Reordered, "fixture sidecar has no 'Reordered' arrangement")

  local function plan()
    return assert(regions.plan_pack(snapshot(), arrangement, oracle, automation))
  end

  it("plans the Tempo Anchors the fixture predicts", function()
    local anchors = regions.plan_anchors(snapshot(), oracle)

    assert_matches(EXPECTED.anchors, anchors.anchors, "anchors")
    assert.are.equal(EXPECTED.anchors_changing, anchors.changing)
    -- Three of four anchors are redundant but one is not, so the run must take
    -- the two-phase path rather than the idempotent shortcut.
    assert.is_false(anchors.is_noop)
  end)

  it("pads exactly the regions that are not a whole number of bars", function()
    assert_matches(EXPECTED.pads, plan().pads, "pads")
  end)

  it("packs the regions contiguously from the timeline origin", function()
    assert_matches(EXPECTED.places, plan().places, "places")
  end)

  -- ADR-0006's load-bearing claim: placement needs no bar math, because a region
  -- that starts on a bar line and spans whole bars transplants rigidly. If that
  -- is wrong, a destination lands off the grid.
  --
  -- Checked against the *original* grid, which is a proxy: after the Repack each
  -- region's bar lines come from its own transplanted tempo slice, and only
  -- REAPER can confirm those. What this does catch is a cumulative sum that
  -- stopped being a whole number of bars -- the way the claim would actually
  -- fail. The real check is a human diffing after.rpp.
  it("lands every placed region on a bar line of the new timeline", function()
    for _, place in ipairs(plan().places) do
      local bar = oracle.next_bar_at_or_after(place.to_start)
      assert.is_true(math.abs(bar - place.to_start) < regions.BOUNDARY_TOLERANCE,
        ("%q lands at %.6f, which is not a bar line (nearest at or after: %.6f)")
          :format(place.name, place.to_start, bar))
    end
  end)

  it("leaves no gap between placed regions", function()
    local cursor = 0
    for _, place in ipairs(plan().places) do
      assert.is_true(math.abs(place.to_start - cursor) < 1e-9,
        ("%q starts at %.6f, expected %.6f"):format(place.name, place.to_start, cursor))
      cursor = cursor + place.length
    end
    assert.are.equal(EXPECTED.packed_end, cursor)
  end)

  it("cuts at the bounds of the moving regions its items straddle", function()
    assert_matches(EXPECTED.splits, plan().splits, "splits")
  end)

  it("discards exactly the material that touches no region", function()
    assert_matches(EXPECTED.drops, plan().drops, "drops")
  end)

  it("carries every item that is inside a placed region", function()
    assert_matches(EXPECTED.item_moves, plan().item_moves, "item_moves")
  end)

  it("carries the plain markers, including one that is not at a region start", function()
    assert_matches(EXPECTED.marker_moves, plan().marker_moves, "marker_moves")
  end)

  it("transplants each region's tempo slice", function()
    assert_matches(EXPECTED.tempo_moves, plan().tempo_moves, "tempo_moves")
  end)

  it("carries the envelope points inside placed regions", function()
    assert_matches(EXPECTED.envelope_moves, plan().envelope_moves, "envelope_moves")
  end)

  it("discards the envelope point lying in a gap", function()
    assert_matches(EXPECTED.envelope_drops, plan().envelope_drops, "envelope_drops")
  end)

  it("writes an Automation Anchor at both bounds of every placed region", function()
    assert_matches(EXPECTED.envelope_anchors, plan().envelope_anchors, "envelope_anchors")
  end)

  it("needs no parking, so the run is applicable end to end", function()
    assert.are.same(EXPECTED.parks, plan().parks)
  end)
end)

describe("repack_bars fixture, Identity arrangement", function()
  local oracle = fixture_oracle()
  local arrangement = assert(ARRANGEMENTS.Identity, "fixture sidecar has no 'Identity' arrangement")

  local function plan()
    return assert(regions.plan_pack(snapshot(), arrangement, oracle, automation))
  end

  -- The first thing to run against real REAPER: it isolates Padding and gap
  -- closing from reordering, so a bad result cannot be blamed on the order.
  it("still closes the gaps and pads, without reordering", function()
    assert_matches(EXPECTED.pads, plan().pads, "pads")

    local by_name = {}
    for _, place in ipairs(plan().places) do
      by_name[place.name] = place
    end

    -- Alpha alone keeps its position: it starts at the origin already and is a
    -- whole number of bars, so it is not placed at all.
    assert.is_nil(by_name.Alpha)
    assert.are.equal(8, by_name.Bravo.to_start)
    assert.are.equal(18, by_name.Charlie.to_start)
    assert.are.equal(26, by_name.Delta.to_start)
  end)

  it("lands every placed region on a bar line here too", function()
    for _, place in ipairs(plan().places) do
      local bar = oracle.next_bar_at_or_after(place.to_start)
      assert.is_true(math.abs(bar - place.to_start) < regions.BOUNDARY_TOLERANCE,
        ("%q lands at %.6f, which is not a bar line"):format(place.name, place.to_start))
    end
  end)
end)

-- Issue #7's half of the fixture. Everything asserted here was derived by hand
-- in expected_plan.lua before the planner was run against it, the same
-- discipline the Reordered block follows -- a prediction copied out of the
-- thing it predicts proves nothing.
describe("repack_bars fixture, Subset arrangement", function()
  local oracle = fixture_oracle()
  local arrangement = assert(ARRANGEMENTS.Subset, "fixture sidecar has no 'Subset' arrangement")
  local EXPECT = EXPECTED.subset

  local function plan()
    return assert(regions.plan_pack(snapshot(), arrangement, oracle, automation))
  end

  -- Phase 1 does not consult the Arrangement at all, so omitting Charlie must
  -- not cost Charlie its anchor. That anchor is what lets the parked region
  -- keep its own tempo instead of inheriting the Packed Block's.
  it("still anchors the region the Arrangement omits", function()
    local anchors = regions.plan_anchors(snapshot(), oracle)

    assert_matches(EXPECTED.anchors, anchors.anchors, "anchors")
    assert.are.equal(EXPECT.anchors_changing, anchors.changing)
  end)

  it("pads only the placed regions, leaving the omitted one its own length", function()
    assert_matches(EXPECT.pads, plan().pads, "pads")
  end)

  it("packs the placed regions contiguously from the origin", function()
    assert_matches(EXPECT.places, plan().places, "places")

    local cursor = 0
    for _, place in ipairs(plan().places) do
      -- Alpha is absent from places, so the cursor starts past it.
      cursor = math.max(cursor, place.to_start) + place.length
    end
    assert.are.equal(EXPECT.packed_end, cursor)
  end)

  -- Cuts happen at the bounds of *moving* regions. Charlie does not move, so
  -- the Keys item spanning it is not diced -- it parks whole. This is the one
  -- place the fixture proves that splitting follows placement rather than
  -- region membership.
  it("does not cut at an omitted region's bounds", function()
    assert_matches(EXPECT.splits, plan().splits, "splits")
  end)

  it("discards only what touches no region at all", function()
    assert_matches(EXPECT.drops, plan().drops, "drops")
  end)

  it("carries the items inside placed regions, and nothing from the omitted one", function()
    assert_matches(EXPECT.item_moves, plan().item_moves, "item_moves")
  end)

  it("carries no marker: one is inside a region that does not move, one parks", function()
    assert_matches(EXPECT.marker_moves, plan().marker_moves, "marker_moves")
  end)

  -- The homeless tempo marker is the one parked category applied this run, so
  -- it appears in tempo_moves rather than parks (ADR-0006's #4 amendment).
  it("parks the homeless tempo marker into tempo_moves, by the shared offset", function()
    assert_matches(EXPECT.tempo_moves, plan().tempo_moves, "tempo_moves")
  end)

  it("carries no envelope point, and drops only the one lying in a gap", function()
    assert_matches(EXPECT.envelope_moves, plan().envelope_moves, "envelope_moves")
    assert_matches(EXPECT.envelope_drops, plan().envelope_drops, "envelope_drops")
  end)

  -- Bravo's anchor value comes from a point this run drops, Delta's from a
  -- point this run parks. Anchors are evaluated before anything moves, so
  -- neither is lossy (ADR-0006).
  it("anchors placed regions from values whose source is dropped or parked", function()
    assert_matches(EXPECT.envelope_anchors, plan().envelope_anchors, "envelope_anchors")
  end)

  it("parks the omitted region and everything belonging to it", function()
    assert.are.equal(EXPECT.park_delta, plan().park_delta)
    assert_matches(EXPECT.parks, plan().parks, "parks")
  end)

  -- The offset is what makes parking reversible, so it has to be one number
  -- shared by every entry, and it has to clear the Packed Block by PARK_GAP.
  it("shifts everything parked by one offset that clears the Packed Block", function()
    local packed = plan()
    for _, park in ipairs(packed.parks) do
      assert.are.equal(packed.park_delta, park.delta)
      assert.is_true(park.to >= EXPECT.packed_end + regions.PARK_GAP - 1e-9,
        ("%s at %.3f parks to %.3f, inside the gap"):format(park.kind, park.from, park.to))
    end
  end)
end)

-- The second run, planned against the saved result of the first (issue #13).
--
-- HANDOFF's headline verification rule is "run it twice, always": four of this
-- work's bugs produced correct output on a first run and appeared only when
-- the same Arrangement was applied to the operation's own output. Until now
-- that rule had no automated expression at all -- every fixture spec planned
-- against `before.rpp` only, and the second run was checked by hand in REAPER.
--
-- This closes that gap for the plan half. Real REAPER, running `Subset` twice
-- on 2026-08-05, reported "nothing to do" and wrote nothing the second time;
-- this asserts the planner agrees, from the geometry that run actually saved.
--
-- It guards issue #13 in particular. Giving `envelope_anchors` a `redundant`
-- flag so an anchors-only plan is no longer silently skipped is exactly the
-- change that could cost the no-op, because anchors are planned at every bound
-- on every run -- so the interesting case is not that some anchor is redundant
-- but that *all* of them are, on real saved data.
describe("repack_bars fixture, Subset applied twice", function()
  local arrangement = assert(ARRANGEMENTS.Subset, "fixture sidecar has no 'Subset' arrangement")

  -- The bar grid of the *packed* tempo map, which is not the fixture's
  -- original one: markers at 0 (120 4/4), 8 (120 4/4), 18 (90 3/4) and 326
  -- (90 4/4). The first three all give a 2 s bar -- 4 beats at 120, and 3
  -- beats at 90, are the same length -- so bar lines run every 2 s until 326
  -- and every 8/3 s after it.
  --
  -- Confirmed against real REAPER rather than only derived here:
  -- `LCRR_Arrange_ShowBarLines` on this saved project reported all four regions already
  -- on a bar line and "0 of 4 region(s) would be padded".
  local function packed_oracle()
    local lines, t = {}, 0
    while t < 326 - 1e-9 do
      lines[#lines + 1] = t
      t = t + 2
    end
    t = 326
    while t <= 400 do
      lines[#lines + 1] = t
      t = t + 8 / 3
    end

    local function bar_at_or_before(time)
      local found = lines[1]
      for _, line in ipairs(lines) do
        if line - time <= regions.BOUNDARY_TOLERANCE then
          found = line
        end
      end
      return found
    end

    return {
      next_bar_at_or_after = function(time)
        for _, line in ipairs(lines) do
          if line - time > -regions.BOUNDARY_TOLERANCE then
            return line
          end
        end
        error("packed grid does not reach " .. time)
      end,
      bar_at_or_before = bar_at_or_before,
      bar_after = function(time)
        local at = bar_at_or_before(time)
        for _, line in ipairs(lines) do
          if line - at > regions.BOUNDARY_TOLERANCE then
            return line
          end
        end
        error("packed grid does not reach past " .. time)
      end,
      tempo_at = function(time)
        if time >= 326 - 1e-9 then
          return 90, 4, 4
        elseif time >= 18 - 1e-9 then
          return 90, 3, 4
        end
        return 120, 4, 4
      end,
    }
  end

  -- Transcribed from spec/fixtures/repack_bars/after.rpp, the committed and
  -- REAPER-verified result of the first `Subset` run.
  local function packed_snapshot()
    local function mute(position, value)
      return { position = position, track_index = 0, track_name = "Gtr",
        envelope_name = "Mute", value = value, shape = 1, tension = 0, selected = false }
    end

    return {
      project_path = FIXTURE .. "after.rpp",
      regions = {
        { name = "Alpha", number = 1, start_time = 0, end_time = 8 },
        { name = "Bravo", number = 2, start_time = 8, end_time = 18 },
        { name = "Delta", number = 4, start_time = 18, end_time = 24 },
        { name = "Charlie", number = 3, start_time = 326, end_time = 334 },
      },
      markers = {
        { name = "Alpha", number = 5, position = 0 },
        { name = "verse", number = 6, position = 328 },
      },
      items = {
        { position = 2, length = 2, track_index = 0, track_name = "Gtr", timebase_safe = true },
        { position = 8, length = 2, track_index = 0, track_name = "Gtr", timebase_safe = true },
        { position = 324, length = 12, track_index = 1, track_name = "Keys", timebase_safe = true },
        { position = 19, length = 2, track_index = 2, track_name = "Perc", timebase_safe = true },
      },
      tempo_markers = {
        { position = 0, bpm = 120, timesig_num = 4, timesig_denom = 4, lineartempo = false },
        { position = 8, bpm = 120, timesig_num = 4, timesig_denom = 4, lineartempo = false },
        { position = 18, bpm = 90, timesig_num = 3, timesig_denom = 4, lineartempo = false },
        { position = 326, bpm = 90, timesig_num = 4, timesig_denom = 4, lineartempo = false },
      },
      -- The two pairs at 8 and 18 are the shared bounds' step pairs, written
      -- by the first run's anchors. Order is REAPER's own and load-bearing:
      -- where two points share a time the last one wins.
      envelope_points = {
        mute(0, 1), mute(1, 1), mute(3, 0),
        mute(8, 0), mute(8, 1),
        mute(18, 1), mute(18, 0),
        mute(24, 0),
        mute(327, 0),
      },
    }
  end

  local function plan()
    return assert(regions.plan_pack(
      packed_snapshot(), arrangement, packed_oracle(), automation))
  end

  it("plans no work at all, so the run creates no undo point", function()
    assert.is_true(plan().is_empty)
  end)

  it("still anchors every bound, and finds every one of them redundant", function()
    local packed = plan()

    assert.is_true(#packed.envelope_anchors > 0, "the second run must still plan anchors")
    assert.are.equal(0, packed.changing_envelope_anchors)
    for _, anchor in ipairs(packed.envelope_anchors) do
      assert.is_true(anchor.redundant,
        ("anchor %s %s@%.3f"):format(anchor.region_name, anchor.edge, anchor.to))
    end
  end)

  it("finds the Tempo Anchors redundant too, so phase 2 needs no write first", function()
    local anchors = regions.plan_anchors(packed_snapshot(), packed_oracle())

    assert.is_true(anchors.is_noop)
  end)

  -- Every other category, named individually rather than only through
  -- `is_empty`, so a failure says which one moved.
  it("moves, drops, pads, cuts and parks nothing", function()
    local packed = plan()

    assert.are.same({}, packed.splits, "splits")
    assert.are.same({}, packed.drops, "drops")
    assert.are.same({}, packed.pads, "pads")
    assert.are.same({}, packed.places, "places")
    assert.are.same({}, packed.tempo_moves, "tempo_moves")
    assert.are.same({}, packed.envelope_moves, "envelope_moves")
    assert.are.same({}, packed.envelope_drops, "envelope_drops")
    assert.are.same({}, packed.marker_moves, "marker_moves")
    assert.are.same({}, packed.item_moves, "item_moves")
    assert.are.same({}, packed.parks, "parks")
  end)

  -- `report.verify` asked of the same saved geometry (issue #21). This is the
  -- one place it meets real packed output rather than a timeline a spec
  -- invented, and it is a genuinely different question from everything above:
  -- those assert the *planner* has no work left, this asserts the *result*
  -- holds the properties a Repack promises, derived from the project alone.
  --
  -- The distinction is the whole reason `verify` exists. A planner that agreed
  -- with itself about a wrong packing would pass every assertion above and
  -- fail this one.
  it("satisfies report.verify: packed in order, contiguous, on the grid, Charlie parked", function()
    local result = report.verify({
      snapshot = packed_snapshot(),
      arrangement = arrangement,
      tempo = packed_oracle(),
    })

    assert.are.same({}, result.findings)
    assert.are.equal("pass", result.verdict)
  end)

  -- **Headroom is the one operation in this suite that is deliberately not
  -- idempotent, and this is where that is pinned by a test rather than by
  -- prose.** Everything above asserts the opposite property -- run `Subset`
  -- again and the planner has nothing left to do. `Headroom` is `Subset` with a
  -- `+4` on Bravo and nothing else different, so the two blocks differ in
  -- exactly the thing under test.
  --
  -- If a later change makes Headroom absolute -- "leave Bravo 14 seconds long"
  -- rather than "add 4 seconds to Bravo" -- the second assertion here fails and
  -- says so, instead of the behaviour drifting quietly into something the
  -- confirmation prompt no longer needs to exist for.
  describe("with a Headroom on Bravo", function()
    local with_headroom = assert(ARRANGEMENTS.Headroom,
      "fixture sidecar has no 'Headroom' arrangement")

    local function first()
      return assert(regions.plan_pack(
        packed_snapshot(), with_headroom, packed_oracle(), automation))
    end

    it("moves Bravo's end by two bars, and packs Delta against the new end", function()
      local packed = first()

      assert.are.equal(1, #packed.headroom)
      local entry = packed.headroom[1]
      assert.are.equal("Bravo", entry.name)
      assert.are.equal(4, entry.requested)
      assert.are.equal(4, entry.resolved)
      assert.are.equal(2, entry.bars)
      assert.are.equal(18, entry.from_end)
      assert.are.equal(22, entry.to_end)

      local by_name = {}
      for _, place in ipairs(packed.places) do
        by_name[place.name] = place
      end
      -- Bravo does not move -- its start is already at the cursor -- but it is
      -- still placed, because `apply.places` is what writes a region's bounds.
      assert.are.equal(0, by_name.Bravo.delta)
      assert.are.equal(14, by_name.Bravo.length)
      assert.are.equal(22, by_name.Delta.to_start)
      assert.is_false(packed.is_empty)
    end)

    -- The geometry the first run above produces, written out by hand.
    --
    -- **Not golden data, and deliberately partial.** Every other snapshot in
    -- this file is transcribed from a committed `.RPP` that REAPER itself
    -- wrote; this one cannot be, because REAPER is unreachable from here and
    -- `after.rpp` records the `Subset` run rather than this one. So it carries
    -- only what the claim under test needs -- the region bounds and the tempo
    -- map -- rather than inventing item and envelope positions that would read
    -- like verified output. Confirming the *rest* of a Headroom run needs a
    -- real run on the Windows side.
    local function after_first_run()
      return {
        project_path = FIXTURE .. "after.rpp",
        regions = {
          { name = "Alpha", number = 1, start_time = 0, end_time = 8 },
          { name = "Bravo", number = 2, start_time = 8, end_time = 22 },
          { name = "Delta", number = 4, start_time = 22, end_time = 28 },
          { name = "Charlie", number = 3, start_time = 328, end_time = 336 },
        },
        markers = {},
        items = {},
        tempo_markers = {
          { position = 0, bpm = 120, timesig_num = 4, timesig_denom = 4, lineartempo = false },
          { position = 8, bpm = 120, timesig_num = 4, timesig_denom = 4, lineartempo = false },
          { position = 22, bpm = 90, timesig_num = 3, timesig_denom = 4, lineartempo = false },
          { position = 328, bpm = 90, timesig_num = 4, timesig_denom = 4, lineartempo = false },
        },
        envelope_points = {},
      }
    end

    it("moves Bravo's end AGAIN when applied a second time", function()
      local second = assert(regions.plan_pack(
        after_first_run(), with_headroom, packed_oracle(), automation))

      assert.are.equal(1, #second.headroom)
      local entry = second.headroom[1]
      assert.are.equal("Bravo", entry.name)
      assert.are.equal(4, entry.resolved)
      -- The whole point: it starts from where the end now is, not from where it
      -- was before the first run.
      assert.are.equal(22, entry.from_end)
      assert.are.equal(26, entry.to_end)
      assert.is_false(second.is_empty)
    end)

    -- The same second application with the Headroom stripped -- what Apply's
    -- "repack only" answer does -- has nothing to do, which is what makes that
    -- answer a safe way out of the prompt.
    it("has nothing to do on a second run once the Headroom is dropped", function()
      local second = assert(regions.plan_pack(
        after_first_run(), report.without_headroom(with_headroom),
        packed_oracle(), automation))

      assert.are.same({}, second.headroom)
      assert.are.same({}, second.places)
    end)
  end)
end)
