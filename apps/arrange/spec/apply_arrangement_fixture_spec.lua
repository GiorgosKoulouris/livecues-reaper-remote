-- End-to-end coverage of LCRR_Arrange_Apply's pipeline (issue #5), against
-- the real region/marker positions in spec/fixtures/repack_basic/before.rpp
-- and the real, committed before.arrangements.lua sidecar -- not synthetic
-- data. REAPER itself cannot run here (ADR-0001), so this is the closest
-- thing to an end-to-end check available: real fixture data through the real
-- planner and applier, verified by recording the call sequence a real run
-- would make (ADR-0005 calls this a complement to, not a replacement for, a
-- human verifying the actual golden .rpp diff).
--
-- The region positions below were extracted once from before.rpp's MARKER
-- lines (paired by index, region bit at flags & 1, exactly as
-- lib/project.lua reads them) and are transcribed literally rather than
-- parsed here, so this spec does not need or become a general .RPP parser
-- (that is ADR-0005's concern, not this one's).
--
-- The fixture's regions have real gaps between them -- it is a live-set
-- recording, not a pre-packed timeline -- so applying even this two-swap
-- Arrangement legitimately repositions every region: Repack's job is to
-- close those gaps (CONTEXT.md), not just to honour the two transpositions.
-- What this spec checks is that the two named swaps land in the right
-- relative order, and that the pipeline (sidecar -> plan_pack -> apply)
-- wires together correctly against real data.

local sidecar = require("lib.sidecar")
local regions = require("lib.regions")
local apply = require("lib.apply")
local fake_reaper = require("spec.support.fake_reaper")

local function region(name, number, start_time, end_time)
  return { name = name, number = number, start_time = start_time, end_time = end_time }
end

local function marker(name, number, position)
  return { name = name, number = number, position = position }
end

-- Transcribed from spec/fixtures/repack_basic/before.rpp, in timeline order.
local FIXTURE_REGIONS = {
  region("Sleep Tight", 13, 436.03896, 737.72121),
  region("Darkness of Blue", 14, 800.52496, 1117.66782),
  region("NES_15", 15, 1337.48090, 1551.98088),
  region("Intro", 1, 2206.88092, 2276.48093),
  region("Sundown", 2, 2276.48093, 2482.48093),
  region("What I Deserve", 3, 2482.48093, 2759.35726),
  region("I'm gonna tell God everything", 6, 2759.35727, 2996.77876),
  region("Payback", 10, 2996.77876, 3147.43528),
  region("Prophets", 11, 3147.43528, 3371.59030),
  region("Low Fall", 5, 3771.16506, 4005.19861),
  region("NES 16", 16, 4390.69862, 4571.69862),
  region("SoFarGone", 9, 5094.57922, 5353.86493),
  region("The pain you leave behind", 4, 5353.86493, 5619.16377),
  region("The distance that happens", 12, 6192.29809, 6446.41574),
  region("Dear Youth", 8, 6675.66947, 6893.23956),
  region("Maze", 7, 6893.23956, 7113.47486),
  region("NES_19", 17, 7271.08680, 7482.85151),
  region("NES_11", 18, 7722.85151, 7979.47666),
  region("NES_22", 19, 8195.46689, 8375.46689),
}

-- Every plain marker in the fixture that coincides with a region start.
local FIXTURE_MARKERS = {
  marker("Sleep Tight", 9, 436.03896),
  marker("Darkness of Blue", 10, 800.52496),
  marker("Sundown", 1, 2276.48093),
  marker("What I Deserve", 2, 2482.48093),
  marker("I'm gonna tell God everything", 5, 2759.35727),
  marker("Payback", 7, 2996.77876),
  marker("Prophets", 8, 3147.43528),
  marker("Low Fall", 4, 3771.16506),
  marker("SoFarGone", 6, 5094.57922),
  marker("The pain you leave behind", 3, 5353.86493),
}

-- Treat every position as already on a bar line, so this spec never Pads.
--
-- **Deliberately not the real oracle, which now exists** (`lib/tempo_oracle.lua`,
-- ADR-0006): it needs REAPER, and this spec's whole point is asserting against
-- positions transcribed from the live project rather than against a synthetic
-- grid. Padding on real data is covered by `spec/repack_bars_fixture_spec.lua`,
-- whose fixture was built to have a grid that can be worked out by hand.
local NO_PADDING_ORACLE = {
  next_bar_at_or_after = function(time) return time end,
}

