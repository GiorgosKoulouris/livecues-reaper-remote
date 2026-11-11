local cue = require("lib.core.cue")
local create = require("lib.core.create")
local adopt = require("lib.core.adopt")
local cell = require("lib.core.cell")
local bulk = require("lib.core.bulk")
local output = require("lib.core.output")
local state = require("lib.core.state")
local service = require("lib.bridge.service")
local fake_project = require("spec.support.fake_project")

local function band()
  return fake_project.new({
    device = { "Output 1", "Output 2", "Output 3", "Output 4" },
    tracks = {
      { name = "Kick", guid = "{K}" },
      { name = "IEMs", guid = "{F}", depth = 1 },
      { name = "IEM_A", guid = "{A}" },
      { name = "IEM_B", guid = "{B}", depth = -1 },
    },
  })
end

local function names(api)
  local out = {}
  for _, track in ipairs(api.tracks) do out[#out + 1] = track.name end
  return out
end

local function depths(api)
  local out = {}
  for _, track in ipairs(api.tracks) do out[#out + 1] = track.depth end
  return out
end

local function cue_track(api)
  for _, track in ipairs(api.tracks) do
    if track.name == "IEM-Cue" then return track end
  end
end

local function one_undo_step(api, description)
  assert.are.same({}, api.outside_block)
  assert.are.equal(0, api.open_blocks)
  assert.are.same({ description }, api.undo_steps)
end

describe("cue", function()
  describe("create", function()
    it("makes IEM-Cue last in the IEMs folder, master off, with a silent post-fader send from every mix", function()
      local api = band()
      local reply = cue.run({ api = api })
      assert.are.equal("ok", reply.status)
      assert.is_true(reply.changed)
      assert.is_true(reply.created)
      assert.are.equal(2, reply.added)
      assert.are.same({ "Kick", "IEMs", "IEM_A", "IEM_B", "IEM-Cue" }, names(api))
      assert.are.same({ 0, 1, 0, 0, -1 }, depths(api))
      local track = cue_track(api)
      assert.are.equal(0, track.main_send)
      assert.are.equal(reply.guid, track.guid)
      assert.are.equal(2, #track.receives)
      for _, receive in ipairs(track.receives) do
        assert.are.equal(0, receive.vol)
        assert.are.equal(0, receive.mode)
      end
      one_undo_step(api, "IEM Setup: create cue")
    end)

    it("makes the folder first when there is none", function()
      local api = fake_project.new({ tracks = { { name = "Kick" }, { name = "IEM_A", guid = "{A}" } } })
      cue.run({ api = api })
      assert.are.same({ "Kick", "IEM_A", "IEMs", "IEM-Cue" }, names(api))
      assert.are.same({ 0, 0, 1, -1 }, depths(api))
      assert.are.equal(1, #cue_track(api).receives)
    end)

    it("makes a cue track with no mixes yet", function()
      local api = fake_project.new({ tracks = { { name = "Kick" } } })
      local reply = cue.run({ api = api })
      assert.are.equal(0, reply.added)
      assert.is_not_nil(cue_track(api))
    end)
  end)

  describe("run again", function()
    it("does nothing and leaves no undo step when nothing is missing", function()
      local api = band()
      cue.run({ api = api })
      local reply = cue.run({ api = api })
      assert.is_false(reply.changed)
      assert.is_false(reply.created)
      assert.are.equal(2, #cue_track(api).receives)
      assert.are.equal(1, #api.undo_steps)
      assert.are.equal(5, #api.tracks)
    end)

    it("adds only the send a mix is missing, keeping the others as they are", function()
      local api = band()
      cue.run({ api = api })
      local track = cue_track(api)
      track.receives[1].vol = 0.7
      table.remove(track.receives, 2)
      table.remove(api.tracks[4].sends, 1)
      local reply = cue.run({ api = api })
      assert.is_true(reply.changed)
      assert.is_false(reply.created)
      assert.are.equal(1, reply.added)
      assert.are.equal(2, #track.receives)
      assert.are.equal(0.7, track.receives[1].vol)
      assert.are.equal(2, #api.undo_steps)
    end)
  end)

  describe("colour", function()
    it("a repair puts the cue track back on the shared colour; the colour command recolours it too", function()
      local colour = require("lib.core.colour")
      local api = band()
      cue.run({ api = api })
      local want = cue_track(api).colour
      assert.are_not.equal(0, want)
      cue_track(api).colour = 0
      cue_track(api).solo_defeat = 0 -- something to repair, so the run is not a no-op
      cue.run({ api = api })
      assert.are.equal(want, cue_track(api).colour)
      colour.run({ api = api, fields = { colour = "ff8000" } })
      assert.are.equal(api.tracks[2].colour, cue_track(api).colour)
      assert.are_not.equal(want, cue_track(api).colour)
    end)
  end)

  describe("solo defeat", function()
    it("is on for the cue track and every mix once the cue is made", function()
      local api = band()
      local reply = cue.run({ api = api })
      assert.are.equal(3, reply.protected)
      assert.are.equal(1, cue_track(api).solo_defeat)
      assert.are.equal(1, api.tracks[3].solo_defeat)
      assert.are.equal(1, api.tracks[4].solo_defeat)
      assert.is_nil(api.tracks[1].solo_defeat)
    end)

    it("is repaired by running the cue again, in one undo step, and then there is nothing to do", function()
      local api = band()
      cue.run({ api = api })
      api.tracks[4].solo_defeat = 0
      cue_track(api).solo_defeat = 0
      api.undo_steps = {}
      local reply = cue.run({ api = api })
      assert.is_true(reply.changed)
      assert.is_false(reply.created)
      assert.are.equal(0, reply.added)
      assert.are.equal(2, reply.protected)
      one_undo_step(api, "IEM Setup: create cue")
      api.undo_steps = {}
      assert.is_false(cue.run({ api = api }).changed)
      assert.are.same({}, api.undo_steps)
    end)

    it("adopt turns it on for the stray", function()
      local api = fake_project.new({ tracks = { { name = "IEM_X", guid = "{X}" } } })
      adopt.run({ api = api, fields = { guid = "{X}" } })
      assert.are.equal(1, api.tracks[2].solo_defeat)
      assert.are.same({ "IEMs", "IEM_X", "IEM-Cue" }, names(api))
    end)

    it("state counts the mixes and the cue track that lack it", function()
      local api = band()
      cue.run({ api = api })
      assert.are.equal(0, state.run({ api = api }).cue.unprotected)
      api.tracks[4].solo_defeat = 0
      cue_track(api).solo_defeat = 0
      assert.are.equal(2, state.run({ api = api }).cue.unprotected)
    end)
  end)

  describe("a mix added later", function()
    it("create gives the new mix its cue send in the same undo step", function()
      local api = band()
      cue.run({ api = api })
      api.undo_steps = {}
      local reply = create.run({ api = api, fields = { name = "C" } })
      assert.are.equal("ok", reply.status)
      assert.are.same({ "Kick", "IEMs", "IEM_A", "IEM_B", "IEM-Cue", "IEM_C" }, names(api))
      assert.are.equal(3, #cue_track(api).receives)
      local last = cue_track(api).receives[3]
      assert.are.equal(0, last.vol)
      assert.are.equal(0, last.mode)
      one_undo_step(api, "IEM Setup: create mix")
    end)

    it("create with copy does too, and does not copy a cue send", function()
      local api = band()
      cell.run({ api = api, fields = { source = "{K}", mix = "{A}", on = "1" } })
      cue.run({ api = api })
      api.undo_steps = {}
      create.run({ api = api, fields = { name = "C", copy = "{A}" } })
      local mix
      for _, track in ipairs(api.tracks) do if track.name == "IEM_C" then mix = track end end
      assert.are.equal(1, #mix.receives)
      assert.are.equal(3, #cue_track(api).receives)
      one_undo_step(api, "IEM Setup: create mix")
    end)

    it("create makes the cue track when there is none, with the mix's send and solo defeat, in one step", function()
      local api = band()
      create.run({ api = api, fields = { name = "C" } })
      local track = cue_track(api)
      assert.is_not_nil(track)
      assert.are.same({ "Kick", "IEMs", "IEM_A", "IEM_B", "IEM_C", "IEM-Cue" }, names(api))
      assert.are.equal(3, #track.receives)
      assert.are.equal(1, track.solo_defeat)
      for _, t in ipairs(api.tracks) do
        if t.name:sub(1, 4) == "IEM_" then assert.are.equal(1, t.solo_defeat) end
      end
      one_undo_step(api, "IEM Setup: create mix")
    end)

    it("create gives the first mix of a project its folder, cue track, send and solo defeat", function()
      local api = fake_project.new({ tracks = { { name = "Kick" } } })
      create.run({ api = api, fields = { name = "A" } })
      assert.are.same({ "Kick", "IEMs", "IEM_A", "IEM-Cue" }, names(api))
      assert.are.same({ 0, 1, 0, -1 }, depths(api))
      assert.are.equal(1, api.tracks[3].solo_defeat)
      assert.are.equal(1, #cue_track(api).receives)
      one_undo_step(api, "IEM Setup: create mix")
    end)

    it("create turns solo defeat on for the new mix only when the cue track exists", function()
      local api = band()
      cue.run({ api = api })
      api.tracks[3].solo_defeat = 0
      create.run({ api = api, fields = { name = "C" } })
      local mix
      for _, track in ipairs(api.tracks) do if track.name == "IEM_C" then mix = track end end
      assert.are.equal(1, mix.solo_defeat)
      assert.are.equal(0, api.tracks[3].solo_defeat)
    end)

    it("adopt gives a stray its cue send in the same undo step", function()
      local api = fake_project.new({
        tracks = {
          { name = "Kick", guid = "{K}" },
          { name = "IEMs", depth = 1 },
          { name = "IEM-Cue", depth = -1, guid = "{Q}" },
          { name = "IEM_S", guid = "{S}", receives = { { from = "Kick", vol = 1, mode = 0 } } },
        },
      })
      assert.are.equal("ok", adopt.run({ api = api, fields = { guid = "{S}" } }).status)
      assert.are.equal(1, #cue_track(api).receives)
      assert.are.equal(0, cue_track(api).receives[1].vol)
      assert.are.same({ "IEM Setup: adopt mix" }, api.undo_steps)
      assert.are.same({}, api.outside_block)
    end)

    it("adopt does not add a second send when the stray already has one", function()
      local api = fake_project.new({
        tracks = {
          { name = "IEMs", depth = 1 },
          { name = "IEM-Cue", depth = -1, guid = "{Q}" },
          { name = "IEM_S", guid = "{S}" },
        },
      })
      cue.run({ api = api })
      adopt.run({ api = api, fields = { guid = "{S}" } })
      assert.are.equal(1, #cue_track(api).receives)
    end)
  end)

  describe("the cue track is no source", function()
    local function with_cue()
      local api = band()
      cue.run({ api = api })
      return api, cue_track(api).guid
    end

    it("cell refuses it as a source, adds no send, no undo step", function()
      local api, guid = with_cue()
      local steps = #api.undo_steps
      local reply = cell.run({ api = api, fields = { source = guid, mix = "{A}", on = "1" } })
      assert.are.same({ status = "refused", error = { code = "not_a_source" } }, reply)
      assert.are.equal(steps, #api.undo_steps)
      assert.are.equal(0, #api.tracks[3].receives)
    end)

    it("row refuses it, and a column on adds nothing from it", function()
      local api, guid = with_cue()
      assert.are.equal("not_a_source", bulk.row.run({ api = api, fields = { source = guid, on = "1" } }).error.code)
      bulk.column.run({ api = api, fields = { mix = "{A}", on = "1" } })
      assert.are.equal(1, #api.tracks[3].receives)
      assert.are.equal("{K}", api.tracks[3].receives[1].src_track.guid)
      assert.are.equal(0, #cue_track(api).sends)
    end)

    it("is not a mix, so nothing can be sent into it as a mix", function()
      local api, guid = with_cue()
      local reply = cell.run({ api = api, fields = { source = "{A}", mix = guid, on = "1" } })
      assert.are.equal("not_a_mix", reply.error.code)
    end)

    it("is not listed in state's sources, nor among its mixes", function()
      local api = with_cue()
      local reply = state.run({ api = api })
      assert.are.equal(1, #reply.sources)
      assert.are.equal(2, #reply.mixes)
      assert.are.same({ guid = cue_track(api).guid, outputs = {}, missing = 0, unprotected = 0 }, reply.cue)
    end)

    it("a second track with the same name is an ordinary source", function()
      local api = band()
      cue.run({ api = api })
      local real = cue_track(api)
      api.tracks[1].name = "IEM-Cue" -- now first in project order, so it is the cue and the old one is not
      local ok = cell.run({ api = api, fields = { source = real.guid, mix = "{A}", on = "1" } })
      assert.are.equal("ok", ok.status)
      assert.are.equal("not_a_source",
        cell.run({ api = api, fields = { source = "{K}", mix = "{A}", on = "1" } }).error.code)
    end)
  end)

  describe("state", function()
    it("has no cue field when there is none", function()
      assert.is_nil(state.run({ api = band() }).cue)
    end)

    it("reports the cue's output and how many mixes lack a send", function()
      local api = band()
      cue.run({ api = api })
      table.remove(cue_track(api).receives, 1)
      table.remove(api.tracks[3].sends, 1)
      cue_track(api).outputs = { { dest = 2 | 1024 } }
      local reply = state.run({ api = api })
      assert.are.same({ { channel = 2, mono = true } }, reply.cue.outputs)
      assert.are.equal(1, reply.cue.missing)
    end)

    it("leaves the mixes' own entries as they are without a cue", function()
      local without = state.run({ api = band() })
      local api = band()
      cue.run({ api = api })
      assert.are.same(without.mixes, state.run({ api = api }).mixes)
    end)
  end)

  describe("output on the cue track", function()
    it("sets and clears its hardware output, one undo step each", function()
      local api = band()
      cue.run({ api = api })
      local guid = cue_track(api).guid
      api.undo_steps = {}
      local reply = output.run({ api = api, fields = { guid = guid, channel = "2", mono = "0" } })
      assert.are.same({ status = "ok", changed = true }, reply)
      assert.are.same({ { dest = 2, src = 0 } }, cue_track(api).outputs)
      one_undo_step(api, "IEM Setup: set output")
      output.run({ api = api, fields = { guid = guid, channel = "none" } })
      assert.are.same({}, cue_track(api).outputs)
    end)

    it("still refuses a source, the folder and a gone track", function()
      local api = band()
      cue.run({ api = api })
      for _, guid in ipairs({ "{K}", "{F}" }) do
        assert.are.equal("not_a_mix", output.run({ api = api, fields = { guid = guid, channel = "none" } }).error.code)
      end
      assert.are.equal("track_gone", output.run({ api = api, fields = { guid = "{X}", channel = "none" } }).error.code)
    end)

    it("refuses any track when there is no cue track", function()
      local api = band()
      assert.are.equal("not_a_mix", output.run({ api = api, fields = { guid = "{K}", channel = "none" } }).error.code)
    end)
  end)

  it("is one command on the bridge", function()
    local api = band()
    local handler = service.new({ api = api })
    local _, reply = handler.handle("q1|7|cmd=cue")
    assert.is_truthy(reply:find('"status":"ok"', 1, true))
    assert.is_not_nil(cue_track(api))
  end)
end)
