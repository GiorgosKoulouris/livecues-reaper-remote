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

local scenarios = {
  { "state", function() return bridge()("cmd=state") end },
  { "state_unsaved", function() return bridge("")("cmd=state") end },
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
