-- The Arrange bridge's check tokens (JSON and request parsing are shared:
-- shared/spec/bridge_wire_spec.lua). The service built from them is spec/bridge_service_spec.lua.

local tokens = require("lib.bridge.tokens")

describe("lib/bridge/tokens.lua", function()
  local function counting()
    local n = 0
    return function(max)
      n = n + 1
      return (n - 1) % max + 1
    end
  end

  it("remembers what a Check saw", function()
    local store = tokens.new(counting())
    local token = store.issue({ name = "Radio", path = "/p.rpp", changes = 7 })
    assert.are.same({ name = "Radio", path = "/p.rpp", changes = 7 }, store.get(token))
  end)

  it("makes short tokens, each different", function()
    local store = tokens.new()
    local seen = {}
    for _ = 1, 50 do
      local token = store.issue({})
      assert.are.equal(6, #token)
      assert.is_nil(seen[token])
      seen[token] = true
    end
  end)

  it("does not reuse a token that is in the store", function()
    -- Six picks per token: the first token is "aaaaaa", the generator then
    -- offers "aaaaaa" again, and only the third try differs.
    local calls = 0
    local store = tokens.new(function()
      calls = calls + 1
      return calls <= 12 and 1 or 2
    end)
    assert.are.equal("aaaaaa", store.issue({}))
    assert.are.equal("bbbbbb", store.issue({}))
  end)

  it("does not know a token it never issued, or one that was dropped", function()
    local store = tokens.new()
    local token = store.issue({ name = "x" })
    assert.is_nil(store.get("nope"))
    store.drop(token)
    assert.is_nil(store.get(token))
    store.drop(token)
  end)

  it("forgets the oldest token past its capacity", function()
    local store = tokens.new()
    local first = store.issue({ n = 0 })
    local last
    for n = 1, tokens.CAPACITY do
      last = store.issue({ n = n })
    end
    assert.is_nil(store.get(first))
    assert.is_not_nil(store.get(last))
  end)
end)
