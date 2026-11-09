-- lib/core/apply.lua driven headlessly: request in, result out, no dialogs.
--
-- What the dialog front end shows is pinned by spec/dialog_spec.lua. This is
-- the contract a front end builds on: which step refuses with which code,
-- that nothing is written before the Headroom answer, and the order a run
-- writes in (log before applier, all inside one undo block).

local apply = require("lib.core.apply")
local core_env = require("spec.support.core_env")
local projects = require("spec.support.projects")

local merge = projects.merge

local function bars(options)
  return core_env.new(merge({
    snapshots = { projects.BARS, projects.BARS_ANCHORED },
    files = projects.bars_files(),
    tempo = projects.bars_tempo(),
  }, options))
end

local function packed(options)
  return core_env.new(merge({ snapshots = { projects.PACKED }, files = projects.packed_files() },
    options))
end

describe("lib/core/apply.lua prepare", function()
  it("lists the Arrangements to choose from", function()
    local given = bars()
    local prepared = apply.prepare(given)

    assert.are.equal("ok", prepared.status)
    assert.are.equal(projects.BARS_PATH, prepared.project_path)
    assert.are.same({ "Ghost", "Headroom", "Identity", "Reordered", "Shrink", "Subset" },
      prepared.available)
  end)

  local refusals = {
    { "an unsaved project", "project_unsaved", { snapshots = { projects.UNSAVED_BARS } } },
    { "a tempo envelope on Beats", "tempo_env_beats",
      { files = projects.bars_files({ [projects.BARS_PATH] = projects.RPP_BEATS }) } },
    { "a project with no regions", "no_regions",
      { snapshots = { projects.EMPTY }, files = { ["/proj/Empty.rpp"] = projects.RPP_TIME } } },
    { "duplicate region names", "region_names", { snapshots = { projects.DUPES },
      files = projects.packed_files() } },
    { "an unreadable sidecar", "sidecar_invalid",
      { files = projects.bars_files({ [projects.BARS_SIDECAR] = "return {" }) } },
    { "a sidecar with no Arrangements", "no_arrangements",
      { files = projects.bars_files({ [projects.BARS_SIDECAR] = "return {}" }) } },
  }
  for _, case in ipairs(refusals) do
    it("refuses " .. case[1] .. " as " .. case[2] .. ", writing nothing", function()
      local given, world = bars(case[3])
      local prepared = apply.prepare(given)

      assert.are.equal("refused", prepared.status)
      assert.are.equal(case[2], prepared.error.code)
      assert.is_true(world.untouched())
    end)
  end

  it("carries what a refusal's wording needs", function()
    local prepared = apply.prepare((bars({ snapshots = { projects.UNSAVED_BARS } })))
    assert.is_string(prepared.error.message)

    prepared = apply.prepare((bars({ snapshots = { projects.DUPES }, files = projects.packed_files() })))
    assert.are.equal("duplicate", prepared.error.problems[1].code)
  end)

  it("marks a missing sidecar rather than refusing, so a host front end can import one", function()
    local given = bars({ files = { [projects.BARS_PATH] = projects.RPP_TIME } })
    local prepared = apply.prepare(given)

    assert.are.equal("ok", prepared.status)
    assert.is_true(prepared.sidecar_missing)
    assert.are.same({}, prepared.available)
  end)
end)

