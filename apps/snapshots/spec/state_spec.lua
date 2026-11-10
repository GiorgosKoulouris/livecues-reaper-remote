local service = require("lib.bridge.service")
local fake_project = require("spec.support.fake_project")

describe("state", function()
  local function ask(path)
    local handler = service.new({ api = fake_project.new({ path = path }) })
    local body = "cmd=state"
    return handler.handle(("q1|%d|%s"):format(#body, body))
  end

  it("reports the active project's name and path", function()
    local id, reply = ask("C:/Shows/Sunday/Sunday.rpp")
    assert.are.equal("q1", id)
    assert.are.equal(
      '{"command":"state","project":{"name":"Sunday","path":"C:/Shows/Sunday/Sunday.rpp"},"status":"ok","v":1}', reply)
  end)

  it("reports an unsaved project with an empty name", function()
    local _, reply = ask("")
    assert.is_truthy(reply:find('"project":{"name":"","path":""}', 1, true))
  end)
end)
