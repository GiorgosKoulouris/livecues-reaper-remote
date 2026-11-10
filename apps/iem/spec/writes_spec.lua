local create = require("lib.core.create")
local rename = require("lib.core.rename")
local colour = require("lib.core.colour")
local move_to_end = require("lib.core.move_to_end")
local delete = require("lib.core.delete")
local state = require("lib.core.state")
local fake_project = require("spec.support.fake_project")

local function project(tracks, ext)
  return fake_project.new({ tracks = tracks, ext = ext })
end

local function run(core, api, fields)
  return core.run({ api = api, fields = fields })
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

local function native(r, g, b) return (r + g * 256 + b * 65536) | 0x1000000 end

local function assert_one_undo_step(api, description)
  assert.are.same({}, api.outside_block)
  assert.are.equal(0, api.open_blocks)
  assert.are.same({ description }, api.undo_steps)
end

describe("create", function()
  describe("the first mix", function()
    it("makes the IEMs folder at the end of the list, with the mix inside it", function()
      local api = project({ { name = "Kick" }, { name = "Bass" } })
      local result = run(create, api, { name = "Drummer" })
      assert.are.equal("ok", result.status)
      assert.is_true(result.folder_created)
      assert.are.same({ "Kick", "Bass", "IEMs", "IEM_Drummer", "IEM-Cue" }, names(api))
      assert.are.same({ 0, 0, 1, 0, -1 }, depths(api))
      assert.are.equal(result.guid, api.tracks[4].guid)
    end)

    it("turns master send off on the folder and the mix, and colours both", function()
      local api = project({ { name = "Kick" } })
      run(create, api, { name = "A" })
      assert.are.equal(0, api.tracks[2].main_send)
      assert.are.equal(0, api.tracks[3].main_send)
      assert.are.equal(native(0x3b, 0x82, 0xc4), api.tracks[2].colour)
      assert.are.equal(api.tracks[2].colour, api.tracks[3].colour)
    end)

    it("uses the colour stored in the project", function()
      local api = project({}, { ["LCRR_IEM/colour"] = "ff8000" })
      run(create, api, { name = "A" })
      assert.are.equal(native(255, 128, 0), api.tracks[1].colour)
      assert.are.equal(native(255, 128, 0), api.tracks[2].colour)
    end)

    it("is one undo step", function()
      local api = project({ { name = "Kick" } })
      run(create, api, { name = "A" })
      assert_one_undo_step(api, "IEM Setup: create mix")
    end)
  end)

  describe("a later mix", function()
    local function band()
      return project({
        { name = "Kick" },
        { name = "IEMs", depth = 1, main_send = false },
        { name = "IEM_A", main_send = false },
        { name = "IEM_B", main_send = false, depth = -1 },
        { name = "FOH" },
      })
    end

    it("goes after the folder's last member, which stops closing it", function()
      local api = band()
      local result = run(create, api, { name = "C" })
      assert.is_false(result.folder_created)
      assert.are.same({ "Kick", "IEMs", "IEM_A", "IEM_B", "IEM_C", "IEM-Cue", "FOH" }, names(api))
      assert.are.same({ 0, 1, 0, 0, 0, -1, 0 }, depths(api))
      assert.are.equal(0, api.tracks[5].main_send)
      assert.are.equal(1, api.tracks[7].main_send) -- the track after is not touched
    end)

    it("makes no second folder, and is one undo step", function()
      local api = band()
      run(create, api, { name = "C" })
      local count = 0
      for _, name in ipairs(names(api)) do if name == "IEMs" then count = count + 1 end end
      assert.are.equal(1, count)
      assert_one_undo_step(api, "IEM Setup: create mix")
    end)

    it("closes a parent of the folder too when the last member did", function()
      local api = project({
        { name = "Group", depth = 1 },
        { name = "IEMs", depth = 1 },
        { name = "IEM_A", depth = -2 },
      })
      run(create, api, { name = "B" })
      assert.are.same({ 1, 1, 0, 0, -2 }, depths(api))
    end)

    it("reopens an emptied folder, which is a plain track, and puts the mix right after it", function()
      local api = project({ { name = "Kick" }, { name = "IEMs" }, { name = "FOH" } })
      run(create, api, { name = "A" })
      assert.are.same({ "Kick", "IEMs", "IEM_A", "IEM-Cue", "FOH" }, names(api))
      assert.are.same({ 0, 1, 0, -1, 0 }, depths(api))
    end)

    it("keeps what an emptied folder closed when it reopens", function()
      local api = project({ { name = "Group", depth = 1 }, { name = "IEMs", depth = -1 } })
      run(create, api, { name = "A" })
      assert.are.same({ 1, 1, 0, -2 }, depths(api))
    end)

    it("fills an open folder that holds nothing", function()
      local api = project({ { name = "IEMs", depth = 1 } })
      run(create, api, { name = "A" })
      assert.are.same({ 1, 0, -1 }, depths(api))
    end)

    it("leaves the state reading it as in the folder", function()
      local api = band()
      run(create, api, { name = "C" })
      local read = state.run({ api = api })
      assert.is_true(read.mixes[3].in_folder)
      assert.are.equal("C", read.mixes[3].name)
    end)
  end)

  describe("copy from a mix (issue 09)", function()
    local function band()
      return project({
        { name = "Kick", guid = "{K}" },
        { name = "Snare", guid = "{S}" },
        { name = "Vox", guid = "{V}" },
        { name = "IEMs", guid = "{F}", depth = 1 },
        { name = "IEM_A", guid = "{A}", depth = -1, outputs = { { dest = 2, src = 0 } },
          receives = {
            { from = "Kick", vol = 0.5, pan = -0.25, muted = true, mode = 0 },
            { from = "Snare", vol = 0.8, pan = 0.5, mode = 3 },
            { from = "IEMs", vol = 0.3, mode = 3 },
          } },
      })
    end
    local function copy(api, guid)
      return run(create, api, { name = "B", copy = guid })
    end

    it("gives the new mix the same sources with their level, pan, mute and signal point", function()
      local api = band()
      local reply = copy(api, "{A}")
      assert.are.equal("ok", reply.status)
      local new = api.tracks[6]
      assert.are.equal("IEM_B", new.name)
      assert.are.equal(2, #new.receives)
      local kick, snare = new.receives[1], new.receives[2]
      assert.are.equal(api.tracks[1], kick.src_track)
      assert.are.same({ 0.5, -0.25, true, 0 }, { kick.vol, kick.pan, kick.muted, kick.mode })
      assert.are.equal(api.tracks[2], snare.src_track)
      assert.are.same({ 0.8, 0.5, false, 3 }, { snare.vol, snare.pan, snare.muted or false, snare.mode })
    end)

    it("leaves the source mix's sends alone", function()
      local api = band()
      copy(api, "{A}")
      assert.are.equal(3, #api.tracks[5].receives)
      assert.are.equal(0.5, api.tracks[5].receives[1].vol)
    end)

    it("does not copy a send that comes from the IEMs folder or another mix", function()
      local api = band()
      copy(api, "{A}")
      for _, receive in ipairs(api.tracks[6].receives) do
        assert.are_not.equal(api.tracks[4], receive.src_track)
      end
    end)

    it("leaves the new mix without an output", function()
      local api = band()
      copy(api, "{A}")
      assert.are.same({}, api.tracks[6].outputs)
      assert.are.equal(1, #api.tracks[5].outputs)
    end)

    it("is one undo step with the creation", function()
      local api = band()
      copy(api, "{A}")
      assert_one_undo_step(api, "IEM Setup: create mix")
    end)

    it("without a copy creates no sends", function()
      local api = band()
      run(create, api, { name = "B" })
      assert.are.same({}, api.tracks[6].receives)
    end)

    it("refuses a source mix that has gone, before anything changes", function()
      local api = band()
      local reply = copy(api, "{GONE}")
      assert.are.same({ status = "refused", error = { code = "track_gone" } }, reply)
      assert.are.equal(6 - 1, #api.tracks)
      assert.are.same({}, api.undo_steps)
      assert.are.same({}, api.outside_block)
    end)

    it("refuses a copy from a track that is not a mix", function()
      local api = band()
      local reply = copy(api, "{K}")
      assert.are.same({ status = "refused", error = { code = "not_a_mix" } }, reply)
      assert.are.same({}, api.undo_steps)
    end)

    it("still checks the name first", function()
      local api = band()
      local reply = run(create, api, { name = "A", copy = "{GONE}" })
      assert.are.equal("duplicate_name", reply.error.code)
    end)

    it("copies into a first-ever folder too", function()
      local api = project({
        { name = "Kick", guid = "{K}" },
        { name = "IEM_A", guid = "{A}", receives = { { from = "Kick", vol = 0.4, mode = 3 } } },
      })
      local reply = copy(api, "{A}")
      assert.are.equal("ok", reply.status)
      local new = api.tracks[4]
      assert.are.equal("IEM_B", new.name)
      assert.are.equal(0.4, new.receives[1].vol)
    end)
  end)

  describe("names", function()
    it("trims the name and never takes the prefix from the page", function()
      local api = project({})
      run(create, api, { name = "  Drummer  " })
      assert.are.equal("IEM_Drummer", api.tracks[2].name)
    end)

    it("refuses an empty name, or only spaces, and changes nothing", function()
      for _, bad in ipairs({ "", "   ", nil }) do
        local api = project({ { name = "Kick" } })
        local result = run(create, api, { name = bad })
        assert.are.same({ status = "refused", error = { code = "empty_name" } }, result)
        assert.are.same({ "Kick" }, names(api))
        assert.are.same({}, api.undo_steps)
      end
    end)

    it("refuses a name another mix has, even a stray one", function()
      local api = project({ { name = "IEM_Drums" }, { name = "IEMs", depth = 1 }, { name = "IEM_Bass", depth = -1 } })
      for _, taken in ipairs({ "Drums", "Bass" }) do
        local result = run(create, api, { name = taken })
        assert.are.equal("duplicate_name", result.error.code)
      end
      assert.are.equal(3, #api.tracks)
      assert.are.same({}, api.undo_steps)
    end)

    it("treats names as exact: a different case is another mix", function()
      local api = project({ { name = "IEM_Drums" } })
      assert.are.equal("ok", run(create, api, { name = "drums" }).status)
    end)
  end)

  it("closes the undo block even when REAPER fails part way", function()
    local api = project({})
    api.InsertTrackAtIndex = function() error("boom") end
    assert.has_error(function() run(create, api, { name = "A" }) end)
    assert.are.equal(0, api.open_blocks)
  end)
end)

describe("rename", function()
  local function band()
    return project({
      { name = "Kick" },
      { name = "IEMs", depth = 1 },
      { name = "IEM_A", guid = "{A}" },
      { name = "IEM_A", guid = "{A2}", depth = -1 },
    })
  end

  it("renames a mix by GUID and keeps the prefix", function()
    local api = band()
    local result = run(rename, api, { guid = "{A}", name = "Singer" })
    assert.are.same({ status = "ok", changed = true }, result)
    assert.are.equal("IEM_Singer", api.tracks[3].name)
    assert_one_undo_step(api, "IEM Setup: rename mix")
  end)

  it("lets two existing duplicates be renamed apart, but not to each other's name", function()
    local api = band()
    assert.are.equal("ok", run(rename, api, { guid = "{A2}", name = "B" }).status)
    assert.are.equal("duplicate_name", run(rename, api, { guid = "{A2}", name = "A" }).error.code)
    assert.are.same({ "Kick", "IEMs", "IEM_A", "IEM_B" }, names(api))
  end)

  it("refuses an empty name and a taken one", function()
    local api = band()
    assert.are.equal("empty_name", run(rename, api, { guid = "{A}", name = " " }).error.code)
    api.tracks[4].name = "IEM_B"
    assert.are.equal("duplicate_name", run(rename, api, { guid = "{A}", name = "B" }).error.code)
    assert.are.same({}, api.undo_steps)
  end)

  it("treats the mix's own name as no change and opens no undo step", function()
    local api = band()
    assert.are.same({ status = "ok", changed = false }, run(rename, api, { guid = "{A}", name = "A" }))
    assert.are.same({}, api.undo_steps)
  end)

  it("refuses a target that has gone", function()
    local api = band()
    local result = run(rename, api, { guid = "{GONE}", name = "X" })
    assert.are.same({ status = "refused", error = { code = "track_gone" } }, result)
    assert.are.same({ "Kick", "IEMs", "IEM_A", "IEM_A" }, names(api))
    assert.are.same({}, api.undo_steps)
  end)

  it("refuses to rename a track that is not a mix", function()
    local api = band()
    api.tracks[1].guid = "{KICK}"
    assert.are.equal("not_a_mix", run(rename, api, { guid = "{KICK}", name = "X" }).error.code)
  end)
end)

describe("colour", function()
  local function band()
    return project({
      { name = "Kick" },
      { name = "IEM_Stray" },
      { name = "IEMs", depth = 1 },
      { name = "IEM_A" },
      { name = "IEM_B", depth = -1 },
    })
  end

  it("is stored in the project and recolours the folder and every mix in it, not a stray or a source", function()
    local api = band()
    local result = run(colour, api, { colour = "FF8000" })
    assert.are.same({ status = "ok", colour = "ff8000" }, result)
    assert.are.equal("ff8000", api.ext["LCRR_IEM/colour"])
    local want = native(255, 128, 0)
    assert.are.same({ 0, 0, want, want, want }, {
      api.tracks[1].colour, api.tracks[2].colour, api.tracks[3].colour, api.tracks[4].colour, api.tracks[5].colour,
    })
    assert_one_undo_step(api, "IEM Setup: change colour")
  end)

  it("is stored even before the folder exists, and the first create then uses it", function()
    local api = project({ { name = "Kick" } })
    run(colour, api, { colour = "00ff00" })
    run(create, api, { name = "A" })
    assert.are.equal(native(0, 255, 0), api.tracks[3].colour)
  end)

  it("refuses anything that is not six hex digits", function()
    for _, bad in ipairs({ "", "#ff8000", "ff80", "gg0000", "ff80000" }) do
      local api = band()
      assert.are.equal("bad_colour", run(colour, api, { colour = bad }).error.code)
      assert.are.same({}, api.undo_steps)
    end
    assert.are.equal("bad_colour", run(colour, band(), {}).error.code)
  end)

  it("shows in the state", function()
    local api = band()
    assert.are.equal("3b82c4", state.run({ api = api }).colour)
    run(colour, api, { colour = "ff8000" })
    assert.are.equal("ff8000", state.run({ api = api }).colour)
  end)
end)

describe("move_to_end", function()
  local function band()
    return project({
      { name = "IEMs", depth = 1, guid = "{F}" },
      { name = "IEM_A" },
      { name = "IEM_B", depth = -1 },
      { name = "Kick", guid = "{K}", selected = true },
      { name = "FOH" },
    })
  end

  it("moves the folder and its mixes to the end, keeping their depths", function()
    local api = band()
    local result = run(move_to_end, api, { guid = "{F}" })
    assert.are.same({ status = "ok" }, result)
    assert.are.same({ "Kick", "FOH", "IEMs", "IEM_A", "IEM_B" }, names(api))
    assert.are.same({ 0, 0, 1, 0, -1 }, depths(api))
    assert_one_undo_step(api, "IEM Setup: move IEMs folder to end")
  end)

  it("puts the engineer's track selection back", function()
    local api = band()
    run(move_to_end, api, { guid = "{F}" })
    local selected = {}
    for _, track in ipairs(api.tracks) do if track.selected then selected[#selected + 1] = track.name end end
    assert.are.same({ "Kick" }, selected)
  end)

  it("is refused when nothing sits after the folder", function()
    local api = project({
      { name = "Kick" }, { name = "IEMs", depth = 1, guid = "{F}" }, { name = "IEM_A", depth = -1 },
    })
    assert.are.equal("nothing_to_move", run(move_to_end, api, { guid = "{F}" }).error.code)
    assert.are.same({}, api.undo_steps)
  end)

  it("moves an emptied folder too", function()
    local api = project({ { name = "IEMs", guid = "{F}" }, { name = "Kick" } })
    assert.are.equal("ok", run(move_to_end, api, { guid = "{F}" }).status)
    assert.are.same({ "Kick", "IEMs" }, names(api))
  end)

  it("is refused for a target that has gone, or one that is not the folder", function()
    local api = band()
    assert.are.equal("track_gone", run(move_to_end, api, { guid = "{GONE}" }).error.code)
    assert.are.equal("not_the_folder", run(move_to_end, api, { guid = "{K}" }).error.code)
    assert.are.same({}, api.undo_steps)
  end)

  it("never happens by itself: create leaves tracks after the folder where they are", function()
    local api = band()
    run(create, api, { name = "C" })
    assert.are.same({ "IEMs", "IEM_A", "IEM_B", "IEM_C", "IEM-Cue", "Kick", "FOH" }, names(api))
  end)

  it("is offered by the state exactly while tracks sit after the folder", function()
    local api = band()
    assert.is_true(state.run({ api = api }).folder.tracks_after)
    run(move_to_end, api, { guid = "{F}" })
    assert.is_truthy(state.run({ api = api }).folder)
  end)
end)

describe("delete", function()
  local function band()
    return project({
      { name = "Kick" },
      { name = "IEMs", depth = 1, guid = "{F}" },
      { name = "IEM_A", guid = "{A}", receives = { { from = "Kick" } } },
      { name = "IEM_B", depth = -1, guid = "{B}" },
      { name = "FOH" },
    })
  end

  it("removes the mix and its sends, in one undo step", function()
    local api = band()
    local result = run(delete, api, { guid = "{A}" })
    assert.are.equal("ok", result.status)
    assert.are.same({ "Kick", "IEMs", "IEM_B", "FOH" }, names(api))
    assert.are.same({ 0, 1, -1, 0 }, depths(api))
    assert_one_undo_step(api, "IEM Setup: delete mix")
  end)

  it("deletes a mix that is the first track without a predecessor to repair", function()
    local api = project({
      { name = "IEM_A", depth = -1, guid = "{A}" },
      { name = "Kick" },
    })
    local result = run(delete, api, { guid = "{A}" })
    assert.are.equal("ok", result.status)
    assert.are.same({ "Kick" }, names(api))
  end)

  it("gives the previous member the closing depth when the last mix goes", function()
    local api = band()
    run(delete, api, { guid = "{B}" })
    assert.are.same({ "Kick", "IEMs", "IEM_A", "FOH" }, names(api))
    assert.are.same({ 0, 1, -1, 0 }, depths(api))
  end)

  it("leaves the folder as a plain track when its only mix goes", function()
    local api = project({
      { name = "IEMs", depth = 1 }, { name = "IEM_A", depth = -1, guid = "{A}" }, { name = "FOH" },
    })
    run(delete, api, { guid = "{A}" })
    assert.are.same({ "IEMs", "FOH" }, names(api))
    assert.are.same({ 0, 0 }, depths(api))
    assert.is_truthy(state.run({ api = api }).folder)
  end)

  it("keeps what the only mix closed beyond the folder", function()
    local api = project({
      { name = "Stage", depth = 1 },
      { name = "IEMs", depth = 1 },
      { name = "IEM_A", depth = -2, guid = "{A}" },
      { name = "FOH" },
    })
    run(delete, api, { guid = "{A}" })
    assert.are.same({ 1, -1, 0 }, depths(api))
  end)

  it("keeps a folder around the IEMs folder closed when its last mix goes", function()
    local api = project({
      { name = "Stage", depth = 1 },
      { name = "IEMs", depth = 1 },
      { name = "IEM_A", guid = "{A}" },
      { name = "IEM_B", depth = -2, guid = "{B}" },
    })
    run(delete, api, { guid = "{B}" })
    assert.are.same({ 1, 1, -2 }, depths(api))
  end)

  it("does not break another folder when a stray inside it goes", function()
    local api = project({
      { name = "Band", depth = 1 },
      { name = "Bass" },
      { name = "IEM_Stray", depth = -1, guid = "{S}" },
      { name = "IEMs", depth = 1 },
      { name = "IEM_A", depth = -1 },
    })
    run(delete, api, { guid = "{S}" })
    assert.are.same({ 1, -1, 1, -1 }, depths(api))
  end)

  it("turns a folder that held only the stray into a plain track", function()
    local api = project({
      { name = "Band", depth = 1 }, { name = "IEM_Stray", depth = -1, guid = "{S}" }, { name = "FOH" },
    })
    run(delete, api, { guid = "{S}" })
    assert.are.same({ 0, 0 }, depths(api))
  end)

  it("leaves the closing of a mix that was itself a folder to the track that closed it", function()
    local api = project({
      { name = "IEM_P", depth = 1, guid = "{P}" },
      { name = "Child", depth = -1 },
      { name = "FOH" },
    })
    run(delete, api, { guid = "{P}" })
    assert.are.same({ 0, 0 }, depths(api))
  end)

  it("never touches a mix in the middle of a folder's depths", function()
    local api = band()
    api.tracks[3].depth = 0
    run(delete, api, { guid = "{A}" })
    assert.are.same({ 0, 1, -1, 0 }, depths(api))
  end)

  it("is refused for a target that has gone, with no undo step", function()
    local api = band()
    local result = run(delete, api, { guid = "{GONE}" })
    assert.are.same({ status = "refused", error = { code = "track_gone" } }, result)
    assert.are.equal(5, #api.tracks)
    assert.are.same({}, api.undo_steps)
    assert.are.same({}, api.outside_block)
  end)

  it("is refused for anything that is not a mix: the folder, a source, a bare prefix", function()
    local api = project({ { name = "Kick", guid = "{K}" }, { name = "IEMs", depth = 1, guid = "{F}" },
      { name = "IEM_", depth = -1, guid = "{E}" } })
    for _, guid in ipairs({ "{K}", "{F}", "{E}" }) do
      assert.are.equal("not_a_mix", run(delete, api, { guid = guid }).error.code)
    end
    assert.are.equal(3, #api.tracks)
    assert.are.same({}, api.undo_steps)
  end)

  it("deleting every mix in turn leaves a valid project", function()
    local api = band()
    run(delete, api, { guid = "{B}" })
    run(delete, api, { guid = "{A}" })
    assert.are.same({ "Kick", "IEMs", "FOH" }, names(api))
    assert.are.same({ 0, 0, 0 }, depths(api))
  end)

  it("lets create reopen the emptied folder afterwards", function()
    local api = band()
    run(delete, api, { guid = "{B}" })
    run(delete, api, { guid = "{A}" })
    run(create, api, { name = "C" })
    assert.are.same({ 0, 1, 0, -1, 0 }, depths(api))
  end)
end)