describe("lib/core/apply.lua import_sidecar", function()
  local function missing(extra_files)
    return bars({ files = projects.merge({ [projects.BARS_PATH] = projects.RPP_TIME }, extra_files) })
  end

  it("saves the imported Arrangements beside the project", function()
    local given, world = missing({ ["/elsewhere/good.lua"] = projects.BARS_ARRANGEMENTS })
    local prepared = apply.import_sidecar(apply.prepare(given), "/elsewhere/good.lua")

    assert.are.equal("ok", prepared.status)
    assert.is_false(prepared.sidecar_missing)
    assert.are.equal(6, #prepared.available)
    assert.is_truthy(world.files[projects.BARS_SIDECAR]:find("Reordered", 1, true))
  end)

  it("refuses a file it cannot read, naming it", function()
    local given = missing()
    local result = apply.import_sidecar(apply.prepare(given), "/elsewhere/nope.lua")

    assert.are.equal("import_unreadable", result.error.code)
    assert.are.equal("/elsewhere/nope.lua", result.error.path)
  end)

  it("refuses a file that is not a sidecar, writing nothing", function()
    local given, world = missing({ ["/elsewhere/bad.lua"] = "return 5" })
    local result = apply.import_sidecar(apply.prepare(given), "/elsewhere/bad.lua")

    assert.are.equal("import_invalid", result.error.code)
    assert.is_nil(world.files[projects.BARS_SIDECAR])
  end)
end)

describe("lib/core/apply.lua run", function()
  it("refuses when there is no sidecar, for a front end that cannot import one", function()
    local given = bars({ files = { [projects.BARS_PATH] = projects.RPP_TIME } })
    local result = apply.run(apply.prepare(given), { name = "Identity" })

    assert.are.equal("sidecar_missing", result.error.code)
  end)

  it("refuses an unknown name, listing the known ones", function()
    local given, world = bars()
    local result = apply.run(apply.prepare(given), { name = "Nope" })

    assert.are.equal("arrangement_unknown", result.error.code)
    assert.are.equal("Nope", result.error.name)
    assert.are.equal(6, #result.error.available)
    assert.is_true(world.untouched())
  end)

  it("refuses an Arrangement naming a region the project lacks", function()
    local given = bars()
    local result = apply.run(apply.prepare(given), { name = "Ghost" })

    assert.are.equal("arrangement_missing_regions", result.error.code)
    assert.are.same({ "Zulu" }, result.error.missing)
  end)

  it("trims the name, as the prompt always has", function()
    local given = bars()
    local result = apply.run(apply.prepare(given), { name = "  Reordered " })

    assert.are.equal("ok", result.status)
    assert.are.equal("Reordered", result.name)
  end)

  -- ADR-0007: Headroom is the one non-idempotent operation, and asking first
  -- is the whole of its guard. Nothing may be written before the answer.
  describe("with a Headroom", function()
    it("asks before writing anything, with the requests to confirm", function()
      local given, world = bars()
      local result = apply.run(apply.prepare(given), { name = "Headroom" })

      assert.are.equal("confirm", result.status)
      assert.are.equal("headroom", result.confirm.code)
      assert.are.same({ { name = "Bravo", seconds = 4 } }, result.confirm.headroom)
      assert.is_true(world.untouched())
    end)

    it("asks again for any answer it does not recognise", function()
      local given, world = bars()
      local result = apply.run(apply.prepare(given), { name = "Headroom", headroom = "yes" })

      assert.are.equal("confirm", result.status)
      assert.is_true(world.untouched())
    end)

    it("does nothing on cancel", function()
      local given, world = bars()
      local result = apply.run(apply.prepare(given), { name = "Headroom", headroom = "cancel" })

      assert.are.equal("cancelled", result.status)
      assert.is_true(world.untouched())
    end)

    it("repacks with the Headroom on apply", function()
      local given = bars()
      local result = apply.run(apply.prepare(given), { name = "Headroom", headroom = "apply" })

      assert.are.equal("ok", result.status)
      assert.are.equal(1, #result.plan.headroom)
      assert.are.equal("Bravo", result.plan.headroom[1].name)
    end)

    it("repacks treating every Headroom as zero on zero", function()
      local given = bars()
      local result = apply.run(apply.prepare(given), { name = "Headroom", headroom = "zero" })

      assert.are.equal("ok", result.status)
      assert.are.same({}, result.plan.headroom)
    end)
  end)

  describe("when Tempo Anchors are needed (phase 1, then phase 2)", function()
    it("writes anchors, re-reads, logs, then applies, all in one undo block", function()
      local given, world = bars()
      local result = apply.run(apply.prepare(given), { name = "Reordered" })

      assert.are.equal("ok", result.status)
      assert.is_false(result.noop)
      assert.are.equal(1, result.anchor_plan.changing)
      assert.are.equal(2, world.snapshots_taken)
      assert.are.same({
        "undo begin",
        "apply.anchors",
        "console",
        "write /proj/Bars.arrange.log",
        "apply.plan",
        "undo end Apply Arrangement",
      }, world.labels())
    end)

    it("records a failure after the plan was logged, but not one before it", function()
      local given, world = bars({ applier_fails = { plan = "boom" } })
      local ok = pcall(apply.run, apply.prepare(given), { name = "Reordered" })
      assert.is_false(ok)
      local log = world.files["/proj/Bars.arrange.log"]
      assert.is_truthy(log:find("tempo anchor", 1, true))
      assert.is_truthy(log:find("RUN FAILED: boom", 1, true))

      -- Failing at the anchors, the plan is not logged yet but the tempo map may
      -- be half rewritten, so the failure gets a heading and a line of its own.
      given, world = bars({ applier_fails = { anchors = "no anchors" } })
      ok = pcall(apply.run, apply.prepare(given), { name = "Reordered" })
      assert.is_false(ok)
      log = world.files["/proj/Bars.arrange.log"]
      assert.is_truthy(log:find('Apply Arrangement -- "Reordered"', 1, true))
      assert.is_truthy(log:find("RUN FAILED: no anchors", 1, true))
      assert.is_nil(log:find("tempo anchor (region", 1, true))
    end)

    it("hands the applier the plan it returns", function()
      local given, world = bars()
      local result = apply.run(apply.prepare(given), { name = "Reordered" })

      local applied = world.events[5]
      assert.are.equal("plan", applied.apply)
      assert.are.equal(result.plan, applied.value)
    end)

    it("logs the run beside the project", function()
      local given, world = bars()
      apply.run(apply.prepare(given), { name = "Reordered" })

      local log = world.files["/proj/Bars.arrange.log"]
      assert.is_truthy(log:find('[2026-11-07 12:00:00] Apply Arrangement -- "Reordered"', 1, true))
      assert.is_truthy(log:find('tempo anchor (region "Bravo")', 1, true))
    end)

    it("refuses when writing the anchors moved items, saying how many it wrote", function()
      local given, world = bars({ snapshots = { projects.BARS, projects.BARS_DRIFTED } })
      local result = apply.run(apply.prepare(given), { name = "Reordered" })

      assert.are.equal("refused", result.status)
      assert.are.equal("anchors_moved_items", result.error.code)
      assert.are.equal(1, result.error.anchors_written)
      assert.are.equal(11.5, result.error.moved[1].to)
      -- The block still closes: the anchors are one undo step.
      assert.are.same({ "undo begin", "apply.anchors", "undo end Apply Arrangement" }, world.labels())
    end)

    it("refuses a phase-2 plan after the anchors, saying how many it wrote", function()
      local given = bars()
      local result = apply.run(apply.prepare(given), { name = "Shrink", headroom = "apply" })

      assert.are.equal("plan_refused", result.error.code)
      assert.is_string(result.error.error)
      assert.are.equal(1, result.error.anchors_written)
    end)
  end)

  describe("when every Tempo Anchor is already present", function()
    it("reports an Arrangement that already matches as a no-op, leaving no trace", function()
      local given, world = packed()
      local result = apply.run(apply.prepare(given), { name = "Packed" })

      assert.are.equal("ok", result.status)
      assert.is_true(result.noop)
      assert.is_true(world.untouched())
    end)

    it("logs and applies in one undo block, without re-reading", function()
      local given, world = packed()
      local result = apply.run(apply.prepare(given), { name = "Swapped" })

      assert.is_false(result.noop)
      assert.are.equal(1, world.snapshots_taken)
      assert.are.same({
        "console",
        "write /proj/Packed.arrange.log",
        "undo begin",
        "apply.plan",
        "undo end Apply Arrangement",
      }, world.labels())
    end)

    it("records a failing applier in the log after the plan, closes the undo block and raises", function()
      local given, world = packed({ applier_fails = { plan = "boom at 12.000s" } })
      local prepared = apply.prepare(given)

      local ok, err = pcall(apply.run, prepared, { name = "Swapped" })

      assert.is_false(ok)
      assert.are.equal("boom at 12.000s", err)
      assert.are.same({
        "console", "write /proj/Packed.arrange.log",
        "undo begin", "apply.plan", "undo end Apply Arrangement",
        "console", "write /proj/Packed.arrange.log",
      }, world.labels())
      local log = world.files["/proj/Packed.arrange.log"]
      local plan_at = log:find("Apply Arrangement", 1, true)
      local failed_at = log:find("RUN FAILED: boom at 12.000s", 1, true)
      assert.is_truthy(plan_at)
      assert.is_truthy(failed_at)
      assert.is_true(failed_at > plan_at)
      assert.is_truthy(log:find("not done", failed_at, true))
    end)

    it("refuses a plan with nothing written and no anchors to mention", function()
      local given, world = packed()
      local result = apply.run(apply.prepare(given), { name = "Shrink", headroom = "apply" })

      assert.are.equal("plan_refused", result.error.code)
      assert.is_nil(result.error.anchors_written)
      assert.is_true(world.untouched())
    end)
  end)
end)
