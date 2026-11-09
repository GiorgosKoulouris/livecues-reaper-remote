-- The read-only cores driven headlessly: Check, Verify, and the three
-- diagnostics. None of them may open a dialog (spec/support/core_env.lua
-- errors if one tries), and none writes anything but its run-log entry.

local check = require("lib.core.check")
local verify = require("lib.core.verify")
local find = require("lib.core.find_duplicate_region_names")
local bar_lines = require("lib.core.show_bar_lines")
local timebase = require("lib.core.show_track_timebase")
local core_env = require("spec.support.core_env")
local projects = require("spec.support.projects")

local merge = projects.merge

local function bars(options)
  return core_env.new(merge({
    snapshots = { projects.BARS },
    files = projects.bars_files(),
    tempo = projects.bars_tempo(),
  }, options))
end

local function packed(options)
  return core_env.new(merge({ snapshots = { projects.PACKED }, files = projects.packed_files() },
    options))
end

local function writes(world)
  local found = {}
  for _, label in ipairs(world.labels()) do
    if label:match("^write ") then
      found[#found + 1] = label
    end
  end
  return found
end

describe("lib/core/check.lua", function()
  it("refuses a project with no regions in prepare", function()
    local given, world = core_env.new({ snapshots = { projects.EMPTY } })
    local prepared = check.prepare(given)

    assert.are.equal("no_regions", prepared.error.code)
    assert.is_true(world.untouched())
  end)

  it("lists the names to choose from", function()
    local prepared = check.prepare((bars()))
    assert.are.equal(6, #prepared.available)
  end)

  it("lists none when the sidecar is missing, and still checks", function()
    local given = bars({ files = { [projects.BARS_PATH] = projects.RPP_TIME } })
    local prepared = check.prepare(given)
    assert.are.same({}, prepared.available)

    local result = check.run(prepared, { name = "" })
    assert.are.equal("will refuse", result.verdict)
    assert.are.equal("sidecar_missing", result.findings[1].code)
  end)

  it("returns the structured report, named and trimmed", function()
    local given = bars()
    local result = check.run(check.prepare(given), { name = " Subset " })

    assert.are.equal("ok", result.status)
    assert.are.equal("Subset", result.name)
    assert.are.equal("Subset", result.arrangement)
    assert.are.equal("will proceed", result.verdict)
    assert.is_false(result.padding_exact)
    assert.are.equal(projects.BARS_PATH, result.project_path)
  end)

  it("writes nothing but its run-log entry", function()
    local given, world = bars()
    check.run(check.prepare(given), { name = "Reordered" })

    assert.are.same({ "write /proj/Bars.arrange.log" }, writes(world))
    assert.is_truthy(world.files["/proj/Bars.arrange.log"]
      :find('Check Arrangement -- "Reordered"', 1, true))
  end)

  it("reads the .RPP for the tempo-envelope timebase", function()
    local given = bars({ files = projects.bars_files({ [projects.BARS_PATH] = projects.RPP_BEATS }) })
    local result = check.run(check.prepare(given), { name = "Identity" })

    assert.are.equal("tempo_env_beats", result.findings[1].code)
  end)
end)

describe("lib/core/verify.lua", function()
  local refusals = {
    { "no regions", "no_regions", { snapshots = { projects.EMPTY } } },
    { "an unreadable sidecar", "sidecar_invalid",
      { files = projects.bars_files({ [projects.BARS_SIDECAR] = "return {" }) } },
    { "an unsaved project", "sidecar_unsaved", { snapshots = { projects.UNSAVED_BARS } } },
    { "no sidecar", "no_arrangements", { files = { [projects.BARS_PATH] = projects.RPP_TIME } } },
  }
  for _, case in ipairs(refusals) do
    it("refuses " .. case[1] .. " as " .. case[2], function()
      local given, world = bars(case[3])
      local prepared = verify.prepare(given)

      assert.are.equal(case[2], prepared.error.code)
      assert.is_true(world.untouched())
    end)
  end

  it("refuses an unknown name, writing nothing", function()
    local given, world = packed()
    local result = verify.run(verify.prepare(given), { name = "Nope" })

    assert.are.equal("arrangement_unknown", result.error.code)
    assert.are.equal("Nope", result.error.name)
    assert.is_true(world.untouched())
  end)

  it("passes a packed timeline, and logs it", function()
    local given, world = packed()
    local result = verify.run(verify.prepare(given), { name = "Packed" })

    assert.are.equal("ok", result.status)
    assert.are.equal("pass", result.verdict)
    assert.are.equal("Packed", result.name)
    assert.are.same({ "write /proj/Packed.arrange.log" }, writes(world))
  end)

  it("fails a timeline in the wrong order, with structured findings", function()
    local given = packed()
    local result = verify.run(verify.prepare(given), { name = "Swapped" })

    assert.are.equal("fail", result.verdict)
    assert.are.equal("order_mismatch", result.findings[1].code)
    assert.are.equal("A", result.findings[1].region_name)
  end)
end)

describe("lib/core/find_duplicate_region_names.lua", function()
  it("reports problems as structured entries, and logs them", function()
    local given, world = core_env.new({ snapshots = { projects.DUPES } })
    local result = find.run(given)

    assert.are.equal("problems", result.verdict)
    assert.are.equal(3, result.region_count)
    assert.are.same({ "duplicate", "empty" }, { result.problems[1].code, result.problems[2].code })
    assert.are.same({ "write /proj/Packed.arrange.log" }, writes(world))
  end)

  it("reports a clean project", function()
    local given = core_env.new({ snapshots = { projects.PACKED } })
    assert.are.equal("clean", find.run(given).verdict)
  end)

  it("reports a project with no regions", function()
    local given = core_env.new({ snapshots = { projects.EMPTY } })
    assert.are.equal("no_regions", find.run(given).verdict)
  end)
end)

describe("lib/core/show_bar_lines.lua", function()
  local function api()
    return { TimeMap2_timeToBeats = function() return 0, 0, 0, 0, 4 end }
  end

  it("refuses a project with no regions", function()
    local given = core_env.new({ snapshots = { projects.EMPTY }, api = api() })
    assert.are.equal("no_regions", bar_lines.run(given).error.code)
  end)

  it("reports each region's bounds against the grid, in timeline order, writing nothing", function()
    local given, world = bars({ api = api() })
    local result = bar_lines.run(given)

    assert.are.equal("ok", result.status)
    assert.are.equal(0, result.origin_measure)
    assert.are.same({ bpm = 120, num = 4, denom = 4 }, result.origin)
    assert.are.same({ "Alpha", "Bravo", "Charlie", "Delta" },
      { result.regions[1].name, result.regions[2].name, result.regions[3].name, result.regions[4].name })

    local bravo = result.regions[2]
    assert.are.equal(22, bravo.end_bar)
    assert.are.equal(1, bravo.pad)
    assert.is_true(bravo.pads)
    assert.is_true(bravo.on_bar)
    assert.are.equal(result.padded, 2)
    assert.is_true(world.untouched())
  end)
end)

describe("lib/core/show_track_timebase.lua", function()
  local function tracks(list)
    return {
      CountTracks = function() return #list end,
      GetTrack = function(_, index) return list[index + 1] end,
      GetMediaTrackInfo_Value = function(track) return track.mode end,
      GetSetMediaTrackInfo_String = function(track) return true, track.name end,
    }
  end

  it("refuses a project with no tracks", function()
    local given = core_env.new({ api = tracks({}) })
    assert.are.equal("no_tracks", timebase.run(given).error.code)
  end)

  it("lists every track and tallies the modes", function()
    local given = core_env.new({ api = tracks({
      { name = "Gtr", mode = 0 }, { name = "Keys", mode = -1 }, { name = "Bass", mode = 0 },
    }) })
    local result = timebase.run(given)

    assert.are.equal("ok", result.status)
    assert.are.same({ track_index = 1, name = "Keys", mode = -1 }, result.tracks[2])
    assert.are.same({ [0] = 2, [-1] = 1 }, result.tally)
    assert.are.equal(_VERSION, result.lua_version)
  end)
end)
