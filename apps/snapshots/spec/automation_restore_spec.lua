local fake_project = require("spec.support.fake_project")
local save = require("lib.core.snapshot_save")
local restore = require("lib.core.snapshot_restore")

-- The Master's mute is restored with any M tick; behind this envelope it is skipped, so a spec can be about one track.
local GUARDED_MASTER = { mute = 1, automode = 3, env = { Mute = 1 } }

-- Save a show, move the values, restore, and see what automation did to the result.
local function setup(spec)
  spec.path = "C:/Shows/Sunday/Sunday.rpp"
  local api = fake_project.new(spec)
  assert.are.equal("ok", save.run({ api = api, fields = { name = "Verse" }, now = function() return 1 end }).status)
  for _, track in ipairs(api.tracks) do
    track.vol, track.pan, track.mute = 0.11, 0.33, 0
    for _, s in ipairs(track.sends) do s.vol, s.pan, s.mute = 0.01, 0.02, 0 end
  end
  api.GetMasterTrack().mute = 0
  api.writes, api.undo_blocks = {}, 0
  return api
end

local function run(api, ticks)
  return restore.run({ api = api, fields = { name = "Verse", ticks = ticks or "LPME" } })
end

local function muted(api, index) return api.tracks[index].mute end

describe("restore and automation", function()
  it("counts written track and send values that have active automation, and writes them", function()
    local api = setup({ tracks = {
      { name = "Kick", vol = 0.5, pan = 0.2, mute = 1, env = { Volume = 3, Pan = 2 },
        sends = { { to = "Bus", vol = 0.4, mute = 1, env = { vol = 4, pan = 1 } } } },
      { name = "Bus" },
    } })
    local reply = run(api)
    assert.are.equal("ok", reply.status)
    -- Kick volume and pan, send volume and pan.
    assert.are.equal(4, reply.automated)
    assert.are.equal(0, reply.muted_skipped)
    assert.are.equal(0.5, api.tracks[1].vol)
    assert.are.equal(0.4, api.tracks[1].sends[1].vol)
  end)

  it("does not count an envelope with no points or a bypassed one", function()
    local api = setup({ tracks = { { name = "Kick", env = { Volume = 0, Pan = 3 }, inactive = { Pan = true } } } })
    assert.are.equal(0, run(api).automated)
  end)

  it("counts only values that are written", function()
    local api = setup({ tracks = { { name = "Kick", env = { Volume = 3, Pan = 3 } } } })
    assert.are.equal(1, run(api, "L").automated)
  end)

  for _, mode in ipairs({ 2, 3, 4 }) do
    it("skips a track mute with a Mute envelope in mode " .. mode, function()
      local api = setup({ master = GUARDED_MASTER,
        tracks = { { name = "Kick", mute = 1, automode = mode, env = { Mute = 2 } } } })
      local reply = run(api, "M")
      assert.are.equal(2, reply.muted_skipped)
      assert.are.equal(0, muted(api, 1))
      assert.are.equal(0, reply.skipped)
      assert.are.equal(0, api.undo_blocks)
      assert.are.equal(0, reply.tracks)
    end)
  end

  for _, mode in ipairs({ 0, 1, 5 }) do
    it("writes a track mute normally in mode " .. mode, function()
      local api = setup({ tracks = { { name = "Kick", mute = 1, automode = mode, env = { Mute = 2 } } } })
      local reply = run(api, "M")
      assert.are.equal(0, reply.muted_skipped)
      assert.are.equal(1, muted(api, 1))
      assert.are.equal(1, reply.automated)
    end)
  end

  it("writes a track mute when there is no Mute envelope, whatever the mode", function()
    local api = setup({ tracks = { { name = "Kick", mute = 1, automode = 3 } } })
    assert.are.equal(0, run(api, "M").muted_skipped)
    assert.are.equal(1, muted(api, 1))
  end)

  it("skips a mute under a global override of 2, 3 or 4, and not under 0, 1 or 5", function()
    for override, skipped in pairs({ [2] = 1, [3] = 1, [4] = 1, [0] = 0, [1] = 0, [5] = 0, [-1] = 0 }) do
      local api = setup({ override = override, tracks = { { name = "Kick", mute = 1, env = { Mute = 2 } } } })
      assert.are.equal(skipped, run(api, "M").muted_skipped, "override " .. override)
    end
  end)

  it("guards the Master's mute the same way", function()
    local api = setup({ master = { mute = 1, automode = 3, env = { Mute = 1 } } })
    assert.are.equal(1, run(api, "M").muted_skipped)
    assert.are.equal(0, api.GetMasterTrack().mute)
  end)

  it("still writes levels and pans on a writing-mode track", function()
    local api = setup({ tracks = { { name = "Kick", vol = 0.5, mute = 1, automode = 3, env = { Mute = 2 } } } })
    local reply = run(api, "LM")
    assert.are.equal(1, reply.muted_skipped)
    assert.are.equal(0.5, api.tracks[1].vol)
    assert.are.equal(2, reply.tracks)
    assert.are.equal(1, api.undo_blocks)
  end)

  describe("a send's mute", function()
    local function with_send(send, track_mode)
      send.to = "Bus"
      send.mute = 1
      return setup({ tracks = { { name = "Kick", automode = track_mode or 0, sends = { send } }, { name = "Bus" } } })
    end

    it("is skipped when the send's own mode writes and it has a Mute envelope", function()
      local api = with_send({ automode = 3, env = { mute = 2 } })
      local reply = run(api, "E")
      assert.are.equal(1, reply.muted_skipped)
      assert.are.equal(0, api.tracks[1].sends[1].mute)
      assert.are.equal(1, reply.sends)
    end)

    it("follows the track's mode when the send's is -1", function()
      local api = with_send({ env = { mute = 2 } }, 4)
      assert.are.equal(1, run(api, "E").muted_skipped)
    end)

    it("ignores the track's mode when the send has its own, safe, one", function()
      local api = with_send({ automode = 1, env = { mute = 2 } }, 3)
      local reply = run(api, "E")
      assert.are.equal(0, reply.muted_skipped)
      assert.are.equal(1, api.tracks[1].sends[1].mute)
      assert.are.equal(1, reply.automated)
    end)

    it("is written when the send has no Mute envelope", function()
      local api = with_send({ automode = 3 })
      assert.are.equal(0, run(api, "E").muted_skipped)
      assert.are.equal(1, api.tracks[1].sends[1].mute)
    end)

    it("is skipped under the global override", function()
      local api = setup({ override = 3, tracks = { { name = "Kick", sends = { { to = "Bus", mute = 1,
        env = { mute = 1 } } } }, { name = "Bus" } } })
      assert.are.equal(1, run(api, "E").muted_skipped)
    end)
  end)

  it("adds no undo step when every write is a skipped mute", function()
    local api = setup({ master = GUARDED_MASTER,
      tracks = { { name = "Kick", mute = 1, automode = 3, env = { Mute = 2 } } } })
    local reply = run(api, "M")
    assert.are.equal("ok", reply.status)
    assert.are.equal(2, reply.muted_skipped)
    assert.are.equal(0, api.undo_blocks)
    assert.are.same({}, api.writes)
  end)
end)
