local fake_project = require("spec.support.fake_project")
local save = require("lib.core.snapshot_save")
local restore = require("lib.core.snapshot_restore")

local function show()
  return fake_project.new({
    path = "C:/Shows/Sunday/Sunday.rpp",
    tracks = {
      { name = "Kick", vol = 0.5, pan = -0.25, width = 0.5, dual_l = -0.5, dual_r = 0.75, pan_mode = 6, mute = 1,
        solo = 5, phase = 1, fx = 0,
        sends = { { to = "Bus", vol = 0.3, pan = 0.1, mute = 1, mode = 3 }, { to = "Bus", vol = 0.6 },
          { to = "IEM_Drums", vol = 0.2 } },
        outputs = { { vol = 0.7, pan = 0.2, mode = 1 }, { vol = 0.8 } } },
      { name = "IEM_Drums", vol = 0.4, mute = 1 },
      { name = "Bus", vol = 0.9 },
    },
    master = { vol = 0.9, pan = 0.05, mute = 1, phase = 1, outputs = { { vol = 0.6, mode = 1 } } },
  })
end

local function saved(api, name)
  local reply = save.run({ api = api, fields = { name = name }, now = function() return 1 end })
  assert.are.equal("ok", reply.status)
end

-- Move every value away from what was saved.
local function disturb(api)
  for _, track in ipairs({ api.tracks[1], api.tracks[2], api.tracks[3], api.GetMasterTrack() }) do
    track.vol, track.pan, track.width, track.dual_l, track.dual_r, track.pan_mode = 0.11, 0.33, 0.22, 0.1, 0.2, 0
    track.mute, track.solo, track.phase, track.fx = 0, 0, 0, 1
    for _, s in ipairs(track.sends) do s.vol, s.pan, s.mute, s.mode = 0.01, 0.02, 0, 1 end
    for _, o in ipairs(track.outputs) do o.vol, o.pan, o.mute, o.mode = 0.01, 0.02, 0, 2 end
  end
end

local function run(api, ticks, name)
  return restore.run({ api = api, fields = { name = name or "Verse", ticks = ticks } })
end

