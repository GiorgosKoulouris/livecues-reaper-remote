local undo = require("lib.undo")
local fake_reaper = require("spec.support.fake_reaper")

describe("undo.run", function()
  it("wraps the applier in exactly one undo block", function()
    local api = fake_reaper.new()
    undo.run({ api = api, description = "LCRR Arrange: Repack Regions", apply = function() end })

    assert.are.same({ "Undo_BeginBlock", "Undo_EndBlock" }, api.call_names())
  end)

  it("labels the undo point with the description", function()
    local api = fake_reaper.new()
    undo.run({ api = api, description = "LCRR Arrange: Repack Regions", apply = function() end })

    assert.are.equal("LCRR Arrange: Repack Regions", api.calls_to("Undo_EndBlock")[1].args[1])
  end)

  it("opens the block before the applier runs and closes it after", function()
    local api = fake_reaper.new()
    local order = {}
    undo.run({
      api = api,
      description = "d",
      apply = function() order[#order + 1] = "apply" end,
    })

    assert.are.same({ "Undo_BeginBlock", "Undo_EndBlock" }, api.call_names())
    assert.are.same({ "apply" }, order)
  end)

  it("returns what the applier returned", function()
    local api = fake_reaper.new()
    local result = undo.run({ api = api, description = "d", apply = function() return "done" end })
    assert.are.equal("done", result)
  end)

  -- An empty plan creates no undo point at all (CLAUDE.md, Undo convention).
  it("creates no undo point when the plan is empty", function()
    local api = fake_reaper.new()
    local applied = false
    undo.run({
      api = api,
      description = "d",
      skip = true,
      apply = function() applied = true end,
    })

    assert.are.same({}, api.call_names())
    assert.is_false(applied)
  end)

  -- Leaving a block open would swallow the user's next edit into our undo point.
  it("closes the block even when the applier raises", function()
    local api = fake_reaper.new()
    local ok = pcall(undo.run, {
      api = api,
      description = "d",
      apply = function() error("boom") end,
    })

    assert.is_false(ok)
    assert.are.same({ "Undo_BeginBlock", "Undo_EndBlock" }, api.call_names())
  end)

  it("re-raises the applier's error after closing the block", function()
    local api = fake_reaper.new()
    local _, err = pcall(undo.run, {
      api = api,
      description = "d",
      apply = function() error("boom", 0) end,
    })

    assert.are.equal("boom", err)
  end)
end)
