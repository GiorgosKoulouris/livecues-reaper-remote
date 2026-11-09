-- Coverage of lib/report.lua: the aggregation layer behind
-- LCRR_Arrange_Check and LCRR_Arrange_Verify (issue #21).
--
-- These specs assert on the *report tables* the two functions return -- the
-- external behaviour -- and never on rendered message text or on which
-- primitive was called to reach a finding. Wording changes constantly and
-- proves nothing; what is worth pinning is "given this project state and this
-- Arrangement, does the report reach the right verdict and carry the right
-- findings".
--
-- Prior art: spec/validate_spec.lua for driving pure functions over plain
-- snapshot tables, spec/regions_spec.lua for supplying a fake tempo oracle.

local report = require("lib.report")
local planner = require("lib.regions")

-- An oracle that never Pads: every time is already on a bar line. Lets a spec
-- exercise everything downstream of Padding without Padding interfering.
-- Mirrors spec/regions_spec.lua's oracle of the same shape.
local NEVER_PADS = {
  next_bar_at_or_after = function(time) return time end,
  tempo_at = function() return 120, 4, 4 end,
}

-- Bar lines every `length` seconds from zero.
local function bar_oracle(length)
  return {
    next_bar_at_or_after = function(time)
      local bars = math.ceil(time / length - planner.BOUNDARY_TOLERANCE)
      return math.max(0, bars) * length
    end,
    tempo_at = function() return 120, 4, 4 end,
  }
end

local FLAT_AUTOMATION = { value_at = function() return 0 end }

local function region(name, number, start_time, end_time)
  return { name = name, number = number, start_time = start_time, end_time = end_time }
end

local function item(track_index, position, length, timebase_safe)
  return {
    track_index = track_index,
    track_name = ("Track %d"):format(track_index + 1),
    position = position,
    length = length,
    timebase_safe = timebase_safe ~= false,
  }
end

local function snapshot(fields)
  local base = {
    project_path = [[D:\P\Song.RPP]],
    region_reader = "GetRegionOrMarker",
    regions = {},
    markers = {},
    items = {},
    tempo_markers = {},
    envelope_points = {},
  }
  for key, value in pairs(fields or {}) do
    base[key] = value
  end
  return base
end

-- Three back-to-back regions, already bar-aligned at every bound under
-- bar_oracle(10), so nothing pads and nothing is refused.
local function clean_snapshot()
  return snapshot({
    regions = {
      region("Intro", 1, 0, 10),
      region("Verse", 2, 10, 30),
      region("Chorus", 3, 30, 60),
    },
  })
end

local function check(fields)
  local input = {
    snapshot = clean_snapshot(),
    name = "Radio",
    arrangements = { Radio = { "Intro", "Verse", "Chorus" } },
    rpp_text = "<REAPER_PROJECT\n  TEMPOENVLOCKMODE 0\n",
    tempo = NEVER_PADS,
    automation = FLAT_AUTOMATION,
  }
  for key, value in pairs(fields or {}) do
    input[key] = value
  end
  -- `arrangements = nil` in a table literal is an absent key, not an
  -- instruction to clear one, so the no-sidecar cases ask for it by name.
  if fields and fields.no_sidecar then
    input.arrangements = nil
  end
  return report.check(input)
end

local function codes(result)
  local found = {}
  for _, finding in ipairs(result.findings) do
    found[#found + 1] = finding.code
  end
  return found
end

local function has_code(result, code)
  for _, finding in ipairs(result.findings) do
    if finding.code == code then
      return true
    end
  end
  return false
end

local function finding(result, code)
  for _, entry in ipairs(result.findings) do
    if entry.code == code then
      return entry
    end
  end
  return nil
end

describe("report.check", function()
  describe("a clean Arrangement on a clean project", function()
    it("reports that the run will proceed", function()
      assert.are.equal("will proceed", check().verdict)
    end)

    it("raises no refusal", function()
      for _, entry in ipairs(check().findings) do
        assert.are_not.equal("refusal", entry.severity)
      end
    end)

    it("names the Arrangement it checked", function()
      assert.are.equal("Radio", check().arrangement)
    end)
  end)

  -- Every refusal Apply can raise, in isolation. The code is what a spec
  -- pins; the message is the script's business.
  describe("refusals", function()
    it("reports an unsaved project", function()
      local result = check({ snapshot = snapshot({
        project_path = "",
        regions = clean_snapshot().regions,
      }) })
      assert.is_true(has_code(result, "project_unsaved"))
      assert.are.equal("will refuse", result.verdict)
    end)

    it("reports a missing sidecar", function()
      local result = check({ no_sidecar = true, sidecar_reason = "missing" })
      assert.is_true(has_code(result, "sidecar_missing"))
      assert.are.equal("will refuse", result.verdict)
    end)

    -- A sidecar that exists but will not parse is a different problem from one
    -- that is absent: the first is a typo in a hand-edit, the second is a
    -- project that has never had an Arrangement.
    it("reports an unparseable sidecar separately from a missing one", function()
      local result = check({
        no_sidecar = true,
        sidecar_reason = "invalid",
        sidecar_error = "arrangements:3: unexpected symbol",
      })
      assert.is_true(has_code(result, "sidecar_invalid"))
      assert.is_false(has_code(result, "sidecar_missing"))
    end)

    it("reports an Arrangement name the sidecar does not have", function()
      local result = check({ name = "Radioo" })
      assert.is_true(has_code(result, "arrangement_unknown"))
      assert.are.equal("will refuse", result.verdict)
    end)

    it("lists the Arrangement names that do exist", function()
      local result = check({
        name = "Radioo",
        arrangements = { Radio = { "Intro" }, Full = { "Intro" } },
      })
      assert.are.same({ "Full", "Radio" }, finding(result, "arrangement_unknown").available)
    end)

    it("reports duplicate Region Names", function()
      local result = check({ snapshot = snapshot({
        regions = {
          region("Intro", 1, 0, 10),
          region("Intro", 2, 10, 30),
        },
      }) })
      assert.is_true(has_code(result, "region_names"))
      assert.are.equal("will refuse", result.verdict)
    end)

    it("reports regions with no name", function()
      local result = check({ snapshot = snapshot({
        regions = {
          region("Intro", 1, 0, 10),
          region("", 2, 10, 30),
        },
      }) })
      assert.is_true(has_code(result, "region_names"))
    end)

    -- A misspelled Region Name is an error the user wants caught; an omitted
    -- one is an instruction. These look alike and mean opposite things, so
    -- they get different codes and different severities.
    it("reports an Arrangement naming a region the project does not have", function()
      local result = check({ arrangements = { Radio = { "Intro", "Bridge" } } })
      assert.is_true(has_code(result, "arrangement_missing_regions"))
      assert.are.same({ "Bridge" }, finding(result, "arrangement_missing_regions").missing)
      assert.are.equal("will refuse", result.verdict)
    end)

    it("refuses an empty Arrangement with its own code, and does not plan it", function()
      local result = check({ arrangements = { Radio = {} } })
      assert.is_true(has_code(result, "arrangement_empty"))
      assert.are.equal("refusal", finding(result, "arrangement_empty").severity)
      assert.are.equal("will refuse", result.verdict)
      assert.is_true(has_code(result, "not_planned"))
      assert.is_false(has_code(result, "parked"))
    end)

    it("does not confuse an omitted region with a missing one", function()
      local result = check({ arrangements = { Radio = { "Intro", "Chorus" } } })
      assert.is_false(has_code(result, "arrangement_missing_regions"))
      assert.are.equal("will proceed", result.verdict)
    end)

    it("reports a tempo envelope on a Beats timebase", function()
      local result = check({ rpp_text = "<REAPER_PROJECT\n  TEMPOENVLOCKMODE 1\n" })
      assert.is_true(has_code(result, "tempo_env_beats"))
      assert.are.equal("will refuse", result.verdict)
    end)

    -- Padding running a region into its neighbour, and unsafe item timebases,
    -- both surface as a planner refusal rather than as separate checks -- the
    -- planner is the authority on both and restating its rules here would let
    -- them drift.
    it("reports a planner refusal, such as an item on an unsafe timebase", function()
      -- The Arrangement is reversed so the regions actually move: an item on an
      -- unsafe timebase is only a problem for a region the run repositions.
      local result = check({
        snapshot = snapshot({
          regions = clean_snapshot().regions,
          items = { item(0, 12, 4, false) },
        }),
        arrangements = { Radio = { "Chorus", "Verse", "Intro" } },
      })
      assert.is_true(has_code(result, "plan_refused"))
      assert.are.equal("will refuse", result.verdict)
    end)

    it("reports overlapping regions as a planner refusal", function()
      local result = check({
        snapshot = snapshot({
          regions = {
            region("Intro", 1, 0, 9),
            region("Verse", 2, 10, 30),
            region("Chorus", 3, 30, 60),
          },
        }),
        -- Padding "Intro" out to bar 10 does not overlap, but padding it to 20
        -- runs it into "Verse".
        tempo = bar_oracle(20),
      })
      assert.is_true(has_code(result, "plan_refused"))
    end)

    -- The whole point of a precheck is saving a round trip, so it must not
    -- stop at the first thing it finds.
    it("reports every refusal it finds, not only the first", function()
      local result = check({
        snapshot = snapshot({
          project_path = "",
          regions = {
            region("Intro", 1, 0, 10),
            region("Intro", 2, 10, 30),
          },
        }),
        rpp_text = "<REAPER_PROJECT\n  TEMPOENVLOCKMODE 1\n",
      })
      assert.is_true(has_code(result, "project_unsaved"))
      assert.is_true(has_code(result, "region_names"))
      assert.is_true(has_code(result, "tempo_env_beats"))
    end)
  end)

  -- Item timebase is a static property of tracks and items, so it is knowable
  -- whatever else is wrong. The planner only refuses over an item inside a
  -- region *this* Arrangement moves, but "which tracks do I have to change?" is
  -- the question the user acts on, and it has an answer either way.
  describe("item timebase", function()
    it("names items on an unsafe timebase even when nothing would refuse", function()
      local result = check({ snapshot = snapshot({
        regions = clean_snapshot().regions,
        items = { item(0, 2, 4, false) },
      }) })
      local unsafe = finding(result, "unsafe_timebase")
      assert.is_truthy(unsafe)
      assert.are.equal(1, #unsafe.items)
      assert.are.equal("will proceed", result.verdict)
    end)

    it("names them even when an unrelated problem stopped the planner", function()
      local result = check({
        snapshot = snapshot({
          regions = {
            region("Intro", 1, 0, 10),
            region("Intro", 2, 10, 30),
          },
          items = { item(0, 2, 4, false) },
        }),
      })
      assert.is_true(has_code(result, "region_names"))
      assert.is_true(has_code(result, "unsafe_timebase"))
    end)

    it("says nothing when every item is on a safe timebase", function()
      assert.is_false(has_code(check(), "unsafe_timebase"))
    end)
  end)

  -- A report that is quietly shorter than usual reads like a cleaner project
  -- rather than a partial answer, which is the opposite of what a check is for.
  describe("when a problem stops the planner", function()
    it("says the Repack was not planned, so the silence is not read as a clean bill", function()
      local result = check({ name = "Radioo" })
      assert.is_true(has_code(result, "not_planned"))
    end)

    it("does not say so when the Repack was planned", function()
      assert.is_false(has_code(check(), "not_planned"))
    end)
  end)

  describe("permanent effects that are not refusals", function()
    it("reports the regions a subset Arrangement will park", function()
      local result = check({ arrangements = { Radio = { "Intro", "Chorus" } } })
      local parked = finding(result, "parked")
      assert.is_truthy(parked)
      assert.are.equal("permanent", parked.severity)
      assert.are.same({ "Verse" }, parked.regions)
    end)

    it("does not treat parking as a refusal", function()
      local result = check({ arrangements = { Radio = { "Intro", "Chorus" } } })
      assert.are.equal("will proceed", result.verdict)
    end)

    it("reports Padding per region, with the amount", function()
      local result = check({
        snapshot = snapshot({
          regions = {
            region("Intro", 1, 0, 8),
            region("Verse", 2, 20, 40),
          },
        }),
        arrangements = { Radio = { "Intro", "Verse" } },
        tempo = bar_oracle(10),
      })
      local padded = finding(result, "padded")
      assert.is_truthy(padded)
      assert.are.equal("permanent", padded.severity)
      assert.are.equal(1, #padded.pads)
      assert.are.equal("Intro", padded.pads[1].name)
      assert.is_true(math.abs(padded.pads[1].added - 2) < planner.BOUNDARY_TOLERANCE)
    end)

    it("reports material that would be discarded", function()
      local result = check({ snapshot = snapshot({
        regions = clean_snapshot().regions,
        items = { item(0, 200, 4) },
      }) })
      local dropped = finding(result, "dropped")
      assert.is_truthy(dropped)
      assert.are.equal("permanent", dropped.severity)
      assert.are.equal(1, #dropped.items)
    end)

    it("reports Straddling Items that would be cut", function()
      local result = check({
        snapshot = snapshot({
          regions = clean_snapshot().regions,
          items = { item(0, 8, 6) },
        }),
        arrangements = { Radio = { "Chorus", "Verse", "Intro" } },
      })
      local cut = finding(result, "cut")
      assert.is_truthy(cut)
      assert.are.equal("permanent", cut.severity)
    end)
  end)

  -- Padding is computed against the grid that exists *now*. On a project whose
  -- Tempo Anchors are all already present that is the post-anchor grid and the
  -- figures are exact; on a first run it is an estimate. plan_anchors already
  -- knows which case it is in, so the report says so rather than hedging.
  describe("Padding accuracy", function()
    it("reports Padding as exact when every Tempo Anchor is already present", function()
      local result = check({ snapshot = snapshot({
        regions = clean_snapshot().regions,
        tempo_markers = {
          { position = 0, bpm = 120, timesig_num = 4, timesig_denom = 4, starts_measure = true },
          { position = 10, bpm = 120, timesig_num = 4, timesig_denom = 4, starts_measure = true },
          { position = 30, bpm = 120, timesig_num = 4, timesig_denom = 4, starts_measure = true },
        },
      }) })
      assert.is_true(result.padding_exact)
    end)

    it("reports Padding as an estimate when Tempo Anchors are still to be written", function()
      assert.is_false(check().padding_exact)
    end)
  end)

  -- Not a disclaimer: Padding and beat-attached drift depend on a bar grid the
  -- Tempo Anchors create, and per ADR-0006 the oracle reads live project
  -- state, so it cannot be asked about a grid that does not exist yet. A check
  -- that quietly implied otherwise would be worse than no check.
  describe("blind spots", function()
    it("states what it could not determine, even on a clean report", function()
      assert.is_true(#check().blind_spots > 0)
    end)

    it("states them on a refusing report too", function()
      assert.is_true(#check({ name = "Radioo" }).blind_spots > 0)
    end)
  end)

  -- A user who reads only the top of the report should have read the part that
  -- stops them.
  it("orders findings refusals first, then permanent effects, then the rest", function()
    local result = check({
      snapshot = snapshot({
        project_path = "",
        regions = clean_snapshot().regions,
        items = { item(0, 200, 4) },
      }),
      arrangements = { Radio = { "Intro", "Chorus" } },
    })
    local rank = { refusal = 1, permanent = 2, informational = 3 }
    local previous = 0
    for _, entry in ipairs(result.findings) do
      assert.is_true(rank[entry.severity] >= previous)
      previous = rank[entry.severity]
    end
    assert.is_true(#codes(result) >= 3)
  end)
end)

describe("report.verify", function()
  local function verify(fields)
    local input = {
      snapshot = snapshot({
        regions = {
          region("Intro", 1, 0, 10),
          region("Verse", 2, 10, 30),
          region("Chorus", 3, 30, 60),
        },
      }),
      arrangement = { "Intro", "Verse", "Chorus" },
      tempo = bar_oracle(10),
    }
    for key, value in pairs(fields or {}) do
      input[key] = value
    end
    return report.verify(input)
  end

  it("passes a correctly packed timeline", function()
    local result = verify()
    assert.are.equal("pass", result.verdict)
    assert.are.same({}, result.findings)
  end)

  it("fails when a region the Arrangement names is not in the project", function()
    local result = verify({ arrangement = { "Intro", "Bridge" } })
    assert.are.equal("fail", result.verdict)
    assert.is_true(has_code(result, "region_absent"))
  end)

  it("fails when the regions are not in Arrangement order", function()
    local result = verify({ arrangement = { "Verse", "Intro", "Chorus" } })
    assert.are.equal("fail", result.verdict)
    assert.is_true(has_code(result, "order_mismatch"))
  end)

  it("fails when the Packed Block has a gap", function()
    local result = verify({ snapshot = snapshot({
      regions = {
        region("Intro", 1, 0, 10),
        region("Verse", 2, 20, 40),
        region("Chorus", 3, 40, 70),
      },
    }) })
    assert.are.equal("fail", result.verdict)
    assert.is_true(has_code(result, "gap"))
  end)

  it("fails when the Packed Block does not start at the beginning of the timeline", function()
    local result = verify({ snapshot = snapshot({
      regions = {
        region("Intro", 1, 10, 20),
        region("Verse", 2, 20, 40),
        region("Chorus", 3, 40, 70),
      },
    }) })
    assert.are.equal("fail", result.verdict)
    assert.is_true(has_code(result, "block_start"))
  end)

  -- ADR-0004's central promise.
  it("fails when a region start does not land on a bar line", function()
    local result = verify({
      snapshot = snapshot({
        regions = {
          region("Intro", 1, 0, 12),
          region("Verse", 2, 12, 32),
        },
      }),
      arrangement = { "Intro", "Verse" },
    })
    assert.are.equal("fail", result.verdict)
    local off = finding(result, "off_bar_line")
    assert.are.equal("Verse", off.region_name)
    assert.are.equal(12, off.at)
    assert.are.equal(20, off.expected)
  end)

  -- A check that disagreed with the planner about float noise would fail runs
  -- the planner considers clean (lib/validate.lua's own reasoning).
  it("passes a region start off the bar line by less than the planner's tolerance", function()
    local nudge = planner.BOUNDARY_TOLERANCE / 2
    local result = verify({ snapshot = snapshot({
      regions = {
        region("Intro", 1, 0, 10 + nudge),
        region("Verse", 2, 10 + nudge, 30),
        region("Chorus", 3, 30, 60),
      },
    }) })
    assert.are.equal("pass", result.verdict)
  end)

  describe("Parked Material", function()
    it("passes when omitted regions sit beyond the Packed Block", function()
      local result = verify({
        snapshot = snapshot({
          regions = {
            region("Intro", 1, 0, 10),
            region("Chorus", 2, 10, 40),
            region("Verse", 3, 340, 360),
          },
        }),
        arrangement = { "Intro", "Chorus" },
      })
      assert.are.equal("pass", result.verdict)
    end)

    it("fails when an omitted region is still inside the Packed Block", function()
      local result = verify({
        snapshot = snapshot({
          regions = {
            region("Intro", 1, 0, 10),
            region("Verse", 2, 10, 30),
            region("Chorus", 3, 30, 60),
          },
        }),
        arrangement = { "Intro", "Chorus" },
      })
      assert.are.equal("fail", result.verdict)
      assert.is_true(has_code(result, "not_parked"))
    end)
  end)

  it("names the region and the amount when it fails", function()
    local result = verify({ snapshot = snapshot({
      regions = {
        region("Intro", 1, 0, 10),
        region("Verse", 2, 20, 40),
        region("Chorus", 3, 40, 70),
      },
    }) })
    local gap = finding(result, "gap")
    assert.are.equal("Verse", gap.region_name)
    assert.is_true(math.abs(gap.size - 10) < planner.BOUNDARY_TOLERANCE)
  end)
end)

-- Headroom (CONTEXT.md): the per-region end adjustment an Arrangement carries.
describe("report.check with Headroom", function()
  -- bar_oracle plus the two directional primitives Headroom resolution needs.
  -- Bars every 10 seconds, matching clean_snapshot's geometry.
  local function headroom_oracle(length)
    local base = bar_oracle(length)
    base.bar_at_or_before = function(time)
      return math.max(0, math.floor(time / length + planner.BOUNDARY_TOLERANCE)) * length
    end
    base.bar_after = function(time)
      return base.bar_at_or_before(time) + length
    end
    return base
  end

  local function arrangement(names, headroom)
    local list = {}
    for _, name in ipairs(names) do
      list[#list + 1] = name
    end
    list.headroom = headroom
    return list
  end

  local function check_headroom(headroom)
    return check({
      tempo = headroom_oracle(10),
      arrangements = { Radio = arrangement({ "Intro", "Verse", "Chorus" }, headroom) },
    })
  end

  it("reports each adjustment as a permanent effect", function()
    local entry = finding(check_headroom({ Verse = 20 }), "headroom")

    assert.is_truthy(entry)
    assert.are.equal("permanent", entry.severity)
    assert.are.equal(1, #entry.headroom)
    assert.are.equal("Verse", entry.headroom[1].name)
    assert.are.equal(20, entry.headroom[1].resolved)
  end)

  -- The likeliest "nothing happened": under half a bar, a request rounds to
  -- nothing, and a region quietly missing from the report reads as a check that
  -- did not notice the edit.
  it("still lists a region whose request resolved to no change", function()
    local entry = finding(check_headroom({ Verse = 2 }), "headroom")

    assert.are.equal(1, #entry.headroom)
    assert.are.equal("Verse", entry.headroom[1].name)
    assert.are.equal(2, entry.headroom[1].requested)
    assert.are.equal(0, entry.headroom[1].resolved)
  end)

  it("raises no Headroom finding when every value is zero", function()
    assert.is_falsy(finding(check_headroom({ Intro = 0, Verse = 0, Chorus = 0 }), "headroom"))
  end)

  -- One check is one round trip, so a blocked shrink has to arrive in the
  -- section the user already reads refusals in.
  it("surfaces a refused shrink as a refusal", function()
    local result = check({
      tempo = headroom_oracle(10),
      snapshot = snapshot({
        regions = { region("Intro", 1, 0, 10), region("Verse", 2, 10, 30) },
        items = { item(0, 10, 20) },
      }),
      arrangements = { Radio = arrangement({ "Intro", "Verse" }, { Verse = -20 }) },
    })

    assert.are.equal("will refuse", result.verdict)
    assert.is_true(has_code(result, "plan_refused"))
    assert.is_truthy(finding(result, "plan_refused").error:find("Verse", 1, true))
  end)
end)

describe("report.verify blind spots", function()
  it("states that it cannot see whether a Headroom was applied twice", function()
    local result = report.verify({
      snapshot = clean_snapshot(),
      arrangement = { "Intro", "Verse", "Chorus" },
      tempo = NEVER_PADS,
    })

    assert.are.equal("pass", result.verdict)
    assert.are.same({ "headroom_count" }, result.blind_spots)
  end)

  it("carries the same blind spots on a failing verify", function()
    local result = report.verify({
      snapshot = clean_snapshot(),
      arrangement = { "Intro", "Nope" },
      tempo = NEVER_PADS,
    })

    assert.are.equal("fail", result.verdict)
    assert.are.same({ "headroom_count" }, result.blind_spots)
  end)
end)

describe("report.headroom_requests", function()
  local function arrangement(names, headroom)
    local list = {}
    for _, name in ipairs(names) do
      list[#list + 1] = name
    end
    list.headroom = headroom
    return list
  end

  -- CLAUDE.md: scripts run immediately, with no confirmation prompt. Every run
  -- that behaves like today's must keep doing so.
  it("asks nothing for an Arrangement with no Headroom at all", function()
    assert.are.same({}, report.headroom_requests({ "Intro", "Verse" }))
  end)

  it("asks nothing when every Headroom is zero", function()
    assert.are.same({}, report.headroom_requests(
      arrangement({ "Intro", "Verse" }, { Intro = 0, Verse = 0 })))
  end)

  it("lists each non-zero request with the seconds asked for", function()
    assert.are.same({
      { name = "Intro", seconds = -2 },
      { name = "Chorus", seconds = 4 },
    }, report.headroom_requests(
      arrangement({ "Intro", "Verse", "Chorus" }, { Intro = -2, Chorus = 4 })))
  end)

  it("lists them in Arrangement order", function()
    local requests = report.headroom_requests(
      arrangement({ "Chorus", "Intro" }, { Intro = -2, Chorus = 4 }))

    assert.are.equal("Chorus", requests[1].name)
    assert.are.equal("Intro", requests[2].name)
  end)
end)

describe("report.without_headroom", function()
  it("keeps the order and drops the adjustments", function()
    local stripped = report.without_headroom({ "Intro", "Verse", headroom = { Intro = 4 } })

    assert.are.same({ "Intro", "Verse" }, stripped)
    assert.is_nil(stripped.headroom)
  end)

  it("leaves the original untouched", function()
    local original = { "Intro", headroom = { Intro = 4 } }
    report.without_headroom(original)
    assert.are.equal(4, original.headroom.Intro)
  end)
end)

-- The bridge (spec step 4) sends these results as JSON and words them in the
-- page, so nothing here may arrive pre-worded: every finding is a code plus
-- the fields its wording needs (lib/text/check.lua, lib/text/verify.lua).
describe("structured reports", function()
  local function no_wording(result)
    for _, entry in ipairs(result.findings) do
      assert.is_nil(entry.detail, entry.code .. " carries pre-worded detail")
      assert.is_string(entry.code)
    end
  end

  it("check findings carry codes and fields, not sentences", function()
    local result = check({
      name = "Nope",
      rpp_text = "<REAPER_PROJECT\n  TEMPOENVLOCKMODE 1\n",
      snapshot = snapshot({
        project_path = "",
        regions = { region("Intro", 1, 0, 10), region("Intro", 2, 10, 20) },
      }),
    })

    assert.are.same(
      { "project_unsaved", "tempo_env_beats", "region_names", "arrangement_unknown", "not_planned" },
      codes(result))
    no_wording(result)
    assert.are.equal("Nope", finding(result, "arrangement_unknown").name)
    assert.are.same({ "Radio" }, finding(result, "arrangement_unknown").available)
    assert.is_string(finding(result, "project_unsaved").message)
    assert.is_string(finding(result, "tempo_env_beats").message)
    assert.are.equal("duplicate", finding(result, "region_names").problems[1].code)
  end)

  it("check counts what will move", function()
    local result = check({
      snapshot = snapshot({
        regions = { region("Intro", 1, 0, 10), region("Verse", 2, 20, 30) },
      }),
      arrangements = { Radio = { "Verse", "Intro" } },
    })

    assert.are.same({ regions = 2, markers = 0, tempo_markers = 0, envelope_points = 0, items = 0 },
      finding(result, "moves").counts)
  end)

  it("check names its blind spots by code", function()
    assert.are.same({ "padding_grid", "anchor_drift", "padding_overlap" }, check().blind_spots)
  end)

  it("verify findings carry codes and fields, not sentences", function()
    local result = report.verify({
      snapshot = snapshot({
        regions = { region("Intro", 1, 10, 20), region("Verse", 2, 0, 10) },
      }),
      arrangement = { "Intro", "Verse" },
      tempo = NEVER_PADS,
    })

    assert.are.same({ "order_mismatch" }, codes(result))
    no_wording(result)
    assert.are.same({ code = "order_mismatch", region_name = "Verse", at = 0,
      after = "Intro", after_at = 10 }, result.findings[1])
  end)
end)
