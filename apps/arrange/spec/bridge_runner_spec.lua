-- lib/bridge/runner.lua: the ExtState loop, driven with a fake REAPER.

local runner = require("lib.bridge.runner")

local S = runner.SECTION

local function world()
  local w = { state = {}, now = 0, handled = {} }
  w.api = {
    GetExtState = function(section, key) return w.state[section .. "/" .. key] or "" end,
    SetExtState = function(section, key, value) w.state[section .. "/" .. key] = value end,
    DeleteExtState = function(section, key) w.state[section .. "/" .. key] = nil end,
    time_precise = function() return w.now end,
  }
  w.loop = runner.new({
    api = w.api,
    clock = function() return w.now end,
    handle = function(raw)
      w.handled[#w.handled + 1] = raw
      local id = raw:match("^([%w_%-]+)|")
      if raw == "silent" then return nil end
      return id, '{"echo":"' .. raw .. '"}'
    end,
  })
  function w.get(key) return w.state[S .. "/" .. key] end
  return w
end

describe("lib/bridge/runner.lua", function()
  it("clears a stale request and reply on start, and beats", function()
    local w = world()
    w.state[S .. "/req"] = "old|0|"
    w.state[S .. "/res"] = "old|{}"
    w.loop.start()
    assert.is_nil(w.get("req"))
    assert.is_nil(w.get("res"))
    assert.are.equal("1", w.get("heartbeat"))
    assert.are.same({}, w.handled)
  end)

  it("answers a request under its id", function()
    local w = world()
    w.loop.start()
    w.state[S .. "/req"] = "a1|0|"
    w.loop.tick()
    assert.are.equal('a1|{"echo":"a1|0|"}', w.get("res"))
  end)

  it("answers a request once, until the page writes another", function()
    local w = world()
    w.loop.start()
    w.state[S .. "/req"] = "a1|0|"
    w.loop.tick()
    w.loop.tick()
    w.loop.tick()
    assert.are.equal(1, #w.handled)
    w.state[S .. "/req"] = "a2|0|"
    w.loop.tick()
    assert.are.equal(2, #w.handled)
    assert.are.equal("a2", w.get("res"):match("^(a2)|"))
  end)

  it("writes no reply to a request it cannot address", function()
    local w = world()
    w.loop.start()
    w.state[S .. "/req"] = "silent"
    w.loop.tick()
    assert.is_nil(w.get("res"))
    w.loop.tick()
    assert.are.equal(1, #w.handled)
  end)

  it("beats four times a second, not on every tick", function()
    local w = world()
    w.loop.start()
    w.now = 0.1
    w.loop.tick()
    assert.are.equal("1", w.get("heartbeat"))
    w.now = 0.26
    w.loop.tick()
    assert.are.equal("2", w.get("heartbeat"))
    w.now = 0.3
    w.loop.tick()
    assert.are.equal("2", w.get("heartbeat"))
  end)

  it("beats as soon as a request is done, since it may have been a long one", function()
    local w = world()
    w.loop.start()
    w.now = 0.01
    w.state[S .. "/req"] = "a1|0|"
    w.loop.tick()
    assert.are.equal("2", w.get("heartbeat"))
  end)

  it("removes every key on stop", function()
    local w = world()
    w.loop.start()
    w.state[S .. "/req"] = "a1|0|"
    w.loop.tick()
    w.loop.stop()
    assert.is_nil(w.get("heartbeat"))
    assert.is_nil(w.get("req"))
    assert.is_nil(w.get("res"))
  end)
end)
