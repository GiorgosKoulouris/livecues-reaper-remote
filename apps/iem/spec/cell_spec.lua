local cell = require("lib.core.cell")
local service = require("lib.bridge.service")
local fake_project = require("spec.support.fake_project")

local function project(tracks)
  return fake_project.new({ tracks = tracks })
end

local function band()
  return project({
    { name = "Kick", guid = "{K}" },
    { name = "Snare", guid = "{S}" },
    { name = "IEMs", guid = "{F}", depth = 1 },
    { name = "IEM_A", guid = "{A}" },
    { name = "IEM_B", guid = "{B}", depth = -1, receives = { { from = "Snare", vol = 0.5, mode = 3 } } },
  })
end

local function on(api, source, mix)
  return cell.run({ api = api, fields = { source = source, mix = mix, on = "1" } })
end

local function off(api, source, mix)
  return cell.run({ api = api, fields = { source = source, mix = mix, on = "0" } })
end

local function untouched(api)
  assert.are.same({}, api.undo_steps)
  assert.are.same({}, api.outside_block)
end

local function one_undo_step(api, description)
  assert.are.same({}, api.outside_block)
  assert.are.equal(0, api.open_blocks)
  assert.are.same({ description }, api.undo_steps)
end

describe("cell", function()
  describe("on", function()
    it("creates a send from the source to the mix, post-FX pre-fader at 0 dB", function()
      local api = band()
      assert.are.same({ status = "ok", changed = true }, on(api, "{K}", "{A}"))
      local receives = api.tracks[4].receives
      assert.are.equal(1, #receives)
      assert.are.equal(api.tracks[1], receives[1].src_track)
      assert.are.equal(3, receives[1].mode)
      assert.are.equal(1.0, receives[1].vol)
      one_undo_step(api, "IEM Setup: switch cell on")
    end)

    it("leaves other sends of the mix and of the source alone", function()
      local api = band()
      on(api, "{S}", "{A}")
      on(api, "{K}", "{B}")
      assert.are.equal(1, #api.tracks[4].receives)
      assert.are.equal(2, #api.tracks[5].receives)
      assert.are.equal(0.5, api.tracks[5].receives[1].vol)
    end)

    it("can feed from a folder track as a source", function()
      local api = project({ { name = "Drums", guid = "{D}", depth = 1 }, { name = "Kick", depth = -1 },
        { name = "IEM_A", guid = "{A}" } })
      assert.are.equal("ok", on(api, "{D}", "{A}").status)
    end)

    it("does nothing, with no undo step, when the pair already has a send (several included)", function()
      local api = band()
      assert.are.same({ status = "ok", changed = false }, on(api, "{S}", "{B}"))
      untouched(api)
      api.CreateTrackSend(api.tracks[2], api.tracks[5])
      api.undo_steps, api.outside_block = {}, {}
      assert.are.same({ status = "ok", changed = false }, on(api, "{S}", "{B}"))
      assert.are.equal(2, #api.tracks[5].receives)
      untouched(api)
    end)
  end)

  describe("off", function()
    it("removes the send", function()
      local api = band()
      assert.are.same({ status = "ok", changed = true }, off(api, "{S}", "{B}"))
      assert.are.same({}, api.tracks[5].receives)
      assert.are.same({}, api.tracks[2].sends)
      one_undo_step(api, "IEM Setup: switch cell off")
    end)

    it("removes every send between the pair at once, in one undo step, and no other", function()
      local api = band()
      api.CreateTrackSend(api.tracks[2], api.tracks[5])
      api.CreateTrackSend(api.tracks[2], api.tracks[4])
      api.CreateTrackSend(api.tracks[1], api.tracks[5])
      api.CreateTrackSend(api.tracks[2], api.tracks[5])
      api.undo_steps, api.outside_block = {}, {}
      assert.are.same({ status = "ok", changed = true }, off(api, "{S}", "{B}"))
      assert.are.equal(1, #api.tracks[5].receives)
      assert.are.equal(api.tracks[1], api.tracks[5].receives[1].src_track)
      assert.are.equal(1, #api.tracks[4].receives)
      assert.are.equal(api.tracks[2], api.tracks[4].receives[1].src_track)
      assert.are.equal(1, #api.tracks[2].sends)
      one_undo_step(api, "IEM Setup: switch cell off")
    end)

    it("removes by destination track, highest index first, so the other sends keep their identity", function()
      local api = band()
      local snare = api.tracks[2]
      api.CreateTrackSend(snare, api.tracks[4]) -- source sends: B (from band), A, B, A, B
      api.CreateTrackSend(snare, api.tracks[5])
      api.CreateTrackSend(snare, api.tracks[4])
      api.CreateTrackSend(snare, api.tracks[5])
      local keep = { snare.sends[2], snare.sends[4] } -- the two sends to A
      local removed = {}
      local remove = api.RemoveTrackSend
      api.RemoveTrackSend = function(track, category, index)
        removed[#removed + 1] = { track = track, category = category, index = index,
          dest = track.sends[index + 1].dest }
        return remove(track, category, index)
      end
      api.undo_steps, api.outside_block = {}, {}
      assert.are.equal(true, off(api, "{S}", "{B}").changed)
      assert.are.same({ 4, 2, 0 }, { removed[1].index, removed[2].index, removed[3].index })
      for _, call in ipairs(removed) do
        assert.are.equal(snare, call.track)
        assert.are.equal(0, call.category)
        assert.are.equal(api.tracks[5], call.dest) -- every removal hit a send to B, by its destination
      end
      assert.are.same(keep, snare.sends)
      assert.are.same(keep, api.tracks[4].receives)
    end)

    it("does nothing, with no undo step, when the pair has no send", function()
      local api = band()
      assert.are.same({ status = "ok", changed = false }, off(api, "{K}", "{A}"))
      untouched(api)
    end)

    it("turning it on and off again leaves the project as it was", function()
      local api = band()
      on(api, "{K}", "{A}")
      off(api, "{K}", "{A}")
      assert.are.same({}, api.tracks[4].receives)
      assert.are.same({}, api.tracks[1].sends)
    end)
  end)

  describe("refusals leave the project and the undo history alone", function()
    local function refused(api, result, code)
      assert.are.same({ status = "refused", error = { code = code } }, result)
      untouched(api)
    end

    it("track_gone when the source or the mix is no longer in the project", function()
      local api = band()
      refused(api, on(api, "{X}", "{A}"), "track_gone")
      refused(api, on(api, "{K}", "{X}"), "track_gone")
      refused(api, off(api, "{X}", "{B}"), "track_gone")
      refused(api, off(api, "{S}", "{X}"), "track_gone")
      refused(api, cell.run({ api = api, fields = { on = "1" } }), "track_gone")
    end)

    it("not_a_mix when the column is not a mix (a source, the folder, a bare IEM_)", function()
      local api = project({
      { name = "Kick", guid = "{K}" }, { name = "IEMs", guid = "{F}" }, { name = "IEM_", guid = "{B}" },
    })
      refused(api, on(api, "{K}", "{K}"), "not_a_mix")
      refused(api, on(api, "{K}", "{F}"), "not_a_mix")
      refused(api, off(api, "{K}", "{B}"), "not_a_mix")
    end)

    it("not_a_source when the row is a mix or the IEMs folder", function()
      local api = band()
      refused(api, on(api, "{B}", "{A}"), "not_a_source")
      refused(api, on(api, "{F}", "{A}"), "not_a_source")
      refused(api, off(api, "{A}", "{A}"), "not_a_source")
    end)

    it("a second track named IEMs is an ordinary source", function()
      local api = project({
      { name = "IEMs", guid = "{F}" }, { name = "IEMs", guid = "{G}" }, { name = "IEM_A", guid = "{A}" },
    })
      assert.are.equal("ok", on(api, "{G}", "{A}").status)
    end)
  end)

  it("is one command on the bridge", function()
    local api = band()
    local handler = service.new({ api = api })
    local body = "cmd=cell&source=%7BK%7D&mix=%7BA%7D&on=1"
    local _, reply = handler.handle(("q1|%d|%s"):format(#body, body))
    assert.is_truthy(reply:find('"status":"ok"', 1, true))
    assert.are.equal(1, #api.tracks[4].receives)
    body = "cmd=cell&source=%7BS%7D&mix=%7BB%7D&on=0"
    _, reply = handler.handle(("q2|%d|%s"):format(#body, body))
    assert.is_truthy(reply:find('"changed":true', 1, true))
    assert.are.equal(0, #api.tracks[5].receives)
  end)
end)
