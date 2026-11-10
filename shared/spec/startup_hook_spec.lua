-- shared/startup/hook.lua: the __startup.lua lines that start the bridges with REAPER, driven with a fake REAPER.

local hook = require("shared.startup.hook")

local function world(opts)
  opts = opts or {}
  local w = { files = opts.files or {}, ran = {}, added = {}, shown = nil }
  w.api = {
    GetResourcePath = function() return "/R" end,
    file_exists = function(p) return w.files[p] == true end,
    AddRemoveReaScript = function(add, section, p, commit)
      w.added[#w.added + 1] = { add, section, p, commit }
      return 42
    end,
    Main_OnCommand = function(id, flag) w.ran[#w.ran + 1] = { id, flag } end,
  }
  w.fs = {
    read = function(p) return w.files[p] ~= true and w.files[p] or nil end,
    write = function(p, text) w.files[p] = text end,
    remove = function(p) w.files[p] = nil end,
  }
  return w
end

local STARTUP = "/R/Scripts/__startup.lua"

-- Run the managed line for one bridge the way REAPER would at start-up.
local function run_line(w, line)
  local env = { reaper = w.api, ipairs = ipairs }
  assert(load(line, "startup", "t", env))()
end

describe("shared/startup/hook.lua", function()
  describe("apply (text in, text out)", function()
    it("adds one marked line per bridge to an empty file", function()
      local out = hook.apply("", true)
      local n = 0
      for _ in out:gmatch("\n") do n = n + 1 end
      assert.are.equal(#hook.bridges, n)
      assert.is_truthy(out:find("LCRR-ARRANGE-BRIDGE", 1, true))
      assert.is_truthy(out:find("LCRR-IEM-BRIDGE", 1, true))
      assert.is_truthy(out:sub(-1) == "\n")
    end)

    it("keeps the user's own lines, before and after", function()
      local out = hook.apply("-- mine\nprint('hi')\n", true)
      assert.are.equal("-- mine\nprint('hi')\n", out:sub(1, 20))
      local gone = hook.apply(out, false)
      assert.are.equal("-- mine\nprint('hi')\n", gone)
    end)

    it("is idempotent: applying twice gives the same text", function()
      local once = hook.apply("x = 1\n", true)
      assert.are.equal(once, hook.apply(once, true))
    end)

    it("adds a newline when the file lacks a trailing one", function()
      local out = hook.apply("x = 1", true)
      assert.are.equal("x = 1\n", out:sub(1, 6))
    end)

    it("replaces lines written by install.ps1 instead of duplicating them", function()
      local legacy = 'do local p = "x" end -- LCRR-ARRANGE-BRIDGE (managed by install.ps1)\n'
      local out = hook.apply(legacy, true)
      local count = select(2, out:gsub("LCRR%-ARRANGE%-BRIDGE", ""))
      assert.are.equal(1, count)
      assert.is_nil(out:find("install.ps1", 1, true))
    end)

    it("removes only our lines, and leaves an empty text when nothing else remains", function()
      assert.are.equal("", hook.apply(hook.apply("", true), false))
    end)

    it("copes with CRLF files", function()
      local out = hook.apply("a = 1\r\nb = 2\r\n", true)
      assert.are.equal("a = 1\r\nb = 2\r\n", hook.apply(out, false))
    end)
  end)

  describe("the managed line", function()
    local arrange = hook.bridges[1]

    it("starts the bridge from the install.ps1 location", function()
      local w = world({ files = { ["/R/Scripts/LCRR/arrange/LCRR_Arrange_Bridge.lua"] = true } })
      run_line(w, hook.line(arrange))
      assert.are.same({ { true, 0, "/R/Scripts/LCRR/arrange/LCRR_Arrange_Bridge.lua", true } }, w.added)
      assert.are.same({ { 42, 0 } }, w.ran)
    end)

    it("starts the bridge from the ReaPack location", function()
      local w = world({ files = { ["/R/Scripts/LCRR/Remote/arrange/LCRR_Arrange_Bridge.lua"] = true } })
      run_line(w, hook.line(arrange))
      assert.are.equal("/R/Scripts/LCRR/Remote/arrange/LCRR_Arrange_Bridge.lua", w.added[1][3])
      assert.are.equal(1, #w.ran)
    end)

    it("does nothing, without an error, when the scripts are gone (uninstalled)", function()
      local w = world()
      run_line(w, hook.line(arrange))
      assert.are.same({}, w.added)
      assert.are.same({}, w.ran)
    end)

    it("is a single line", function()
      for _, b in ipairs(hook.bridges) do assert.is_nil(hook.line(b):find("\n")) end
    end)
  end)

  describe("run (install and remove actions)", function()
    it("install creates __startup.lua with the lines", function()
      local w = world()
      local msg = hook.run({ api = w.api, fs = w.fs }, true)
      assert.is_truthy(w.files[STARTUP]:find("LCRR-ARRANGE-BRIDGE", 1, true))
      assert.is_truthy(msg:lower():find("restart", 1, true))
    end)

    it("install twice leaves one line per bridge", function()
      local w = world()
      hook.run({ api = w.api, fs = w.fs }, true)
      local first = w.files[STARTUP]
      hook.run({ api = w.api, fs = w.fs }, true)
      assert.are.equal(first, w.files[STARTUP])
    end)

    it("remove deletes __startup.lua when only our lines were in it", function()
      local w = world()
      hook.run({ api = w.api, fs = w.fs }, true)
      hook.run({ api = w.api, fs = w.fs }, false)
      assert.is_nil(w.files[STARTUP])
    end)

    it("remove keeps the user's lines", function()
      local w = world({ files = { [STARTUP] = "print('mine')\n" } })
      hook.run({ api = w.api, fs = w.fs }, true)
      hook.run({ api = w.api, fs = w.fs }, false)
      assert.are.equal("print('mine')\n", w.files[STARTUP])
    end)

    it("remove with no __startup.lua is a no-op", function()
      local w = world()
      local msg = hook.run({ api = w.api, fs = w.fs }, false)
      assert.is_nil(w.files[STARTUP])
      assert.is_string(msg)
    end)
  end)
end)
