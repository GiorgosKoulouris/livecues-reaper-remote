-- The replies the web page is written against, recorded from the real service.
--
-- test/fixtures/bridge-replies.txt holds one line per scenario: `<name>\t<reply json>`. This spec compares what the
-- service says now with that file, so a change to a reply's shape cannot go unnoticed; test/words.test.js then pushes
-- the same file through the page's logic, so the page cannot drift from it.
-- After a deliberate change: LCRR_RECORD_BRIDGE=1 busted spec/bridge_contract_spec.lua, and read the diff.

local service = require("lib.bridge.service")
local fake_project = require("spec.support.fake_project")

local FIXTURE = "test/fixtures/bridge-replies.txt"
local PATH = "C:/Shows/Sunday/Sunday.rpp"

local function raw(id, body)
  return ("%s|%d|%s"):format(id, #body, body)
end

local function bridge(path)
  local handler = service.new({ api = fake_project.new({ path = path or PATH }) })
  return function(body)
    local _, reply = handler.handle(raw("q1", body))
    return reply
  end
end

local function saved_bridge()
  local api = fake_project.new({
    path = PATH,
    tracks = {
      { name = "Kick", vol = 0.5, solo = 1, sends = { { to = "Bus", vol = 0.7 } }, outputs = { {} } },
      { name = "Bus" },
    },
    master = { mute = 1, outputs = { {} } },
  })
  local handler = service.new({ api = api, now = function() return 1731240000 end })
  return function(body)
    local _, reply = handler.handle(raw("q1", body))
    return reply
  end, api
end

local scenarios = {
  { "state", function() return bridge()("cmd=state") end },
  { "state_unsaved", function() return bridge("")("cmd=state") end },
  { "snapshots_empty", function() return saved_bridge()("cmd=snapshots") end },
  { "snapshot_save", function() return saved_bridge()("cmd=snapshot_save&name=Verse") end },
  { "snapshots", function()
    local ask = saved_bridge()
    ask("cmd=snapshot_save&name=Verse")
    ask("cmd=snapshot_save&name=Chorus")
    return ask("cmd=snapshots")
  end },
  { "snapshot_save_empty_name", function() return saved_bridge()("cmd=snapshot_save&name=%20") end },
  { "snapshot_save_bad_name", function() return saved_bridge()("cmd=snapshot_save&name=a%0Ab") end },
  { "snapshot_save_name_too_long", function() return saved_bridge()("cmd=snapshot_save&name=" .. ("x"):rep(41)) end },
  { "snapshot_save_duplicate_name", function()
    local ask = saved_bridge()
    ask("cmd=snapshot_save&name=Verse")
    return ask("cmd=snapshot_save&name=Verse")
  end },
  { "snapshot_overwrite", function()
    local ask = saved_bridge()
    ask("cmd=snapshot_save&name=Verse")
    return ask("cmd=snapshot_save&name=Verse&overwrite=1")
  end },
  { "snapshot_overwrite_not_found", function()
    return saved_bridge()("cmd=snapshot_save&name=Verse&overwrite=1")
  end },
  { "snapshot_delete", function()
    local ask = saved_bridge()
    ask("cmd=snapshot_save&name=Verse")
    return ask("cmd=snapshot_delete&name=Verse")
  end },
  { "snapshot_delete_empty_name", function() return saved_bridge()("cmd=snapshot_delete&name=%20") end },
  { "snapshot_delete_bad_name", function() return saved_bridge()("cmd=snapshot_delete&name=a%0Ab") end },
  { "snapshot_delete_name_too_long", function()
    return saved_bridge()("cmd=snapshot_delete&name=" .. ("x"):rep(41))
  end },
  { "snapshot_delete_not_found", function() return saved_bridge()("cmd=snapshot_delete&name=Verse") end },
  { "snapshot_delete_unreadable", function()
    local ask, api = saved_bridge()
    api.ext.LCRR_SNAPSHOTS = { snapshots = "garbage" }
    return ask("cmd=snapshot_delete&name=Verse")
  end },
  { "snapshots_unreadable", function()
    local ask, api = saved_bridge()
    api.ext.LCRR_SNAPSHOTS = { snapshots = "garbage" }
    return ask("cmd=snapshots")
  end },
  { "snapshot_restore", function()
    local ask = saved_bridge()
    ask("cmd=snapshot_save&name=Verse")
    return ask("cmd=snapshot_restore&name=Verse&ticks=LPMSRE")
  end },
  { "snapshot_restore_in_ears", function()
    local ask = saved_bridge()
    ask("cmd=snapshot_save&name=Verse")
    return ask("cmd=snapshot_restore&name=Verse&ticks=I")
  end },
  { "snapshot_restore_no_ticks", function()
    local ask = saved_bridge()
    ask("cmd=snapshot_save&name=Verse")
    return ask("cmd=snapshot_restore&name=Verse&ticks=")
  end },
  { "snapshot_restore_not_found", function() return saved_bridge()("cmd=snapshot_restore&name=Nope&ticks=L") end },
  { "unknown_command", function() return bridge()("cmd=nope") end },
  { "request_truncated", function()
    local _, reply = service.new({ api = fake_project.new({ path = PATH }) }).handle("q1|40|cmd=sta")
    return reply
  end },
  { "bad_request", function()
    local _, reply = service.new({ api = fake_project.new({ path = PATH }) }).handle("q1|3|cmd")
    return reply
  end },
}

local function recorded()
  local handle = io.open(FIXTURE, "r")
  if not handle then return {} end
  local found = {}
  for line in handle:lines() do
    local name, reply = line:match("^([^\t]+)\t(.*)$")
    found[name] = reply
  end
  handle:close()
  return found
end

describe("bridge replies the page is written against", function()
  local expected = recorded()
  local lines = {}

  for _, scenario in ipairs(scenarios) do
    local name, play = scenario[1], scenario[2]
    local reply = play()
    lines[#lines + 1] = name .. "\t" .. reply

    it(name .. " matches test/fixtures/bridge-replies.txt", function()
      if os.getenv("LCRR_RECORD_BRIDGE") then return end
      assert.are.equal(expected[name], reply)
    end)
  end

  if os.getenv("LCRR_RECORD_BRIDGE") then
    local handle = assert(io.open(FIXTURE, "w"))
    handle:write(table.concat(lines, "\n"), "\n")
    handle:close()
  end
end)
