local bulk = require("lib.core.bulk")
local service = require("lib.bridge.service")
local fake_project = require("spec.support.fake_project")

-- Kick -> A (0.5, pre-fader mode 0 on purpose), Snare -> A and B, Vox -> nothing.
local function band()
  return fake_project.new({ tracks = {
    { name = "Kick", guid = "{K}" },
    { name = "Snare", guid = "{S}" },
    { name = "Vox", guid = "{V}" },
    { name = "IEMs", guid = "{F}", depth = 1 },
    { name = "IEM_A", guid = "{A}",
      receives = { { from = "Kick", vol = 0.5, mode = 0 }, { from = "Snare", vol = 0.25, mode = 3 } } },
    { name = "IEM_B", guid = "{B}", depth = -1, receives = { { from = "Snare", vol = 0.7, mode = 3 } } },
  } })
end

local function row(api, source, on) return bulk.row.run({ api = api, fields = { source = source, on = on } }) end
local function column(api, mix, on) return bulk.column.run({ api = api, fields = { mix = mix, on = on } }) end

local function one_step(api, description)
  assert.are.same({}, api.outside_block)
  assert.are.equal(0, api.open_blocks)
  assert.are.same({ description }, api.undo_steps)
end

local function untouched(api)
  assert.are.same({}, api.undo_steps)
  assert.are.same({}, api.outside_block)
end

describe("row", function()
  it("on adds only the missing sends and leaves existing ones alone", function()
    local api = band()
    assert.are.same({ status = "ok", changed = true, count = 1 }, row(api, "{K}", "1"))
    local a, b = api.tracks[5].receives, api.tracks[6].receives
    assert.are.equal(2, #a)
    assert.are.equal(0.5, a[1].vol)
    assert.are.equal(0, a[1].mode)
    assert.are.equal(2, #b)
    assert.are.equal(api.tracks[1], b[2].src_track)
    assert.are.equal(3, b[2].mode)
    assert.are.equal(1.0, b[2].vol)
    one_step(api, "IEM Setup: switch row on")
  end)

  it("on a full row does nothing, with no undo step", function()
    local api = band()
    assert.are.same({ status = "ok", changed = false, count = 0 }, row(api, "{S}", "1"))
    untouched(api)
  end)

  it("on an empty row feeds every mix, a stray included", function()
    local api = band()
    api.CreateTrackSend(api.tracks[3], api.tracks[5])
    api.undo_steps, api.outside_block = {}, {}
    assert.are.equal(1, row(api, "{V}", "1").count)
    assert.are.equal(3, #api.tracks[5].receives)
    assert.are.equal(2, #api.tracks[6].receives)
  end)

  it("off removes the source's sends to every mix, keeps other sources, one undo step", function()
    local api = band()
    api.CreateTrackSend(api.tracks[2], api.tracks[5])
    api.undo_steps, api.outside_block = {}, {}
    assert.are.same({ status = "ok", changed = true, count = 3 }, row(api, "{S}", "0"))
    assert.are.equal(1, #api.tracks[5].receives)
    assert.are.equal(api.tracks[1], api.tracks[5].receives[1].src_track)
    assert.are.same({}, api.tracks[6].receives)
    assert.are.same({}, api.tracks[2].sends)
    one_step(api, "IEM Setup: switch row off")
  end)

  it("off on an empty row does nothing, with no undo step", function()
    local api = band()
    assert.are.same({ status = "ok", changed = false, count = 0 }, row(api, "{V}", "0"))
    untouched(api)
  end)

  it("refuses a gone track, a mix and the folder, and leaves the history alone", function()
    local api = band()
    assert.are.same({ status = "refused", error = { code = "track_gone" } }, row(api, "{X}", "1"))
    assert.are.same({ status = "refused", error = { code = "not_a_source" } }, row(api, "{A}", "1"))
    assert.are.same({ status = "refused", error = { code = "not_a_source" } }, row(api, "{F}", "0"))
    untouched(api)
  end)
end)

describe("column", function()
  it("on adds only the missing sends, post-FX pre-fader at 0 dB, and leaves existing ones alone", function()
    local api = band()
    assert.are.same({ status = "ok", changed = true, count = 2 }, column(api, "{B}", "1"))
    local b = api.tracks[6].receives
    assert.are.equal(3, #b)
    assert.are.equal(0.7, b[1].vol)
    assert.are.equal(api.tracks[1], b[2].src_track)
    assert.are.equal(api.tracks[3], b[3].src_track)
    assert.are.equal(3, b[2].mode)
    assert.are.equal(1.0, b[3].vol)
    assert.are.equal(2, #api.tracks[5].receives)
    one_step(api, "IEM Setup: switch column on")
  end)

  it("never feeds a mix from another mix or the folder", function()
    local api = band()
    column(api, "{A}", "1")
    for _, receive in ipairs(api.tracks[5].receives) do
      assert.are_not.equal(api.tracks[6], receive.src_track)
      assert.are_not.equal(api.tracks[4], receive.src_track)
    end
    assert.are.equal(3, #api.tracks[5].receives)
  end)

  it("off removes every send to the mix from the sources, keeps the mix's own sends, one undo step", function()
    local api = band()
    api.CreateTrackSend(api.tracks[2], api.tracks[5])
    api.CreateTrackSend(api.tracks[6], api.tracks[5])
    api.undo_steps, api.outside_block = {}, {}
    assert.are.same({ status = "ok", changed = true, count = 3 }, column(api, "{A}", "0"))
    assert.are.equal(1, #api.tracks[5].receives)
    assert.are.equal(api.tracks[6], api.tracks[5].receives[1].src_track)
    assert.are.equal(1, #api.tracks[6].receives)
    one_step(api, "IEM Setup: switch column off")
  end)

  it("does nothing when already as asked", function()
    local api = band()
    column(api, "{A}", "0")
    api.undo_steps, api.outside_block = {}, {}
    assert.are.same({ status = "ok", changed = false, count = 0 }, column(api, "{A}", "0"))
    untouched(api)
    column(api, "{A}", "1")
    api.undo_steps, api.outside_block = {}, {}
    assert.are.same({ status = "ok", changed = false, count = 0 }, column(api, "{A}", "1"))
    untouched(api)
  end)

  it("refuses a gone track and a track that is not a mix", function()
    local api = band()
    assert.are.same({ status = "refused", error = { code = "track_gone" } }, column(api, "{X}", "1"))
    assert.are.same({ status = "refused", error = { code = "not_a_mix" } }, column(api, "{K}", "1"))
    assert.are.same({ status = "refused", error = { code = "not_a_mix" } }, column(api, "{F}", "0"))
    untouched(api)
  end)
end)

it("row and column are commands on the bridge", function()
  local api = band()
  local handler = service.new({ api = api })
  local body = "cmd=row&source=%7BV%7D&on=1"
  local _, reply = handler.handle(("q1|%d|%s"):format(#body, body))
  assert.is_truthy(reply:find('"count":2', 1, true))
  body = "cmd=column&mix=%7BB%7D&on=0"
  _, reply = handler.handle(("q2|%d|%s"):format(#body, body))
  assert.is_truthy(reply:find('"changed":true', 1, true))
  assert.are.equal(0, #api.tracks[6].receives)
end)
