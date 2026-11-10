local output = require("lib.core.output")
local service = require("lib.bridge.service")
local fake_project = require("spec.support.fake_project")

local DEVICE = { "Output 1", "Output 2", "Output 3", "Output 4" }

local function project(tracks, device)
  return fake_project.new({ tracks = tracks, device = device or DEVICE })
end

local function set(api, channel, mono, guid)
  local fields = { guid = guid or "{A}", channel = tostring(channel), mono = mono and "1" or "0" }
  return output.run({ api = api, fields = fields })
end

local function clear(api, guid)
  return output.run({ api = api, fields = { guid = guid or "{A}", channel = "none" } })
end

local function untouched(api)
  assert.are.same({}, api.undo_steps)
  assert.are.same({}, api.outside_block)
end

local function one_undo_step(api)
  assert.are.same({}, api.outside_block)
  assert.are.equal(0, api.open_blocks)
  assert.are.same({ "IEM Setup: set output" }, api.undo_steps)
end

describe("output", function()
  describe("set", function()
    it("gives a mix with none a stereo output from the channel", function()
      local api = project({ { name = "IEM_A", guid = "{A}" } })
      local result = set(api, 2, false)
      assert.are.same({ status = "ok", changed = true }, result)
      assert.are.same({ { dest = 2, src = 0 } }, api.tracks[1].outputs)
      one_undo_step(api)
    end)

    it("makes a mono output a downmix: source 0, destination with bit 1024", function()
      local api = project({ { name = "IEM_A", guid = "{A}" } })
      set(api, 1, true)
      assert.are.same({ { dest = 1 | 1024, src = 0 } }, api.tracks[1].outputs)
    end)
  end)

  describe("replace", function()
    it("changes the one output in place, so there is still exactly one", function()
      local api = project({ { name = "IEM_A", guid = "{A}", outputs = { { dest = 0 } } } })
      set(api, 2, true)
      assert.are.same({ { dest = 2 | 1024, src = 0 } }, api.tracks[1].outputs)
      one_undo_step(api)
    end)

    it("goes from mono back to stereo", function()
      local api = project({ { name = "IEM_A", guid = "{A}", outputs = { { dest = 1 | 1024 } } } })
      set(api, 1, false)
      assert.are.equal(1, api.tracks[1].outputs[1].dest)
    end)

    it("does nothing, and leaves no undo step, when the mix already has it", function()
      local api = project({ { name = "IEM_A", guid = "{A}", outputs = { { dest = 2 } } } })
      assert.are.same({ status = "ok", changed = false }, set(api, 2, false))
      untouched(api)
    end)
  end)

  describe("clear", function()
    it("removes the output", function()
      local api = project({ { name = "IEM_A", guid = "{A}", outputs = { { dest = 2 } } } })
      assert.are.same({ status = "ok", changed = true }, clear(api))
      assert.are.same({}, api.tracks[1].outputs)
      one_undo_step(api)
    end)

    it("on a mix with none is a no-op without an undo step", function()
      local api = project({ { name = "IEM_A", guid = "{A}" } })
      assert.are.same({ status = "ok", changed = false }, clear(api))
      untouched(api)
    end)

    it("still works while the audio device is closed", function()
      local api = project({ { name = "IEM_A", guid = "{A}", outputs = { { dest = 2 } } } }, {})
      assert.are.equal("ok", clear(api).status)
      assert.are.same({}, api.tracks[1].outputs)
    end)
  end)

  describe("refusals leave the project and the undo history alone", function()
    local function refused(api, result, code)
      assert.are.same({ status = "refused", error = { code = code } }, result)
      untouched(api)
    end

    it("track_gone for an unknown GUID", function()
      local api = project({})
      refused(api, set(api, 0, false), "track_gone")
    end)

    it("not_a_mix for a source, the folder or a bare IEM_", function()
      local api = project({
        { name = "Kick", guid = "{A}" }, { name = "IEMs", guid = "{F}" }, { name = "IEM_", guid = "{B}" },
      })
      refused(api, set(api, 0, false), "not_a_mix")
      refused(api, set(api, 0, false, "{F}"), "not_a_mix")
      refused(api, clear(api, "{B}"), "not_a_mix")
    end)

    it("multiple_outputs: a track with several outputs is read-only, for set and clear alike", function()
      local api = project({ { name = "IEM_A", guid = "{A}", outputs = { { dest = 0 }, { dest = 2 } } } })
      refused(api, set(api, 1, false), "multiple_outputs")
      refused(api, clear(api), "multiple_outputs")
      assert.are.equal(2, #api.tracks[1].outputs)
    end)

    it("bad_channel when it is not a whole number or is outside the device", function()
      local api = project({ { name = "IEM_A", guid = "{A}" } })
      for _, channel in ipairs({ "x", "-1", "1.5", "", "4" }) do
        refused(api, output.run({ api = api, fields = { guid = "{A}", channel = channel, mono = "1" } }), "bad_channel")
      end
      refused(api, output.run({ api = api, fields = { guid = "{A}" } }), "bad_channel")
    end)

    it("bad_channel for a stereo output that would run past the last channel; mono fits there", function()
      local api = project({ { name = "IEM_A", guid = "{A}" } })
      refused(api, set(api, 3, false), "bad_channel")
      assert.are.equal("ok", set(api, 3, true).status)
    end)

    it("no_device for a set while the audio device is closed", function()
      local api = project({ { name = "IEM_A", guid = "{A}" } }, {})
      refused(api, set(api, 0, false), "no_device")
    end)
  end)

  it("is one command on the bridge", function()
    local api = project({ { name = "IEM_A", guid = "{A}" } })
    local handler = service.new({ api = api })
    local body = "cmd=output&guid=%7BA%7D&channel=1&mono=1"
    local _, reply = handler.handle(("q1|%d|%s"):format(#body, body))
    assert.is_truthy(reply:find('"status":"ok"', 1, true))
    assert.are.same({ { dest = 1 | 1024, src = 0 } }, api.tracks[1].outputs)
  end)

  it("the bridge refuses a write to a read-only track too", function()
    local api = project({ { name = "IEM_A", guid = "{A}", outputs = { { dest = 0 }, { dest = 2 } } } })
    local handler = service.new({ api = api })
    local body = "cmd=output&guid=%7BA%7D&channel=none"
    local _, reply = handler.handle(("q1|%d|%s"):format(#body, body))
    assert.is_truthy(reply:find('"code":"multiple_outputs"', 1, true))
    assert.are.equal(2, #api.tracks[1].outputs)
  end)
end)
