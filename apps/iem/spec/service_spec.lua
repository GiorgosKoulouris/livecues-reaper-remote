local service = require("lib.bridge.service")
local fake_project = require("spec.support.fake_project")

local function ask(tracks, body, path)
  local handler = service.new({ api = fake_project.new({ path = path or "D:/Gig/Night.RPP", tracks = tracks or {} }) })
  local id, reply = handler.handle(("r1|%d|%s"):format(#body, body))
  return id, reply
end

describe("the state command", function()
  it("answers under the request's id, with the project and no status other than ok", function()
    local id, reply = ask({ { name = "Kick" } }, "cmd=state")
    assert.are.equal("r1", id)
    assert.is_truthy(reply:find('"command":"state"', 1, true))
    assert.is_truthy(reply:find('"status":"ok"', 1, true))
    assert.is_truthy(reply:find('"project":{"name":"Night","path":"D:/Gig/Night.RPP"}', 1, true))
    assert.is_truthy(reply:find('"v":1', 1, true))
  end)

  it("names the project even when it has never been saved", function()
    local _, reply = ask({}, "cmd=state", "")
    assert.is_truthy(reply:find('"project":{"name":"","path":""}', 1, true))
  end)

  it("carries mixes, sources and the folder", function()
    local _, reply = ask({
      { name = "Kick" }, { name = "IEMs", depth = 1 }, { name = "IEM_A", depth = -1, outputs = { { dest = 0 } } },
    }, "cmd=state")
    assert.is_truthy(reply:find('"mixes":[{', 1, true))
    assert.is_truthy(reply:find('"sources":[{', 1, true))
    assert.is_truthy(reply:find('"folder":{"guid":"{GUID-2}","is_folder":true,"tracks_after":false}', 1, true))
    assert.is_truthy(reply:find('"in_folder":true', 1, true))
  end)

  it("refuses an unknown command by code", function()
    local _, reply = ask({}, "cmd=lock")
    assert.is_truthy(reply:find('"code":"unknown_command"', 1, true))
  end)

  it("says so when REAPER refuses a call, instead of going silent", function()
    local api = fake_project.new({ tracks = { { name = "Kick" } } })
    api.CountTracks = function() error("boom") end
    local _, reply = service.new({ api = api }).handle("r1|9|cmd=state")
    assert.is_truthy(reply:find('"code":"internal"', 1, true))
  end)

  it("answers nothing to a request with no readable id", function()
    local id = service.new({ api = fake_project.new({}) }).handle("garbage")
    assert.is_nil(id)
  end)
end)

describe("the write commands", function()
  local function ask_api(api, body)
    local _, reply = service.new({ api = api }).handle(("w1|%d|%s"):format(#body, body))
    return reply
  end

  it("create answers with the new GUID, whether the folder was made, and the project", function()
    local api = fake_project.new({ path = "D:/Gig/Night.RPP", tracks = { { name = "Kick" } } })
    local reply = ask_api(api, "cmd=create&name=Drummer")
    assert.is_truthy(reply:find('"command":"create"', 1, true))
    assert.is_truthy(reply:find('"status":"ok"', 1, true))
    assert.is_truthy(reply:find('"folder_created":true', 1, true))
    assert.is_truthy(reply:find('"guid":"{NEW-2}"', 1, true))
    assert.is_truthy(reply:find('"project":{"name":"Night"', 1, true))
    assert.are.same({ "IEM Setup: create mix" }, api.undo_steps)
  end)

  it("decodes a percent-encoded name", function()
    local api = fake_project.new({ tracks = {} })
    ask_api(api, "cmd=create&name=Lead%20%26%20Keys")
    assert.are.equal("IEM_Lead & Keys", api.tracks[2].name)
  end)

  it("refuses by code, and a GUID that has gone", function()
    local api = fake_project.new({ tracks = { { name = "IEM_A" } } })
    assert.is_truthy(ask_api(api, "cmd=create&name=A"):find('"code":"duplicate_name"', 1, true))
    assert.is_truthy(ask_api(api, "cmd=rename&guid=%7BGONE%7D&name=B"):find('"code":"track_gone"', 1, true))
    assert.is_truthy(ask_api(api, "cmd=move_to_end&guid=%7BGONE%7D"):find('"code":"track_gone"', 1, true))
    assert.is_truthy(ask_api(api, "cmd=delete&guid=%7BGONE%7D"):find('"code":"track_gone"', 1, true))
    assert.is_truthy(ask_api(api, "cmd=colour&colour=red"):find('"code":"bad_colour"', 1, true))
    assert.are.same({}, api.undo_steps)
  end)
end)