describe("snapshot_restore", function()
  local api, kick, drums, bus, master

  before_each(function()
    api = show()
    saved(api, "Verse")
    kick, drums, bus, master = api.tracks[1], api.tracks[2], api.tracks[3], api.GetMasterTrack()
    kick.solo = 6
    saved(api, "Two")
    kick.solo = 5
    disturb(api)
  end)

  it("restores levels alone, on tracks and the Master, leaving everything else", function()
    local reply = run(api, "L")
    assert.are.same({ status = "ok", name = "Verse", tracks = 3, sends = 0, skipped = 0 }, reply)
    assert.are.same({ 0.5, 0.9, 0.9 }, { kick.vol, bus.vol, master.vol })
    assert.are.equal(0.11, drums.vol)
    assert.are.equal(0.33, kick.pan)
    assert.are.equal(0, kick.mute)
    assert.are.equal(0.01, kick.sends[1].vol)
    assert.are.equal(0.01, kick.outputs[1].vol)
    assert.are.equal(1, #api.undo_names)
  end)

  it("restores the full pan state alone", function()
    run(api, "P")
    assert.are.same({ -0.25, 0.5, -0.5, 0.75, 6 }, { kick.pan, kick.width, kick.dual_l, kick.dual_r, kick.pan_mode })
    assert.are.equal(0.05, master.pan)
    assert.are.equal(0.11, kick.vol)
  end)

  it("restores mutes alone, the Master included", function()
    run(api, "M")
    assert.are.same({ 1, 1 }, { kick.mute, master.mute })
    assert.are.equal(0.11, kick.vol)
  end)

  it("restores solos alone, writing a stored 5 as 1 and a stored 6 as 2", function()
    run(api, "S")
    assert.are.equal(1, kick.solo)
    run(api, "S", "Two")
    assert.are.equal(2, kick.solo)
    assert.are.equal(0.11, kick.vol)
  end)

  it("restores polarity alone", function()
    run(api, "R")
    assert.are.same({ 1, 1, 0 }, { kick.phase, master.phase, kick.mute })
  end)

  it("restores FX on/off alone", function()
    run(api, "F")
    assert.are.same({ 0, 1, 0.11 }, { kick.fx, bus.fx, kick.vol })
  end)

  it("restores sends and hardware outputs alone, in order, duplicates included", function()
    local reply = run(api, "E")
    assert.are.same({ status = "ok", name = "Verse", tracks = 0, sends = 5, skipped = 0 }, reply)
    local first = kick.sends[1]
    assert.are.same({ 0.3, 0.1, 1, 3 }, { first.vol, first.pan, first.mute, first.mode })
    assert.are.equal(0.6, kick.sends[2].vol)
    assert.are.same({ 0.7, 0.2, 1 }, { kick.outputs[1].vol, kick.outputs[1].pan, kick.outputs[1].mode })
    assert.are.equal(0.8, kick.outputs[2].vol)
    assert.are.same({ 0.6, 1 }, { master.outputs[1].vol, master.outputs[1].mode })
    assert.are.equal(0.11, kick.vol)
  end)

  it("restores everything ticked together", function()
    local reply = run(api, "LPMSREF")
    assert.are.same({ tracks = 3, sends = 5, skipped = 0 },
      { tracks = reply.tracks, sends = reply.sends, skipped = reply.skipped })
    assert.are.same({ 0.5, 1, 1, 0, 1 }, { kick.vol, kick.mute, kick.phase, kick.fx, kick.solo })
    assert.are.equal(0.3, kick.sends[1].vol)
    assert.are.equal(0.6, master.outputs[1].vol)
    assert.are.equal(1, api.undo_blocks)
  end)

  it("never writes in-ear tracks or sends into them, and does not count them", function()
    local reply = run(api, "LPMSREF")
    assert.are.same({ 0.11, 0 }, { drums.vol, drums.mute })
    assert.are.equal(0.01, kick.sends[3].vol)
    assert.are.equal(0, reply.skipped)
  end)

  it("recognises the cue and the IEMs folder by their current names", function()
    bus.name, drums.name = "IEM-Cue", "IEMs"
    run(api, "L")
    assert.are.same({ 0.11, 0.11, 0.5 }, { drums.vol, bus.vol, kick.vol })
  end)

  it("follows a renamed and a reordered track by GUID", function()
    kick.name = "Kick In"
    api.tracks[1], api.tracks[3] = bus, kick
    run(api, "L")
    assert.are.same({ 0.5, 0.9 }, { kick.vol, bus.vol })
  end)

  it("skips and counts a deleted track with its sends and outputs", function()
    table.remove(api.tracks, 1)
    local reply = run(api, "LE")
    assert.are.equal(1 + 3 + 2, reply.skipped)
    assert.are.equal(0.9, bus.vol)
  end)

  it("skips and counts a deleted send, matching the rest by pair and order", function()
    table.remove(kick.sends, 1)
    local reply = run(api, "E")
    assert.are.equal(1, reply.skipped)
    assert.are.equal(0.3, kick.sends[1].vol)
  end)

  it("skips and counts a deleted hardware output", function()
    table.remove(kick.outputs, 2)
    assert.are.equal(1, run(api, "E").skipped)
  end)

  it("leaves a send added since the save alone", function()
    kick.sends[#kick.sends + 1] = { dest = bus, vol = 0.77, pan = 0, mute = 0, mode = 0 }
    run(api, "E")
    assert.are.equal(0.77, kick.sends[4].vol)
    assert.are.equal(0.6, kick.sends[2].vol)
  end)

  describe("undo and refusals", function()
    it("opens exactly one undo block named with the snapshot when it writes", function()
      run(api, "LPMSREF")
      assert.are.equal(1, api.undo_blocks)
      assert.are.same({ "Snapshots: restore Verse" }, api.undo_names)
    end)

    it("opens none when nothing is written", function()
      api.tracks[1], api.tracks[2], api.tracks[3] = nil, nil, nil
      master.outputs = {}
      local reply = run(api, "E")
      assert.are.equal("ok", reply.status)
      assert.are.equal(0, api.undo_blocks)
      assert.are.equal(0, #api.writes)
    end)

    it("refuses before any write", function()
      assert.are.equal("no_ticks", run(api, "").error.code)
      assert.are.equal("bad_ticks", run(api, "LX").error.code)
      assert.are.equal("empty_name", run(api, "L", " ").error.code)
      assert.are.equal("not_found", run(api, "L", "Nope").error.code)
      api.ext.LCRR_SNAPSHOTS["snapshot.1"] = "garbage"
      assert.are.equal("unreadable", run(api, "L").error.code)
      api.ext.LCRR_SNAPSHOTS.snapshots = "garbage"
      assert.are.equal("unreadable", run(api, "L").error.code)
      assert.are.equal(0, api.undo_blocks)
      assert.are.equal(0, #api.writes)
    end)
  end)
end)
