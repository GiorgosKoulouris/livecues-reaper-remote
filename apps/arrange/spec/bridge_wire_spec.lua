-- The bridge's wire formats on their own: JSON out, requests in, check
-- tokens. The service built from them is spec/bridge_service_spec.lua.

local json = require("lib.bridge.json")
local request = require("lib.bridge.request")
local tokens = require("lib.bridge.tokens")

describe("lib/bridge/json.lua", function()
  it("encodes scalars", function()
    assert.are.equal("null", json.encode(nil))
    assert.are.equal("true", json.encode(true))
    assert.are.equal("42", json.encode(42))
    assert.are.equal("-3", json.encode(-3.0))
    assert.are.equal("12.345", json.encode(12.345))
    assert.are.equal('"a"', json.encode("a"))
  end)

  it("turns NaN and infinity into null, since JSON has neither", function()
    assert.are.equal("null", json.encode(0 / 0))
    assert.are.equal("null", json.encode(math.huge))
    assert.are.equal("null", json.encode(-math.huge))
  end)

  it("escapes quotes, backslashes and control characters", function()
    assert.are.equal([["a\"b\\c\nd\te\u0001"]], json.encode('a"b\\c\nd\te\1'))
  end)

  it("leaves UTF-8 as it is", function()
    assert.are.equal('"Verse \u{e9} \u{1F3B5}"', json.encode("Verse \u{e9} \u{1F3B5}"))
  end)

  it("encodes a sequence as an array, and an empty table as an empty array", function()
    assert.are.equal('[1,"two",[3]]', json.encode({ 1, "two", { 3 } }))
    assert.are.equal("[]", json.encode({}))
  end)

  it("encodes other tables as objects with sorted keys", function()
    assert.are.equal('{"a":1,"b":{"c":true}}', json.encode({ b = { c = true }, a = 1 }))
  end)

  it("gives a number key its string form", function()
    assert.are.equal('{"-1":2,"0":5}', json.encode({ [0] = 5, [-1] = 2 }))
  end)

  it("treats a table with a gap as an object", function()
    assert.are.equal('{"1":"a","3":"c"}', json.encode({ "a", nil, "c" }))
  end)

  it("refuses what has no JSON form, rather than dropping it", function()
    assert.has_error(function() json.encode({ f = print }) end, "json: cannot encode a function")
    assert.has_error(function() json.encode({ [{}] = 1 }) end, "json: cannot encode a table key of type table")
  end)

  it("refuses a table that contains itself", function()
    local loop = {}
    loop.self = loop
    assert.has_error(function() json.encode(loop) end, "json: nested deeper than 64")
  end)
end)

describe("lib/bridge/request.lua", function()
  local function body(text)
    return ("r1|%d|%s"):format(#text, text)
  end

  it("reads an id and flat fields", function()
    local parsed = request.parse(body("cmd=check&name=Radio"))
    assert.are.equal("r1", parsed.id)
    assert.are.same({ cmd = "check", name = "Radio" }, parsed.fields)
  end)

  it("reads a request with no fields", function()
    local parsed = request.parse("r1|0|")
    assert.are.same({}, parsed.fields)
  end)

  it("percent-decodes values, so any character can be in a name", function()
    local parsed = request.parse(body("name=A%26B%3DC%7CD%25%20%C3%A9"))
    assert.are.equal("A&B=C|D% \u{e9}", parsed.fields.name)
  end)

  it("keeps + as a plus", function()
    assert.are.equal("a+b", request.parse(body("name=a+b")).fields.name)
  end)

  it("keeps an empty value", function()
    assert.are.equal("", request.parse(body("name=")).fields.name)
  end)

  it("refuses a body shorter than it declared, naming the id", function()
    local cut = "r1|20|cmd=check&na"
    local parsed, refusal = request.parse(cut)
    assert.is_nil(parsed)
    assert.are.same({ id = "r1", code = "request_truncated", declared = 20, received = 12 }, refusal)
  end)

  it("refuses a request cut off before its body", function()
    for _, cut in ipairs({ "r1|", "r1|2", "r1|23" }) do
      local parsed, refusal = request.parse(cut)
      assert.is_nil(parsed)
      assert.are.equal("request_truncated", refusal.code)
      assert.are.equal("r1", refusal.id)
    end
  end)

  it("refuses a body longer than it declared", function()
    local _, refusal = request.parse("r1|3|cmd=check")
    assert.are.equal("bad_request", refusal.code)
    assert.are.equal("r1", refusal.id)
  end)

  it("refuses a field with no key, and a bad escape", function()
    assert.are.equal("bad_request", select(2, request.parse(body("check"))).code)
    assert.are.equal("bad_request", select(2, request.parse(body("name=%zz"))).code)
    assert.are.equal("bad_request", select(2, request.parse(body("name=%4"))).code)
  end)

  it("has nothing to answer when there is no readable id", function()
    for _, raw in ipairs({ "", "no pipe", "|1|x", ("x"):rep(request.MAX_ID + 1) .. "|0|" }) do
      local parsed, refusal = request.parse(raw)
      assert.is_nil(parsed)
      assert.is_nil(refusal.id)
    end
  end)
end)

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