-- The tempo markers around the six region starts issue #19 was filed about,
-- transcribed from before.rpp's TEMPOENVEX `PT` lines at full precision --
-- along with the marker in force before each, which is the value a Repack
-- wrongly wrote onto the region. Each pair is two independently authored
-- numbers for the same instant: the region starts a few microseconds before
-- its own tempo marker, so the tempo *at* the region start is the previous
-- region's. The region positions here are at full precision for the same
-- reason; the 5-decimal ones above cannot express a 2e-5s offset.
--
-- Every offset below is inside `regions.BOUNDARY_TOLERANCE` (1e-4), and so is
-- comfortably inside the applier's own tempo-marker lookup -- which is why a
-- wrong anchor *replaced* the real marker instead of landing beside it.
local FIXTURE_TEMPO = {
  { region = "Darkness of Blue", start_time = 800.52495786048348,
    marker = 800.524978399604, bpm = 112, before = 107 },
  { region = "NES_15", start_time = 1337.4808991970372,
    marker = 1337.480919654611, bpm = 160, before = 107 },
  { region = "I'm gonna tell God everything", start_time = 2759.3572690293126,
    marker = 2759.357271139384, bpm = 121, before = 156 },
  { region = "Prophets", start_time = 3147.4352754134065,
    marker = 3147.435284747749, bpm = 160, before = 121 },
  { region = "Low Fall", start_time = 3771.1650550977242,
    marker = 3771.165074740517, bpm = 156, before = 160 },
  { region = "NES 16", start_time = 4390.6986233883144,
    marker = 4390.698624238057, bpm = 134, before = 160 },
}

local function snapshot()
  return {
    project_path = [[X:\LiveSession.rpp]],
    regions = FIXTURE_REGIONS,
    markers = FIXTURE_MARKERS,
    items = {},
    tempo_markers = {},
  }
end

-- The same six regions as a snapshot of their own, with the real tempo
-- markers and an oracle that reproduces REAPER's disagreement: asked about a
-- time fractionally before a marker, it answers with the tempo still in force
-- there. Without that the defect cannot reproduce, because the oracle would
-- simply return the right answer and there would be nothing to narrow.
local function tempo_snapshot()
  local rgns, tempo_markers = {}, {}
  for index, entry in ipairs(FIXTURE_TEMPO) do
    rgns[index] = region(entry.region, index, entry.start_time, entry.start_time + 100)
    tempo_markers[index] = {
      position = entry.marker,
      bpm = entry.bpm,
      timesig_num = 4,
      timesig_denom = 4,
      lineartempo = false,
    }
  end
  return { project_path = [[X:\LiveSession.rpp]], regions = rgns, markers = {},
    items = {}, tempo_markers = tempo_markers }
end

