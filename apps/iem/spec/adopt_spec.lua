local adopt = require("lib.core.adopt")
local fake_project = require("spec.support.fake_project")

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

local function run(api, guid)
  return adopt.run({ api = api, fields = { guid = guid } })
end

local function native(r, g, b) return (r + g * 256 + b * 65536) | 0x1000000 end

local function one_undo_step(api)
  assert.are.same({}, api.outside_block)
  assert.are.equal(0, api.open_blocks)
  assert.are.same({ "IEM Setup: adopt mix" }, api.undo_steps)
end

local function stray_band(extra)
  return fake_project.new({
    ext = extra,
    tracks = {
      { name = "Kick", guid = "{K}" },
      { name = "Snare", guid = "{S}" },
      { name = "IEM_Stray", guid = "{X}",
        receives = {
          { from = "Kick", vol = 0.5, pan = 0.25, mode = 0 },
          { from = "Snare", vol = 0.7, muted = true, mode = 1 },
        } },
      { name = "IEMs", guid = "{F}", depth = 1 },
      { name = "IEM_A", guid = "{A}", depth = -1 },
      { name = "Vox", guid = "{V}" },
    },
  })
end

describe("adopt", function()
  describe("with an existing folder", function()
    it("moves the stray to the end of the folder, closing it", function()
      local api = stray_band()
      assert.are.same({ status = "ok" }, run(api, "{X}"))
      assert.are.same({ "Kick", "Snare", "IEMs", "IEM_A", "IEM_Stray", "IEM-Cue", "Vox" }, names(api))
      assert.are.same({ 0, 0, 1, 0, 0, -1, 0 }, depths(api))
      one_undo_step(api)
    end)

    it("turns master send off and applies the shared colour", function()
      local api = stray_band({ ["LCRR_IEM/colour"] = "ff8000" })
      run(api, "{X}")
      local mix = api.tracks[5]
      assert.are.equal(0, mix.main_send)
      assert.are.equal(native(255, 128, 0), mix.colour)
    end)

    it("converts a send in each mode to post-FX pre-fader and keeps level, pan and mute", function()
      local api = stray_band()
      run(api, "{X}")
      local mix = api.tracks[5]
      assert.are.equal(2, #mix.receives)
      for _, receive in ipairs(mix.receives) do assert.are.equal(3, receive.mode) end
      assert.are.same({ 0.5, 0.25 }, { mix.receives[1].vol, mix.receives[1].pan })
      assert.is_true(mix.receives[2].muted)
      assert.are.equal(0.7, mix.receives[2].vol)
    end)

    it("keeps several hardware outputs untouched", function()
      local api = fake_project.new({ tracks = {
        { name = "IEM_Stray", guid = "{X}", outputs = { { dest = 0, src = 0 }, { dest = 3, src = 0 } } },
        { name = "IEMs", depth = 1 },
        { name = "IEM_A", depth = -1 },
      } })
      run(api, "{X}")
      assert.are.same({ "IEMs", "IEM_A", "IEM_Stray", "IEM-Cue" }, names(api))
      assert.are.same({ { dest = 0, src = 0 }, { dest = 3, src = 0 } }, api.tracks[3].outputs)
    end)

    it("restores the engineer's track selection", function()
      local api = stray_band()
      api.tracks[1].selected = true
      run(api, "{X}")
      for _, track in ipairs(api.tracks) do
        assert.are.equal(track.name == "Kick", track.selected)
      end
    end)

    it("repairs the depth around a stray that closed another folder", function()
      local api = fake_project.new({ tracks = {
        { name = "Drums", depth = 1 },
        { name = "Kick" },
        { name = "IEM_Stray", guid = "{X}", depth = -1 },
        { name = "IEMs", depth = 1 },
        { name = "IEM_A", depth = -1 },
      } })
      run(api, "{X}")
      assert.are.same({ "Drums", "Kick", "IEMs", "IEM_A", "IEM_Stray", "IEM-Cue" }, names(api))
      assert.are.same({ 1, -1, 1, 0, 0, -1 }, depths(api))
    end)

    it("a stray that opened a folder of its own leaves its children outside the IEMs folder", function()
      local api = fake_project.new({ tracks = {
        { name = "Kick" },
        { name = "IEM_Stray", guid = "{X}", depth = 1 },
        { name = "Child1" },
        { name = "Child2", depth = -1 },
        { name = "IEMs", depth = 1 },
        { name = "IEM_A", depth = -1 },
      } })
      assert.are.same({ status = "ok" }, run(api, "{X}"))
      assert.are.same({ "Kick", "Child1", "Child2", "IEMs", "IEM_A", "IEM_Stray", "IEM-Cue" }, names(api))
      assert.are.same({ 0, 0, 0, 1, 0, 0, -1 }, depths(api))
      one_undo_step(api)
    end)

    it("takes over an emptied folder's closing, reopening it", function()
      local api = fake_project.new({ tracks = {
        { name = "IEM_Stray", guid = "{X}" },
        { name = "IEMs" },
        { name = "Vox" },
      } })
      run(api, "{X}")
      assert.are.same({ "IEMs", "IEM_Stray", "IEM-Cue", "Vox" }, names(api))
      assert.are.same({ 1, 0, -1, 0 }, depths(api))
    end)
  end)

  describe("without a folder", function()
    it("creates the folder at the end and puts the stray inside it", function()
      local api = fake_project.new({ tracks = {
        { name = "Kick" },
        { name = "IEM_Stray", guid = "{X}", receives = { { from = "Kick", mode = 0 } } },
        { name = "Vox" },
      } })
      assert.are.same({ status = "ok" }, run(api, "{X}"))
      assert.are.same({ "Kick", "Vox", "IEMs", "IEM_Stray", "IEM-Cue" }, names(api))
      assert.are.same({ 0, 0, 1, 0, -1 }, depths(api))
      assert.are.equal(0, api.tracks[3].main_send)
      assert.are.equal(3, api.tracks[4].receives[1].mode)
      one_undo_step(api)
    end)
  end)

  describe("refusals", function()
    it("a track that has gone", function()
      local api = stray_band()
      assert.are.same({ status = "refused", error = { code = "track_gone" } }, run(api, "{NO}"))
      assert.are.same({}, api.undo_steps)
    end)

    it("a track that is not a mix, and the folder", function()
      local api = stray_band()
      assert.are.equal("not_a_mix", run(api, "{K}").error.code)
      assert.are.equal("not_a_mix", run(api, "{F}").error.code)
      assert.are.same({}, api.undo_steps)
    end)

    it("a mix already in the folder", function()
      local api = stray_band()
      assert.are.equal("not_a_stray", run(api, "{A}").error.code)
      assert.are.same({}, api.undo_steps)
      assert.are.same({ "Kick", "Snare", "IEM_Stray", "IEMs", "IEM_A", "Vox" }, names(api))
    end)
  end)
  describe("a stray already at its slot", function()
    -- Real REAPER rewrites folder depths around a reordered track even when nothing moves (measured, issue 11), so the
    -- core must not reorder at all, and must leave the depths it wants after any reorder.
    local function band_with_two_strays()
      local api = fake_project.new({
        tracks = {
          { name = "Dummy", guid = "{D}" },
          { name = "IEMs", guid = "{F}" },
          { name = "IEM_UserC", guid = "{C}" },
          { name = "IEM_UserB", guid = "{B}" },
        },
      })
      api.reorders = 0
      local reorder = api.ReorderSelectedTracks
      api.ReorderSelectedTracks = function(...) api.reorders = api.reorders + 1; return reorder(...) end
      return api
    end

    it("adopts two strays below an emptied folder one after the other without reordering", function()
      local api = band_with_two_strays()
      assert.are.same({ status = "ok" }, run(api, "{C}"))
      assert.are.same({ 0, 1, 0, -1, 0 }, depths(api))
      assert.are.same({ status = "ok" }, run(api, "{B}"))
      assert.are.same({ "Dummy", "IEMs", "IEM_UserC", "IEM-Cue", "IEM_UserB" }, names(api))
      assert.are.same({ 0, 1, 0, 0, -1 }, depths(api))
      assert.are.equal(0, api.reorders)
      assert.are.same({ "IEM Setup: adopt mix", "IEM Setup: adopt mix" }, api.undo_steps)
    end)
  end)
end)
