local validate = require("lib.validate")
local planner = require("lib.regions")

local function region(name, number)
  return { name = name, number = number or 1, start_time = 0, end_time = 1 }
end

describe("validate.project_saved", function()
  it("accepts a project with a path", function()
    assert.is_true(validate.project_saved([[D:\P\Song.RPP]]))
  end)

  -- An unsaved project has nowhere to put a sidecar or a log (ADR-0003).
  it("rejects an unsaved project", function()
    local ok, err = validate.project_saved("")
    assert.is_false(ok)
    assert.is_truthy(err)
  end)

  it("rejects a nil path", function()
    local ok, err = validate.project_saved(nil)
    assert.is_false(ok)
    assert.is_truthy(err)
  end)
end)

describe("validate.region_names", function()
  it("accepts uniquely named regions", function()
    local ok, problems = validate.region_names({
      region("Intro", 1), region("Sundown", 2), region("Maze", 3),
    })
    assert.is_true(ok)
    assert.are.same({}, problems)
  end)

  it("accepts a project with no regions at all", function()
    local ok, problems = validate.region_names({})
    assert.is_true(ok)
    assert.are.same({}, problems)
  end)

  -- Names are the primary key, so a collision is fatal, not a warning.
  it("reports duplicated Region Names with every offending Region Number", function()
    local ok, problems = validate.region_names({
      region("Intro", 1), region("Maze", 2), region("Intro", 7),
    })
    assert.is_false(ok)
    assert.are.equal(1, #problems)
    assert.are.equal("duplicate", problems[1].code)
    assert.are.equal("Intro", problems[1].name)
    assert.are.same({ 1, 7 }, problems[1].numbers)
  end)

  it("reports a name duplicated three times once, not twice", function()
    local ok, problems = validate.region_names({
      region("A", 1), region("A", 2), region("A", 3),
    })
    assert.is_false(ok)
    assert.are.equal(1, #problems)
    assert.are.same({ 1, 2, 3 }, problems[1].numbers)
  end)

  -- Agreed extension of ADR-0003: an empty name is no key at all.
  it("reports an unnamed region", function()
    local ok, problems = validate.region_names({ region("Intro", 1), region("", 16) })
    assert.is_false(ok)
    assert.are.equal(1, #problems)
    assert.are.equal("empty", problems[1].code)
    assert.are.same({ 16 }, problems[1].numbers)
  end)

  -- Two unnamed regions are unaddressable, not "duplicates of each other".
  it("reports two unnamed regions as a single empty-name problem", function()
    local ok, problems = validate.region_names({ region("", 4), region("", 16) })
    assert.is_false(ok)
    assert.are.equal(1, #problems)
    assert.are.equal("empty", problems[1].code)
    assert.are.same({ 4, 16 }, problems[1].numbers)
  end)

  it("reports duplicates and empties together", function()
    local ok, problems = validate.region_names({
      region("Intro", 1), region("Intro", 2), region("", 3),
    })
    assert.is_false(ok)
    assert.are.equal(2, #problems)
  end)

  -- Whitespace is invisible in REAPER's ruler; "Intro " and "Intro" would look
  -- identical while keying differently, which is the bug ADR-0003 exists to stop.
  it("treats a name that is only whitespace as empty", function()
    local ok, problems = validate.region_names({ region("   ", 5) })
    assert.is_false(ok)
    assert.are.equal("empty", problems[1].code)
  end)

  it("orders problems deterministically by name", function()
    local _, problems = validate.region_names({
      region("Zebra", 1), region("Zebra", 2), region("Apple", 3), region("Apple", 4),
    })
    assert.are.equal("Apple", problems[1].name)
    assert.are.equal("Zebra", problems[2].name)
  end)
end)

describe("validate.arrangement_regions_exist", function()
  local regions = { region("Intro", 1), region("Sundown", 2), region("Maze", 3) }

  it("accepts an arrangement naming known regions", function()
    assert.is_true(validate.arrangement_regions_exist({ "Maze", "Intro" }, regions))
  end)

  -- An Arrangement may name a subset of the project's regions (CONTEXT.md).
  it("accepts a subset", function()
    assert.is_true(validate.arrangement_regions_exist({ "Intro" }, regions))
  end)

  it("accepts an empty arrangement", function()
    assert.is_true(validate.arrangement_regions_exist({}, regions))
  end)

  it("reports names with no matching region", function()
    local ok, missing = validate.arrangement_regions_exist({ "Intro", "Ghost", "Absent" }, regions)
    assert.is_false(ok)
    assert.are.same({ "Absent", "Ghost" }, missing)
  end)
end)

describe("validate.arrangement_is_exhaustive", function()
  local regions = { region("Intro", 1), region("Sundown", 2), region("Maze", 3) }

  it("accepts an arrangement naming every region", function()
    local ok, omitted = validate.arrangement_is_exhaustive({ "Maze", "Sundown", "Intro" }, regions)
    assert.is_true(ok)
    assert.are.same({}, omitted)
  end)

  it("accepts a project with no regions and an empty arrangement", function()
    assert.is_true(validate.arrangement_is_exhaustive({}, {}))
  end)

  -- Subsetting is not supported by this action yet -- parking is #7's job and
  -- its clamp is not ratified, so an omission is refused rather than parked.
  it("reports regions the arrangement omits, sorted", function()
    local ok, omitted = validate.arrangement_is_exhaustive({ "Maze" }, regions)
    assert.is_false(ok)
    assert.are.same({ "Intro", "Sundown" }, omitted)
  end)

  it("reports every region omitted by an empty arrangement", function()
    local ok, omitted = validate.arrangement_is_exhaustive({}, regions)
    assert.is_false(ok)
    assert.are.same({ "Intro", "Maze", "Sundown" }, omitted)
  end)
end)

describe("validate.arrangement_name_exists", function()
  local arrangements = { ORIG = { "Intro" }, Radio_Edit = { "Intro" } }

  it("accepts a name the sidecar has", function()
    local ok = validate.arrangement_name_exists("ORIG", arrangements)
    assert.is_true(ok)
  end)

  it("reports an unknown name, listing what does exist, sorted", function()
    local ok, available = validate.arrangement_name_exists("Ghost", arrangements)
    assert.is_false(ok)
    assert.are.same({ "ORIG", "Radio_Edit" }, available)
  end)

  it("reports every available name even for an empty sidecar", function()
    local ok, available = validate.arrangement_name_exists("Anything", {})
    assert.is_false(ok)
    assert.are.same({}, available)
  end)
end)

describe("validate.plan_is_region_move_only", function()
  local function empty_plan()
    return { splits = {}, pads = {}, tempo_moves = {}, parks = {} }
  end

  it("accepts a plan with only region moves", function()
    assert.is_true(validate.plan_is_region_move_only(empty_plan()))
  end)

  -- Splits stopped being a blocker when lib/apply.lua learned to cut: a plan
  -- carrying them is applicable, not refused.
  it("accepts a plan that needs splitting", function()
    local plan = empty_plan()
    plan.splits = { { track_index = 2, position = 4.5 } }
    assert.is_true(validate.plan_is_region_move_only(plan))
  end)

  -- Padding stopped being a blocker when the real tempo oracle landed (#4).
  -- Note it has no applier function of its own: a pad changes a region's end,
  -- and lib/regions.lua emits a place for any region whose either bound moved,
  -- so apply.places writes it.
  it("accepts a plan that needs Padding", function()
    local plan = empty_plan()
    plan.pads = { { name = "Intro" } }
    assert.is_true(validate.plan_is_region_move_only(plan))
  end)

  -- tempo_moves stopped being a blocker when lib/apply.lua learned to write
  -- it (issue #4's transplant): a plan carrying one is applicable, not
  -- refused, mirroring how splits stopped blocking once #6 landed.
  it("accepts a plan that needs a tempo transplant", function()
    local plan = empty_plan()
    plan.tempo_moves = { { region_name = "Intro" } }
    assert.is_true(validate.plan_is_region_move_only(plan))
  end)

  -- Parking stopped blocking when apply.split_parks landed (#7). It was the
  -- last category to do so, which is why the two specs that used to assert a
  -- refusal here are gone rather than rewritten: there is no longer any plan
  -- this check refuses, so the message-building path has nothing to exercise.
  it("accepts a plan with parked material", function()
    local plan = empty_plan()
    plan.parks = { { kind = "region", name = "Outtake" }, { kind = "item" } }
    assert.is_true(validate.plan_is_region_move_only(plan))
  end)

  -- The invariant that replaces them: every category a plan can carry is
  -- applicable. If a new one is added to lib/regions.lua without an applier,
  -- the honest outcome is that this check must start refusing again -- and
  -- this spec is where that gets noticed, because it will still pass while
  -- being wrong unless the category is entered in PLAN_CATEGORIES too. That is
  -- the residual risk lib/validate.lua's own comment names.
  it("accepts a plan carrying every category at once", function()
    local plan = empty_plan()
    for _, field in ipairs({ "splits", "drops", "envelope_drops", "pads", "places",
      "tempo_moves", "envelope_moves", "envelope_anchors", "marker_moves",
      "item_moves", "parks" }) do
      plan[field] = { {} }
    end
    assert.is_true(validate.plan_is_region_move_only(plan))
  end)
end)

describe("validate.format_problems", function()
  it("renders duplicates and empties as readable lines", function()
    local message = validate.format_problems({
      { code = "duplicate", name = "Intro", numbers = { 1, 7 } },
      { code = "empty", numbers = { 16 } },
    })
    assert.is_truthy(message:find("Intro", 1, true))
    assert.is_truthy(message:find("1", 1, true))
    assert.is_truthy(message:find("7", 1, true))
    assert.is_truthy(message:find("16", 1, true))
  end)

  it("returns an empty string when there is nothing to report", function()
    assert.are.equal("", validate.format_problems({}))
  end)
end)

describe("validate.tempo_env_is_time_based", function()
  -- 1 = Beats, 0 = Time. Read off a real project paired with its Project
  -- Settings dialog; secondary sources state this mapping backwards.
  it("refuses a project whose tempo envelope is on a Beats timebase", function()
    local ok, err = validate.tempo_env_is_time_based("  TIMELOCKMODE 0\n  TEMPOENVLOCKMODE 1\n")

    assert.is_false(ok)
    assert.is_truthy(err:find("Beats timebase", 1, true))
    assert.is_truthy(err:find("Timebase for tempo/time signature env", 1, true))
  end)

  it("accepts a project whose tempo envelope is on a Time timebase", function()
    assert.is_true(validate.tempo_env_is_time_based("  TIMELOCKMODE 0\n  TEMPOENVLOCKMODE 0\n"))
  end)

  -- An older project may predate the setting; absent means REAPER's own
  -- default, and blocking on a line that was never written would refuse runs
  -- that work fine.
  it("accepts a project that does not carry the setting at all", function()
    assert.is_true(validate.tempo_env_is_time_based("  TIMELOCKMODE 0\n"))
  end)

  -- This check reads the .RPP off disk, which can fail for reasons that have
  -- nothing to do with the tempo map. It advises; it must not become a new way
  -- for a run to be blocked.
  it("accepts an unreadable project file rather than blocking the run", function()
    assert.is_true(validate.tempo_env_is_time_based(nil))
  end)
end)

-- Issue #19's guard. Writing Tempo Anchors edits the tempo map, and a Repack
-- is allowed to do that -- but beat-attached material follows a tempo-map
-- edit, and phase 2 re-reads the project afterwards, so it plans a perfectly
-- self-consistent Repack against positions that moved underneath it. Nothing
-- downstream is in a position to notice. This is the thing that notices.
describe("validate.items_did_not_move", function()
  local function item(track_index, position, track_name)
    return { track_index = track_index, track_name = track_name, position = position, length = 10 }
  end

  local function snapshot(items)
    return { items = items }
  end

  it("accepts two identical snapshots", function()
    local items = { item(0, 12.5, "Click"), item(1, 30, "Gtr") }
    local ok, problems = validate.items_did_not_move(snapshot(items), snapshot(items))

    assert.is_true(ok)
    assert.are.same({}, problems)
  end)

  it("accepts a project with no items at all", function()
    local ok, problems = validate.items_did_not_move(snapshot({}), snapshot({}))

    assert.is_true(ok)
    assert.are.same({}, problems)
  end)

  it("refuses when an item moved further than the membership tolerance", function()
    local ok, problems = validate.items_did_not_move(
      snapshot({ item(2, 100.0, "Click 3") }),
      snapshot({ item(2, 114.82, "Click 3") }))

    assert.is_false(ok)
    assert.are.equal(1, #problems)
    assert.are.equal(2, problems[1].track_index)
    assert.are.equal(100.0, problems[1].from)
    assert.are.equal(114.82, problems[1].to)
  end)

  -- The same tolerance membership uses, so float noise between two reads of
  -- the same project is not reported as movement.
  it("accepts an item that moved by less than the membership tolerance", function()
    local ok = validate.items_did_not_move(
      snapshot({ item(0, 100.0) }),
      snapshot({ item(0, 100.0 + planner.BOUNDARY_TOLERANCE / 2) }))

    assert.is_true(ok)
  end)

  it("reports every moved item, not just the first", function()
    local ok, problems = validate.items_did_not_move(
      snapshot({ item(0, 10), item(0, 20), item(1, 30) }),
      snapshot({ item(0, 11), item(0, 20), item(1, 33) }))

    assert.is_false(ok)
    assert.are.equal(2, #problems)
    assert.are.equal(10, problems[1].from)
    assert.are.equal(30, problems[2].from)
  end)

  -- Items are paired by track and by snapshot order. Phase 1 writes only tempo
  -- markers, so nothing is created, deleted or reordered between the reads --
  -- but a snapshot is sorted by position, so an interleaved pair of tracks
  -- must still pair with its own track rather than with whatever sorted next.
  it("pairs items by track, not by position across the whole project", function()
    local ok, problems = validate.items_did_not_move(
      snapshot({ item(0, 10, "A"), item(1, 11, "B"), item(0, 20, "A"), item(1, 21, "B") }),
      snapshot({ item(0, 10, "A"), item(1, 11, "B"), item(0, 20, "A"), item(1, 21, "B") }))

    assert.is_true(ok)
    assert.are.same({}, problems)
  end)

  -- The user is about to go and look at the track, so the message names it the
  -- way REAPER's UI does (from 1) and says what kind of problem this is.
  it("formats a moved item with its track, both positions and the cause", function()
    local _, problems = validate.items_did_not_move(
      snapshot({ item(2, 100.0, "Click 3") }),
      snapshot({ item(2, 114.82, "Click 3") }))
    local message = validate.format_problems(problems)

    assert.is_truthy(message:find("track 3", 1, true))
    assert.is_truthy(message:find("Click 3", 1, true))
    assert.is_truthy(message:find("100.000", 1, true))
    assert.is_truthy(message:find("114.820", 1, true))
    assert.is_truthy(message:find("beat", 1, true))
  end)
end)
