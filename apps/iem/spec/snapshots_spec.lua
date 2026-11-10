local service = require("lib.bridge.service")
local snapshots = require("lib.core.snapshots")
local snapshot_save = require("lib.core.snapshot_save")
local snapshot_delete = require("lib.core.snapshot_delete")
local snapshot_recall = require("lib.core.snapshot_recall")
local store = require("lib.core.snapshot_store")
local fake_project = require("spec.support.fake_project")

local clock = 1700000000

local function band()
  return fake_project.new({
    path = "C:/Shows/Gig.rpp",
    tracks = {
      { name = "Kick", guid = "{K}" },
      { name = "Vox", guid = "{V}" },
      { name = "IEMs", depth = 1 },
      { name = "IEM_A", guid = "{A}", outputs = { { dest = 0, vol = 0.5 } },
        receives = { { from = "Kick", vol = 0.5, pan = -0.25, mode = 3 }, { from = "Vox", vol = 1.5, muted = true } } },
      { name = "IEM_B", guid = "{B}", depth = -1, outputs = { { dest = 2 } },
        receives = { { from = "Vox", vol = 0.25, pan = 1 } } },
    },
  })
end

local function save(api, name, overwrite)
  clock = clock + 60
  return snapshot_save.run({ api = api, fields = { name = name, overwrite = overwrite and "1" or nil },
    now = function() return clock end })
end

local function delete(api, name) return snapshot_delete.run({ api = api, fields = { name = name } }) end
local function list(api) return snapshots.run({ api = api }).snapshots end
local function code(reply) return reply.status == "refused" and reply.error.code or reply.status end

local function no_undo(api)
  assert.are.same({}, api.outside_block)
  assert.are.equal(0, api.open_blocks)
  assert.are.same({}, api.undo_steps)
end

