-- lib/core/capture.lua driven headlessly: the overwrite confirmation is a
-- result, not a dialog, so a front end can ask in its own way (spec step 4's
-- in-page confirm) and nothing is written until it has.

local capture = require("lib.core.capture")
local sidecar = require("lib.sidecar")
local core_env = require("spec.support.core_env")
local projects = require("spec.support.projects")

-- The fixture sidecar is hand-written (bare strings), so it is not canonical.
-- Most specs run on its canonical rewrite; `hand_written` keeps it as it is.
local CANONICAL = sidecar.serialize(assert(sidecar.parse(projects.BARS_ARRANGEMENTS)))

local function bars(options)
  return core_env.new(projects.merge({ snapshots = { projects.BARS },
    files = projects.bars_files({ [projects.BARS_SIDECAR] = CANONICAL }) }, options))
end

local function hand_written(options)
  return core_env.new(projects.merge({ snapshots = { projects.BARS }, files = projects.bars_files() },
    options))
end

local function saved(world)
  return assert(sidecar.parse(world.files[projects.BARS_SIDECAR]))
end

-- The Region Names of a parsed Arrangement, without its Headroom map.
local function order(arrangement)
  return { table.unpack(arrangement) }
end

describe("lib/core/capture.lua", function()
  local refusals = {
    { "an unsaved project", "project_unsaved", { snapshots = { projects.UNSAVED_BARS } } },
    { "a project with no regions", "no_regions", { snapshots = { projects.EMPTY } } },
    { "duplicate region names", "region_names", { snapshots = { projects.DUPES } } },
    { "an unreadable sidecar", "sidecar_invalid",
      { files = projects.bars_files({ [projects.BARS_SIDECAR] = "return {" }) } },
  }
  for _, case in ipairs(refusals) do
    it("refuses " .. case[1] .. " as " .. case[2] .. " in prepare", function()
      local given, world = bars(case[3])
      local prepared = capture.prepare(given)

      assert.are.equal(case[2], prepared.error.code)
      assert.is_true(world.untouched())
    end)
  end

  it("refuses a blank name", function()
    local given, world = bars()
    local result = capture.run(capture.prepare(given), { name = "   " })

    assert.are.equal("name_empty", result.error.code)
    assert.is_true(world.untouched())
  end)

  it("captures a new name in timeline order, trimmed, and logs it", function()
    local given, world = bars()
    local result = capture.run(capture.prepare(given), { name = "  Live " })

    assert.are.equal("ok", result.status)
    assert.are.equal("Live", result.name)
    assert.is_false(result.replaced)
    assert.are.same({ "Alpha", "Bravo", "Charlie", "Delta" }, result.regions)
    assert.are.equal(projects.BARS_SIDECAR, result.path)
    assert.are.same({ "Alpha", "Bravo", "Charlie", "Delta" }, order(saved(world).Live))
    assert.is_truthy(world.files["/proj/Bars.arrange.log"]
      :find('Capture Region Order -- captured "Live"', 1, true))
  end)

  it("asks before replacing an existing Arrangement, writing nothing", function()
    local given, world = bars()
    local result = capture.run(capture.prepare(given), { name = "Reordered" })

    assert.are.equal("confirm", result.status)
    assert.are.same({ code = "replace", name = "Reordered" }, result.confirm)
    assert.is_true(world.untouched())
  end)

  it("replaces it once confirmed", function()
    local given = bars()
    local prepared = capture.prepare(given)
    capture.run(prepared, { name = "Reordered" })
    local result = capture.run(prepared, { name = "Reordered", replace = true })

    assert.are.equal("ok", result.status)
    assert.is_true(result.replaced)
  end)

  it("keeps the other Arrangements when it replaces one", function()
    local given, world = bars()
    capture.run(capture.prepare(given), { name = "Reordered", replace = true })

    local arrangements = saved(world)
    assert.are.same({ "Alpha", "Bravo", "Charlie", "Delta" }, order(arrangements.Reordered))
    assert.is_truthy(arrangements.Subset)
  end)

  it("refuses when the sidecar cannot be written", function()
    local given = bars({ unwritable = { [projects.BARS_SIDECAR] = true } })
    local result = capture.run(capture.prepare(given), { name = "Live" })

    assert.are.equal("save_failed", result.error.code)
    assert.is_string(result.error.error)
  end)

  describe("a hand-edited sidecar", function()
    local hand_edited = hand_written

    it("asks before rewriting it, writing nothing", function()
      local given, world = hand_edited()
      local result = capture.run(capture.prepare(given), { name = "Live" })

      assert.are.equal("confirm", result.status)
      assert.are.same({ code = "rewrite" }, result.confirm)
      assert.is_true(world.untouched())
    end)

    it("asks the replace question first, then the rewrite one, and takes both answers at once", function()
      local given, world = hand_edited()
      local prepared = capture.prepare(given)

      assert.are.equal("replace", capture.run(prepared, { name = "Identity" }).confirm.code)
      assert.are.equal("rewrite",
        capture.run(prepared, { name = "Identity", replace = true }).confirm.code)
      assert.is_true(world.untouched())
      assert.are.equal("ok",
        capture.run(prepared, { name = "Identity", replace = true, rewrite = true }).status)
    end)

    it("does not ask again once the file has been rewritten", function()
      local given, world = hand_edited()
      capture.run(capture.prepare(given), { name = "Live", rewrite = true })
      assert.is_true(sidecar.is_canonical(world.files[projects.BARS_SIDECAR]))

      local second = capture.run(capture.prepare(given), { name = "Again" })
      assert.are.equal("ok", second.status)
    end)

    it("does not ask when there is no sidecar yet", function()
      local given = bars({ files = { [projects.BARS_PATH] = projects.RPP_TIME } })
      assert.are.equal("ok", capture.run(capture.prepare(given), { name = "Live" }).status)
    end)
  end)
end)