local DISAGREEING_ORACLE = {
  next_bar_at_or_after = function(time) return time end,
  tempo_at = function(time)
    for _, entry in ipairs(FIXTURE_TEMPO) do
      if time < entry.marker then
        return entry.before, 4, 4
      end
    end
    return FIXTURE_TEMPO[#FIXTURE_TEMPO].bpm, 4, 4
  end,
}

local function load_orig_arrangement()
  local path = "spec/fixtures/repack_basic/before.arrangements.lua"
  local handle = assert(io.open(path, "r"), "fixture sidecar missing: " .. path)
  local source = handle:read("a")
  handle:close()

  local arrangements, err = sidecar.parse(source)
  assert(arrangements, err)
  return assert(arrangements.ORIG, "fixture sidecar has no 'ORIG' arrangement")
end

describe("LCRR_Arrange_Apply pipeline against the real repack_basic fixture", function()
  local orig = load_orig_arrangement()

  it("names every fixture region exactly once (a precondition, not a Repack result)", function()
    local names = {}
    for _, name in ipairs(orig) do
      assert.is_nil(names[name], ("%q named twice"):format(name))
      names[name] = true
    end
    for _, r in ipairs(FIXTURE_REGIONS) do
      assert.is_true(names[r.name], ("ORIG omits %q"):format(r.name))
    end
  end)

  it("plans only region moves and marker moves -- never a split, pad, tempo move or park", function()
    local plan = regions.plan_pack(snapshot(), orig, NO_PADDING_ORACLE)

    assert.are.same({}, plan.splits)
    assert.are.same({}, plan.pads)
    assert.are.same({}, plan.tempo_moves)
    assert.are.same({}, plan.parks)
  end)

  -- The two adjacent transpositions the sidecar was hand-edited to carry
  -- (HANDOFF.md): Sleep Tight <-> Darkness of Blue, and NES_19 <-> NES_11.
  -- Closing the fixture's real inter-region gaps moves every region here
  -- (Repack's job, not a bug -- see the file header), so the swap itself is
  -- checked by relative order, not by an isolated four-entry plan.
  it("places Darkness of Blue before Sleep Tight, reversing their timeline order", function()
    local plan = regions.plan_pack(snapshot(), orig, NO_PADDING_ORACLE)
    local to_start = {}
    for _, place in ipairs(plan.places) do
      to_start[place.name] = place.to_start
    end

    assert.is_true(to_start["Darkness of Blue"] < to_start["Sleep Tight"])
  end)

  it("places NES_11 before NES_19, reversing their timeline order", function()
    local plan = regions.plan_pack(snapshot(), orig, NO_PADDING_ORACLE)
    local to_start = {}
    for _, place in ipairs(plan.places) do
      to_start[place.name] = place.to_start
    end

    assert.is_true(to_start["NES_11"] < to_start["NES_19"])
  end)

  it("carries the plain marker at each moved region's start along with it", function()
    local plan = regions.plan_pack(snapshot(), orig, NO_PADDING_ORACLE)
    local place_delta, marker_delta = {}, {}
    for _, place in ipairs(plan.places) do
      place_delta[place.name] = place.delta
    end
    for _, move in ipairs(plan.marker_moves) do
      marker_delta[move.name] = move.delta
    end

    for _, m in ipairs(FIXTURE_MARKERS) do
      assert.are.equal(place_delta[m.name], marker_delta[m.name],
        ("marker %q should move by the same delta as its region"):format(m.name))
    end
  end)

  -- Issue #19, against the numbers that produced it. Six of the project's
  -- nineteen Tempo Anchors were written at the tempo in force *before* a
  -- marker sitting microseconds after the region start -- `NES_15` at 107
  -- against a real 160, which is #16's long-standing residual. The applier's
  -- lookup then matched that marker and overwrote it, so each region ran at
  -- its predecessor's tempo and its beat-attached click slid out of it.
  it("anchors each affected region at its own tempo, not its predecessor's", function()
    local plan = regions.plan_anchors(tempo_snapshot(), DISAGREEING_ORACLE)
    local bpm_at = {}
    for _, anchor in ipairs(plan.anchors) do
      bpm_at[anchor.region_name] = anchor.bpm
    end

    for _, entry in ipairs(FIXTURE_TEMPO) do
      assert.are.equal(entry.bpm, bpm_at[entry.region],
        ("%q should be anchored at its own tempo"):format(entry.region))
    end
  end)

  -- With the anchors correct the writes are tempo-neutral, so a Repack of this
  -- project leaves the tempo map exactly as it found it -- which is the whole
  -- claim, stated as the planner sees it.
  it("plans no tempo change at all across the six affected regions", function()
    local plan = regions.plan_anchors(tempo_snapshot(), DISAGREEING_ORACLE)

    assert.is_true(plan.is_noop)
    assert.are.equal(0, plan.changing)
  end)

  it("runs the whole plan through the applier as one SetProjectMarker4 call per move", function()
    local plan = regions.plan_pack(snapshot(), orig, NO_PADDING_ORACLE)
    local api = fake_reaper.new({ SetProjectMarker4 = true })

    apply.plan(api, plan)

    local calls = api.calls_to("SetProjectMarker4")
    assert.are.equal(#plan.places + #plan.marker_moves, #calls)

    -- Every region move (isrgn true) happens before any marker move (isrgn
    -- false) -- apply.plan's documented order.
    local saw_marker_move = false
    for _, call in ipairs(calls) do
      if call.args[3] == false then
        saw_marker_move = true
      elseif saw_marker_move then
        error("a region move was recorded after a marker move")
      end
    end
  end)
end)
