local state = require("lib.core.state")
local fake_project = require("spec.support.fake_project")

local function read(tracks)
  return state.run({ api = fake_project.new({ tracks = tracks }) })
end

local function names(list)
  local out = {}
  for _, item in ipairs(list) do out[#out + 1] = item.name end
  return out
end

describe("state", function()
  it("reads an empty project", function()
    local result = read({})
    assert.are.equal("ok", result.status)
    assert.is_nil(result.folder)
    assert.are.same({}, result.mixes)
    assert.are.same({}, result.sources)
  end)

  describe("which tracks are mixes", function()
    it("takes the exact IEM_ prefix with a name after it, and shows the name without it", function()
      local result = read({
        { name = "IEM_Vocals" }, { name = "iem_lower" }, { name = "IEM_" }, { name = "IEM" }, { name = "Kick" },
      })
      assert.are.same({ "Vocals" }, names(result.mixes))
      assert.are.same({ "iem_lower", "IEM_", "IEM", "Kick" }, names(result.sources))
    end)

    it("includes incomplete mixes (no receive, no output) and duplicate names", function()
      local result = read({ { name = "IEM_A" }, { name = "IEM_A" } })
      assert.are.same({ "A", "A" }, names(result.mixes))
      assert.are.same({}, result.mixes[1].sends)
      assert.are.same({}, result.mixes[1].outputs)
    end)
  end)

  describe("the IEMs folder", function()
    it("has no folder when no track is named IEMs, and every mix is a stray", function()
      local result = read({ { name = "IEM_A" } })
      assert.is_nil(result.folder)
      assert.is_false(result.mixes[1].in_folder)
    end)

    it("marks mixes inside the folder, and strays before and after it", function()
      local result = read({
        { name = "IEM_Before" },
        { name = "IEMs", depth = 1 },
        { name = "IEM_In1" },
        { name = "IEM_In2", depth = -1 },
        { name = "IEM_After" },
      })
      assert.are.same({ guid = "{GUID-2}", is_folder = true, tracks_after = true }, result.folder)
      local in_folder = {}
      for _, mix in ipairs(result.mixes) do in_folder[mix.name] = mix.in_folder end
      assert.are.same({ Before = false, In1 = true, In2 = true, After = false }, in_folder)
    end)

    it("is not a folder while empty (depth 0), so nothing is inside it", function()
      local result = read({ { name = "IEMs" }, { name = "IEM_A" } })
      assert.are.same({ guid = "{GUID-1}", is_folder = false, tracks_after = true }, result.folder)
      assert.is_false(result.mixes[1].in_folder)
    end)

    it("is never listed as a source", function()
      local result = read({ { name = "IEMs", depth = 1 }, { name = "IEM_A", depth = -1 } })
      assert.are.same({}, result.sources)
    end)
  end)

  describe("sources", function()
    it("come in project order with folder depth", function()
      local result = read({
        { name = "Drums", depth = 1 },
        { name = "Kick" },
        { name = "Overheads", depth = 1 },
        { name = "OH L" },
        { name = "OH R", depth = -2 },
        { name = "Bass" },
      })
      local shape = {}
      for _, s in ipairs(result.sources) do
        shape[#shape + 1] = ("%s:%d:%s"):format(s.name, s.depth, tostring(s.is_folder))
      end
      assert.are.same({
        "Drums:0:true", "Kick:1:false", "Overheads:1:true", "OH L:2:false", "OH R:2:false", "Bass:0:false",
      }, shape)
    end)

    it("carries the track GUID", function()
      assert.are.equal("{GUID-1}", read({ { name = "Kick" } }).sources[1].guid)
    end)

    it("reports the track's own colour as rrggbb, and none when it has no colour", function()
      local red = 0x1000000 + 0xFF + 0x20 * 256 + 0x30 * 65536
      local sources = read({ { name = "Kick", colour = red }, { name = "Snare" } }).sources
      assert.are.equal("ff2030", sources[1].tint)
      assert.is_nil(sources[2].tint)
    end)

    it("never reports a negative depth for a project with stray closers", function()
      assert.are.equal(0, read({ { name = "A", depth = -1 }, { name = "B" } }).sources[2].depth)
    end)
  end)

  describe("a mix's sends", function()
    local result = read({
      { name = "Kick" },
      { name = "Bass" },
      { name = "IEM_Drums",
        receives = {
          { from = "Kick", vol = 0.5, mode = 3 },
          { from = "Bass", vol = 1.0, mode = 0, muted = true },
        } },
    })
    local mix = result.mixes[1]

    it("name the source by GUID and carry level, mute and signal point", function()
      assert.are.same({
        { source = "{GUID-1}", vol = 0.5, muted = false, mode = 3 },
        { source = "{GUID-2}", vol = 1.0, muted = true, mode = 0 },
      }, mix.sends)
    end)
  end)

  describe("a mix's output", function()
    local function outputs_of(dests)
      local list = {}
      for _, dest in ipairs(dests) do list[#list + 1] = { dest = dest } end
      return read({ { name = "IEM_A", outputs = list } }).mixes[1].outputs
    end

    it("is empty when there is none", function()
      assert.are.same({}, outputs_of({}))
    end)

    it("is a stereo pair at its first channel", function()
      assert.are.same({ { channel = 2, mono = false } }, outputs_of({ 2 }))
    end)

    it("is mono when the destination carries the mono bit", function()
      assert.are.same({ { channel = 1, mono = true } }, outputs_of({ 1 | 1024 }))
    end)

    it("lists every output when there are several (shown read-only)", function()
      assert.are.equal(2, #outputs_of({ 0, 2 }))
    end)
  end)

  describe("the audio device and the master", function()
    it("lists the device's output channel names", function()
      local api = fake_project.new({ tracks = {}, device = { "Output 1", "Output 2", "Out 3" } })
      assert.are.same({ "Output 1", "Output 2", "Out 3" }, state.run({ api = api }).device.channels)
    end)

    it("has no channels while the audio device is closed", function()
      assert.are.same({}, read({}).device.channels)
    end)

    it("lists the master track's hardware outputs", function()
      local api = fake_project.new({ tracks = {}, master_outputs = { { dest = 0 }, { dest = 6 | 1024 } } })
      assert.are.same({ { channel = 0, mono = false }, { channel = 6, mono = true } },
        state.run({ api = api }).master_outputs)
    end)
  end)

  it("reports whether the mix feeds the master", function()
    local result = read({ { name = "IEM_A", main_send = false }, { name = "IEM_B" } })
    assert.is_false(result.mixes[1].master_send)
    assert.is_true(result.mixes[2].master_send)
  end)

  it("writes nothing: the fake would fail on any write", function()
    local api = fake_project.new({ tracks = { { name = "IEM_A" } } })
    assert.has_no.errors(function() state.run({ api = api }) end)
  end)
end)