describe("snapshots", function()
  before_each(function() clock = 1700000000 end)

  it("lists nothing at first", function()
    assert.are.same({ status = "ok", snapshots = {} }, snapshots.run({ api = band() }))
  end)

  describe("save", function()
    it("stores every send's level, pan and mute and each mix's master, by GUID", function()
      local api = band()
      local reply = save(api, "Soundcheck")
      assert.are.same({ status = "ok", name = "Soundcheck", overwritten = false, mixes = 2, sends = 3 }, reply)
      local entry = store.find(store.list(api), "Soundcheck")
      assert.are.same({
        { guid = "{A}", master = 0.5, sends = {
          { source = "{K}", vol = 0.5, pan = -0.25, muted = false },
          { source = "{V}", vol = 1.5, pan = 0, muted = true } } },
        { guid = "{B}", master = 1, sends = { { source = "{V}", vol = 0.25, pan = 1, muted = false } } },
      }, store.read(api, entry).mixes)
    end)

    it("lists it with its counts and when it was saved, never its contents", function()
      local api = band()
      save(api, "Soundcheck")
      assert.are.same({ { name = "Soundcheck", saved = 1700000060, mixes = 2, sends = 3 } }, list(api))
    end)

    it("opens no undo block and adds no undo step", function()
      local api = band()
      save(api, "Soundcheck")
      save(api, "Soundcheck", true)
      delete(api, "Soundcheck")
      no_undo(api)
      assert.is_true(api.ext_writes > 0)
    end)

    it("trims the name and keeps the list in save order", function()
      local api = band()
      assert.are.equal("Show", save(api, "  Show \t").name)
      save(api, "Encore")
      assert.are.same({ "Show", "Encore" }, { list(api)[1].name, list(api)[2].name })
    end)

    it("keeps a name with a comma, a semicolon and a percent sign whole", function()
      local api = band()
      save(api, "A,B;C%D")
      assert.are.equal("A,B;C%D", list(api)[1].name)
    end)

    it("takes a mix with no output (no master) and leaves out a mix with no sends", function()
      local api = fake_project.new({ tracks = {
        { name = "Kick", guid = "{K}" },
        { name = "IEM_A", guid = "{A}", receives = { { from = "Kick" } } },
        { name = "IEM_Empty", guid = "{E}" },
      } })
      assert.are.equal(1, save(api, "S").mixes)
      assert.is_nil(store.read(api, store.list(api)[1]).mixes[1].master)
    end)
  end)

  describe("overwrite", function()
    it("replaces the contents, keeps the place and the name, and refreshes the time", function()
      local api = band()
      save(api, "One")
      save(api, "Two")
      api.tracks[4].receives[1].vol = 0.9
      local reply = save(api, "One", true)
      assert.is_true(reply.overwritten)
      local entries = store.list(api)
      assert.are.same({ "One", "Two" }, { entries[1].name, entries[2].name })
      assert.are.equal(1700000180, entries[1].saved)
      assert.are.equal(0.9, store.read(api, entries[1]).mixes[1].sends[1].vol)
      assert.are.equal(0.5, store.read(api, entries[2]).mixes[1].sends[1].vol)
    end)
  end)

  describe("delete", function()
    it("removes the snapshot and its contents, and leaves the others", function()
      local api = band()
      save(api, "One")
      save(api, "Two")
      local gone = store.list(api)[1]
      assert.are.same({ status = "ok" }, delete(api, "One"))
      assert.are.equal(1, #list(api))
      assert.are.equal("Two", list(api)[1].name)
      assert.is_nil(store.read(api, gone))
      no_undo(api)
    end)

    it("gives a later save a fresh id", function()
      local api = band()
      save(api, "One")
      save(api, "Two")
      delete(api, "Two")
      save(api, "Three")
      assert.are.same({ 1, 2 }, { store.list(api)[1].id, store.list(api)[2].id })
    end)
  end)

  describe("a name refused", function()
    it("refuses an empty name, a name with a control character and one that is too long", function()
      local api = band()
      assert.are.equal("empty_name", code(save(api, "   ")))
      assert.are.equal("bad_name", code(save(api, "a\nb")))
      assert.are.equal("name_too_long", code(save(api, ("x"):rep(41))))
      assert.are.equal("ok", code(save(api, ("é"):rep(40))))
      assert.are.equal("empty_name", code(delete(api, " ")))
    end)

    it("refuses a name already taken, case-sensitively, unless overwriting", function()
      local api = band()
      save(api, "Show")
      assert.are.equal("duplicate_name", code(save(api, " Show ")))
      assert.are.equal("ok", code(save(api, "show")))
      assert.are.equal(2, #list(api))
    end)

    it("refuses an overwrite or a delete of a name that is not saved", function()
      local api = band()
      assert.are.equal("not_found", code(save(api, "Nope", true)))
      assert.are.equal("not_found", code(delete(api, "Nope")))
    end)

    it("refuses to save when no mix has a send, and writes nothing", function()
      local api = fake_project.new({ tracks = { { name = "Kick" } } })
      assert.are.equal("nothing_to_save", code(save(api, "S")))
      assert.are.equal(0, api.ext_writes)
    end)

    it("refuses everything when the stored list cannot be read, and leaves it alone", function()
      local api = band()
      api.ext["LCRR_IEM/snapshots"] = "garbage"
      assert.are.equal("unreadable", code(snapshots.run({ api = api })))
      assert.are.equal("unreadable", code(save(api, "S")))
      assert.are.equal("unreadable", code(delete(api, "S")))
      assert.are.equal("garbage", api.ext["LCRR_IEM/snapshots"])
    end)
  end)

  describe("a large snapshot", function()
    local function big()
      local tracks, mixes, sources = {}, 12, 120
      for n = 1, sources do tracks[#tracks + 1] = { name = "Src" .. n, guid = ("{S%d}"):format(n) } end
      for m = 1, mixes do
        local receives = {}
        for n = 1, sources do
          receives[n] = { from = "Src" .. n, vol = n / 7, pan = (n % 5) / 5 - 0.4, muted = n % 9 == 0 }
        end
        tracks[#tracks + 1] = { name = "IEM_Mix" .. m, guid = ("{M%d}"):format(m),
          outputs = { { dest = 0, vol = 0.3 } }, receives = receives }
      end
      return fake_project.new({ tracks = tracks })
    end

    it("saves, lists, reads back exactly and deletes, with a reply that stays small", function()
      local api = big()
      local reply = save(api, "Big")
      assert.are.same({ 12, 1440 }, { reply.mixes, reply.sends })
      local body = api.ext["LCRR_IEM/snapshot." .. store.list(api)[1].id]
      assert.is_true(#body > 60000)
      assert.is_nil(body:find("\n", 1, true))
      assert.are.equal(#("Big"), #list(api)[1].name)
      local contents = store.read(api, store.list(api)[1])
      assert.are.equal(12, #contents.mixes)
      assert.are.equal(120, #contents.mixes[12].sends)
      assert.are.same({ source = "{S7}", vol = 1, pan = -0.4 + 2 / 5, muted = false }, contents.mixes[3].sends[7])

      local handler = service.new({ api = api })
      local _, listed = handler.handle("q1|13|cmd=snapshots")
      local _, saved = handler.handle("q2|38|cmd=snapshot_save&name=Big&overwrite=1")
      assert.is_true(#listed < 400)
      assert.is_true(#saved < 400)
      assert.are.equal("ok", code(delete(api, "Big")))
      assert.are.same({}, list(api))
    end)
  end)

  describe("recall", function()
    local function recall(api, name, mix)
      return snapshot_recall.run({ api = api, fields = { name = name, mix = mix } })
    end
    -- The state after a save, then everything moved.
    local function moved()
      local api = band()
      save(api, "Show")
      for _, t in ipairs({ api.tracks[4], api.tracks[5] }) do
        for _, r in ipairs(t.receives) do r.vol, r.pan, r.muted = 0.11, 0.5, not r.muted end
        t.outputs[1].vol = 0.9
      end
      return api
    end
    local function sends_of(track)
      local out = {}
      for _, r in ipairs(track.receives) do out[#out + 1] = { r.from, r.vol, r.pan or 0, r.muted or false } end
      return out
    end

    it("puts level, pan, mute and master of the whole band back, as one undo step", function()
      local api = moved()
      assert.are.same({ status = "ok", name = "Show", mixes = 2, sends = 3, skipped = 0, missing = 0 },
        recall(api, "Show"))
      assert.are.same({ { "Kick", 0.5, -0.25, false }, { "Vox", 1.5, 0, true } }, sends_of(api.tracks[4]))
      assert.are.same({ { "Vox", 0.25, 1, false } }, sends_of(api.tracks[5]))
      assert.are.same({ 0.5, 1 }, { api.tracks[4].outputs[1].vol, api.tracks[5].outputs[1].vol or 1 })
      assert.are.same({ "IEM Mix: recall snapshot Show" }, api.undo_steps)
      assert.are.same({}, api.outside_block)
      assert.are.equal(0, api.open_blocks)
    end)

    it("recalls one mix and leaves every other mix untouched", function()
      local api = moved()
      local reply = recall(api, "Show", "{B}")
      assert.are.same({ 1, 1, 0, 0 }, { reply.mixes, reply.sends, reply.skipped, reply.missing })
      assert.are.same({ { "Vox", 0.25, 1, false } }, sends_of(api.tracks[5]))
      assert.are.same({ { "Kick", 0.11, 0.5, true }, { "Vox", 0.11, 0.5, false } }, sends_of(api.tracks[4]))
      assert.are.equal(0.9, api.tracks[4].outputs[1].vol)
      assert.are.equal(1, #api.undo_steps)
    end)

    it("skips a send whose source is gone or whose pair is no longer routed, and counts it", function()
      local api = moved()
      table.remove(api.tracks[4].receives, 1) -- Kick no longer routed to A
      local reply = recall(api, "Show")
      assert.are.same({ 2, 2, 1, 0 }, { reply.mixes, reply.sends, reply.skipped, reply.missing })
      assert.are.same({ { "Vox", 1.5, 0, true } }, sends_of(api.tracks[4]))
    end)

    it("leaves a send added since the save alone", function()
      local api = moved()
      api.tracks[4].receives[#api.tracks[4].receives + 1] = { from = "Vox", vol = 0.77, pan = 0.3,
        src_track = api.tracks[2], dest = api.tracks[4] }
      local reply = recall(api, "Show")
      assert.are.same({ 3, 0 }, { reply.sends, reply.skipped })
      local added = api.tracks[4].receives[3]
      assert.are.same({ 0.77, 0.3 }, { added.vol, added.pan })
    end)

    it("counts a mix that has gone, with its sends, and recalls the rest", function()
      local api = moved()
      table.remove(api.tracks, 5)
      local reply = recall(api, "Show")
      assert.are.same({ 1, 2, 1, 1 }, { reply.mixes, reply.sends, reply.skipped, reply.missing })
    end)

    it("skips the master level of a mix whose hardware output is gone, and counts it", function()
      local api = moved()
      api.tracks[4].outputs = {}
      local reply = recall(api, "Show")
      assert.are.same({ 2, 3, 1, 0 }, { reply.mixes, reply.sends, reply.skipped, reply.missing })
      assert.are.equal(1, #api.undo_steps)
    end)

    it("skips a mix that was renamed away from IEM_", function()
      local api = moved()
      api.tracks[5].name = "Drums"
      assert.are.equal(1, recall(api, "Show").missing)
    end)

    it("skips every send when the sources are gone, and makes no undo step when nothing is written", function()
      local api = fake_project.new({ tracks = {
        { name = "Kick", guid = "{K}" }, { name = "IEM_A", guid = "{A}", receives = { { from = "Kick" } } } } })
      save(api, "S")
      api.tracks[2].receives = {}
      api.tracks[1].sends = {}
      local reply = recall(api, "S")
      assert.are.same({ 0, 0, 1 }, { reply.mixes, reply.sends, reply.skipped })
      assert.are.same({}, api.undo_steps)
    end)

    it("refuses a mix that is gone or not a mix, and one the snapshot never held, writing nothing", function()
      local api = moved()
      assert.are.equal("track_gone", code(recall(api, "Show", "{NOPE}")))
      assert.are.equal("not_a_mix", code(recall(api, "Show", "{K}")))
      api.tracks[#api.tracks + 1] = { name = "IEM_New", guid = "{N}", depth = 0, main_send = 1, outputs = {},
        receives = {}, sends = {} }
      assert.are.equal("mix_not_saved", code(recall(api, "Show", "{N}")))
      assert.are.same({}, api.undo_steps)
    end)

    it("refuses a name that is not saved, a bad name and unreadable storage, writing nothing", function()
      local api = moved()
      assert.are.equal("not_found", code(recall(api, "Nope")))
      assert.are.equal("empty_name", code(recall(api, " ")))
      api.ext["LCRR_IEM/snapshot.1"] = "garbage"
      assert.are.equal("unreadable", code(recall(api, "Show")))
      api.ext["LCRR_IEM/snapshots"] = "garbage"
      assert.are.equal("unreadable", code(recall(api, "Show")))
      assert.are.same({}, api.undo_steps)
    end)

    it("leaves the stored snapshot as it was and recalls it again", function()
      local api = moved()
      recall(api, "Show")
      api.tracks[4].receives[1].vol = 0.3
      recall(api, "Show")
      assert.are.equal(0.5, api.tracks[4].receives[1].vol)
      assert.are.equal(2, #api.undo_steps)
    end)

    it("answers through the service", function()
      local api = moved()
      local handler = service.new({ api = api })
      local _, reply = handler.handle("q1|41|cmd=snapshot_recall&name=Show&mix=%7BB%7D")
      assert.is_truthy(reply:find('"status":"ok"', 1, true))
      assert.is_truthy(reply:find('"sends":1', 1, true))
    end)
  end)

  it("answers through the service", function()
    local handler = service.new({ api = band(), now = function() return 5 end })
    local _, saved = handler.handle("q1|26|cmd=snapshot_save&name=One")
    assert.is_truthy(saved:find('"status":"ok"', 1, true))
    local _, listed = handler.handle("q2|13|cmd=snapshots")
    assert.is_truthy(listed:find('"saved":5', 1, true))
  end)
end)
