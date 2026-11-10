local service = require("lib.bridge.service")
local store = require("lib.core.snapshot_store")
local fake_project = require("spec.support.fake_project")
local json = require("shared.bridge.json")

local SECTION = "LCRR_SNAPSHOTS"

local function bridge(api, now)
  local handler = service.new({ api = api, now = now or function() return 1000 end })
  return function(body)
    local _, reply = handler.handle(("q1|%d|%s"):format(#body, body))
    return json.decode and json.decode(reply) or reply
  end
end

local function show()
  return fake_project.new({
    path = "C:/Shows/Sunday/Sunday.rpp",
    tracks = {
      { name = "Kick", vol = 0.1, pan = -0.25, width = 0.5, dual_l = -0.5, dual_r = 0.75, pan_mode = 6, mute = 1,
        solo = 2, phase = 1, fx = 0,
        sends = { { to = "Bus", vol = 0.3, pan = 0.1, mute = 1, mode = 3 }, { to = "Bus", vol = 0.6 } },
        outputs = { { vol = 0.7, pan = 0.2, mode = 1 }, { vol = 0.8 } } },
      { name = "IEM_Drums", sends = { { to = "Bus" } } },
      { name = "Bus" },
    },
    master = { vol = 0.9, pan = 0.05, mute = 1, outputs = { { vol = 1, mode = 0 } } },
  })
end

describe("snapshot_save and snapshots", function()
  it("saves every track, the Master, sends and hardware outputs, exactly", function()
    local api = show()
    local reply = bridge(api)("cmd=snapshot_save&name=Verse")
    assert.is_truthy(reply:find('"status":"ok"', 1, true))
    assert.is_truthy(reply:find('"tracks":3', 1, true))
    assert.is_truthy(reply:find('"sends":6', 1, true))

    local list = assert(store.list(api))
    assert.are.equal(1, #list)
    assert.are.equal("Verse", list[1].name)
    assert.are.equal(1000, list[1].saved)
    local contents = assert(store.read(api, list[1]))
    assert.are.equal(4, #contents.tracks)

    local kick = contents.tracks[1]
    assert.are.equal("{GUID-1}", kick.guid)
    assert.are.equal(0.1, kick.vol)
    assert.are.equal(-0.25, kick.pan)
    assert.are.equal(0.5, kick.width)
    assert.are.equal(-0.5, kick.dual_l)
    assert.are.equal(0.75, kick.dual_r)
    assert.are.equal(6, kick.pan_mode)
    assert.are.equal(1, kick.mute)
    assert.are.equal(2, kick.solo)
    assert.are.equal(1, kick.phase)
    assert.are.equal(0, kick.fx)

    -- Sends of one source and destination keep their order; outputs are in track order.
    assert.are.same({ "{GUID-3}", "{GUID-3}" }, { kick.sends[1].dest, kick.sends[2].dest })
    local first = kick.sends[1]
    assert.are.same({ 0.3, 0.1, 1, 3 }, { first.vol, first.pan, first.mute, first.mode })
    assert.are.equal(0.6, kick.sends[2].vol)
    assert.are.same({ 0.7, 0.8 }, { kick.outputs[1].vol, kick.outputs[2].vol })
    assert.are.same({ 0.2, 1 }, { kick.outputs[1].pan, kick.outputs[1].mode })

    assert.are.equal("IEM_Drums", api.tracks[2].name)
    assert.are.equal("{GUID-2}", contents.tracks[2].guid) -- in-ear tracks are stored like the rest

    local master = contents.tracks[4]
    assert.are.equal("master", master.guid)
    assert.are.same({ 0.9, 0.05, 1 }, { master.vol, master.pan, master.mute })
    assert.are.equal(1, #master.outputs)
  end)

  it("lists in save order from the index alone, with counts and marks", function()
    local api = show()
    local ask = bridge(api)
    ask("cmd=snapshot_save&name=B")
    ask("cmd=snapshot_save&name=A")
    local reply = ask("cmd=snapshots")
    local first, second = reply:find('"name":"B"', 1, true), reply:find('"name":"A"', 1, true)
    assert.is_true(first < second)
    assert.is_truthy(reply:find('"solo":true', 1, true))
    assert.is_truthy(reply:find('"master_muted":true', 1, true))
    assert.is_truthy(reply:find('"saved":1000', 1, true))
    assert.is_truthy(reply:find('"tracks":3', 1, true))
  end)

  it("opens no undo block, marks the project dirty and writes the contents key before the index", function()
    local api = show()
    local order = {}
    local set = api.SetProjExtState
    api.SetProjExtState = function(p, section, key, value)
      order[#order + 1] = key
      return set(p, section, key, value)
    end
    bridge(api)("cmd=snapshot_save&name=Verse")
    assert.are.same({ "snapshot.1", "snapshots" }, order)
    assert.are.equal(0, api.undo_blocks)
    assert.is_true(api.dirty >= 1)
    assert.is_nil(api.ext.LCRR_IEM)
  end)

  it("lists nothing for a project with no snapshots", function()
    assert.is_truthy(bridge(show())("cmd=snapshots"):find('"snapshots":[]', 1, true))
  end)

  it("refuses every bad name before writing anything", function()
    local api = show()
    local ask = bridge(api)
    ask("cmd=snapshot_save&name=Verse")
    local before = api.ext[SECTION].snapshots
    local dirty = api.dirty
    for body, code in pairs({
      ["cmd=snapshot_save&name="] = "empty_name",
      ["cmd=snapshot_save&name=%20%20"] = "empty_name",
      ["cmd=snapshot_save&name=a%0Ab"] = "bad_name",
      ["cmd=snapshot_save&name=" .. ("x"):rep(41)] = "name_too_long",
      ["cmd=snapshot_save&name=Verse"] = "duplicate_name",
    }) do
      local reply = ask(body)
      assert.is_truthy(reply:find('"status":"refused"', 1, true), body)
      assert.is_truthy(reply:find('"code":"' .. code .. '"', 1, true), body .. " " .. reply)
    end
    assert.are.equal(before, api.ext[SECTION].snapshots)
    assert.are.equal(dirty, api.dirty)
    assert.is_nil(api.ext[SECTION]["snapshot.2"])
  end)

  it("never guesses at an unreadable index", function()
    local api = show()
    api.ext[SECTION] = { snapshots = "garbage" }
    local ask = bridge(api)
    assert.is_truthy(ask("cmd=snapshots"):find('"code":"unreadable"', 1, true))
    assert.is_truthy(ask("cmd=snapshot_save&name=X"):find('"code":"unreadable"', 1, true))
    assert.are.equal("garbage", api.ext[SECTION].snapshots)
  end)

  it("recognises a format it did not write", function()
    assert.is_nil(store.decode("V,2;T,x"))
    assert.is_nil(store.decode("V,1;T,{G},1,2"))
    assert.is_nil(store.decode("V,1;S,{G},1,0,0,0"))
  end)

  it("saves a large project (64 tracks, 600 sends) in one piece", function()
    local given = { path = "C:/Big.rpp", tracks = {}, master = { outputs = { {} } } }
    for i = 1, 64 do given.tracks[i] = { name = "T" .. i, vol = i / 64, sends = {} } end
    for i = 1, 600 do
      local source = given.tracks[(i % 63) + 1]
      source.sends[#source.sends + 1] = { to = "T64", vol = i / 1000, pan = (i % 7) / 10 - 0.3 }
    end
    local api = fake_project.new(given)
    local reply = bridge(api)("cmd=snapshot_save&name=Big")
    assert.is_truthy(reply:find('"tracks":64', 1, true))
    assert.is_truthy(reply:find('"sends":601', 1, true))
    local contents = assert(store.read(api, assert(store.list(api))[1]))
    assert.are.equal(65, #contents.tracks)
    assert.are.equal(1 / 64, contents.tracks[1].vol)
    local total = 0
    for _, t in ipairs(contents.tracks) do total = total + #t.sends end
    assert.are.equal(600, total)
  end)
end)

describe("snapshot_save overwrite and snapshot_delete", function()
  local function names(api)
    local out = {}
    for _, e in ipairs(assert(store.list(api))) do out[#out + 1] = e.name end
    return out
  end

  it("overwrites keeping name, id and list position, refreshing saved, contents and marks", function()
    local api = show()
    local clock = 1000
    local ask = bridge(api, function() return clock end)
    ask("cmd=snapshot_save&name=A")
    ask("cmd=snapshot_save&name=B")
    ask("cmd=snapshot_save&name=C")
    api.tracks[1].vol = 0.42
    api.GetMasterTrack(0).mute = 0
    clock = 2000
    local dirty = api.dirty
    local reply = ask("cmd=snapshot_save&name=B&overwrite=1")
    assert.is_truthy(reply:find('"status":"ok"', 1, true))
    assert.is_truthy(reply:find('"overwritten":true', 1, true))
    assert.are.same({ "A", "B", "C" }, names(api))
    local list = assert(store.list(api))
    assert.are.equal(2, list[2].id)
    assert.are.equal(2000, list[2].saved)
    assert.are.equal(1000, list[1].saved)
    assert.are.equal(store.MARK_SOLO, list[2].marks)
    assert.are.equal(0.42, assert(store.read(api, list[2])).tracks[1].vol)
    assert.are.equal(0.1, assert(store.read(api, list[1])).tracks[1].vol)
    assert.are.equal(0, api.undo_blocks)
    assert.is_true(api.dirty > dirty)
    assert.is_nil(api.ext[SECTION]["snapshot.4"])
  end)

  it("a plain save of a taken name is still refused; overwriting an unsaved name is not_found", function()
    local api = show()
    local ask = bridge(api)
    ask("cmd=snapshot_save&name=A")
    assert.is_truthy(ask("cmd=snapshot_save&name=A"):find('"code":"duplicate_name"', 1, true))
    local before, dirty = api.ext[SECTION].snapshots, api.dirty
    assert.is_truthy(ask("cmd=snapshot_save&name=Z&overwrite=1"):find('"code":"not_found"', 1, true))
    assert.are.equal(before, api.ext[SECTION].snapshots)
    assert.are.equal(dirty, api.dirty)
  end)

  it("deletes out of the index first, leaves no contents key, marks dirty and opens no undo block", function()
    local api = show()
    local ask = bridge(api)
    ask("cmd=snapshot_save&name=A")
    ask("cmd=snapshot_save&name=B")
    local order, set = {}, api.SetProjExtState
    api.SetProjExtState = function(p, section, key, value)
      order[#order + 1] = key
      return set(p, section, key, value)
    end
    local dirty = api.dirty
    local reply = ask("cmd=snapshot_delete&name=A")
    assert.is_truthy(reply:find('"status":"ok"', 1, true))
    assert.are.same({ "snapshots", "snapshot.1" }, order)
    assert.is_nil(api.ext[SECTION]["snapshot.1"])
    assert.is_truthy(api.ext[SECTION]["snapshot.2"])
    assert.are.same({ "B" }, names(api))
    assert.is_true(api.dirty > dirty)
    assert.are.equal(0, api.undo_blocks)
    ask("cmd=snapshot_delete&name=B")
    assert.are.same({}, names(api))
    assert.is_nil(api.ext[SECTION]["snapshot.2"])
  end)

  it("refuses a delete for each bad case without writing", function()
    local api = show()
    local ask = bridge(api)
    ask("cmd=snapshot_save&name=A")
    local before, dirty = api.ext[SECTION].snapshots, api.dirty
    for body, code in pairs({
      ["cmd=snapshot_delete&name="] = "empty_name",
      ["cmd=snapshot_delete&name=a%0Ab"] = "bad_name",
      ["cmd=snapshot_delete&name=" .. ("x"):rep(41)] = "name_too_long",
      ["cmd=snapshot_delete&name=Nope"] = "not_found",
    }) do
      assert.is_truthy(ask(body):find('"code":"' .. code .. '"', 1, true), body)
    end
    assert.are.equal(before, api.ext[SECTION].snapshots)
    assert.are.equal(dirty, api.dirty)
    api.ext[SECTION].snapshots = "garbage"
    assert.is_truthy(ask("cmd=snapshot_delete&name=A"):find('"code":"unreadable"', 1, true))
    assert.is_truthy(ask("cmd=snapshot_save&name=A&overwrite=1"):find('"code":"unreadable"', 1, true))
    assert.are.equal("garbage", api.ext[SECTION].snapshots)
  end)
end)
