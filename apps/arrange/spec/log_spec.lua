local log = require("lib.log")
local fake_reaper = require("spec.support.fake_reaper")

-- `open` is always stubbed: a logger built with the real io.open would write a
-- file named after the fake Windows path into the repo root.
local function logger_for(project_path, api)
  return log.new({
    project_path = project_path or [[D:\P\Song.RPP]],
    api = api or fake_reaper.new(),
    clock = function() return "2026-07-30 09:41:00" end,
    open = function() return nil, "specs do not touch the filesystem" end,
  })
end

describe("log.path_for", function()
  it("puts the log beside the project", function()
    assert.are.equal([[D:\P\Song.arrange.log]], log.path_for([[D:\P\Song.RPP]]))
  end)

  it("accepts lowercase .rpp", function()
    assert.are.equal("/x/Song.arrange.log", log.path_for("/x/Song.rpp"))
  end)

  it("refuses an unsaved project", function()
    local path, err = log.path_for("")
    assert.is_nil(path)
    assert.is_truthy(err)
  end)
end)

describe("log body", function()
  it("collects lines in order", function()
    local logger = logger_for()
    logger:line("first")
    logger:line("second")

    local body = logger:text()
    assert.is_true(body:find("first", 1, true) < body:find("second", 1, true))
  end)

  it("stamps the run with a heading and the time", function()
    local logger = logger_for()
    logger:heading("Repack Regions")

    local body = logger:text()
    assert.is_truthy(body:find("Repack Regions", 1, true))
    assert.is_truthy(body:find("2026-07-30 09:41:00", 1, true))
  end)

  it("formats lines with arguments", function()
    local logger = logger_for()
    logger:line("moved %s to %.2f", "Intro", 12.5)
    assert.is_truthy(logger:text():find("moved Intro to 12.50", 1, true))
  end)

  -- A percent sign in a Region Name must not be read as a format directive.
  it("does not format a lone line as a pattern", function()
    local logger = logger_for()
    logger:line("100% wet")
    assert.is_truthy(logger:text():find("100% wet", 1, true))
  end)

  it("reports whether anything was logged", function()
    local logger = logger_for()
    assert.is_true(logger:is_empty())
    logger:line("something")
    assert.is_false(logger:is_empty())
  end)
end)

describe("log:write", function()
  it("sends the body to the REAPER console", function()
    local api = fake_reaper.new()
    local logger = logger_for(nil, api)
    logger:line("planned 3 moves")
    logger:write()

    local console = api.calls_to("ShowConsoleMsg")
    assert.are.equal(1, #console)
    assert.is_truthy(console[1].args[1]:find("planned 3 moves", 1, true))
  end)

  it("appends the body to the log file beside the project", function()
    local opened
    local handle = { written = {} }
    function handle:write(text) self.written[#self.written + 1] = text end
    function handle:close() self.closed = true end

    local logger = log.new({
      project_path = [[D:\P\Song.RPP]],
      api = fake_reaper.new(),
      clock = function() return "t" end,
      open = function(path, mode)
        opened = { path = path, mode = mode }
        return handle
      end,
    })
    logger:line("planned 3 moves")
    logger:write()

    assert.are.equal([[D:\P\Song.arrange.log]], opened.path)
    assert.are.equal("a", opened.mode)
    assert.is_truthy(table.concat(handle.written):find("planned 3 moves", 1, true))
    assert.is_true(handle.closed)
  end)

  it("writes nothing when nothing was logged", function()
    local api = fake_reaper.new()
    local opened = false
    local logger = log.new({
      project_path = [[D:\P\Song.RPP]],
      api = api,
      clock = function() return "t" end,
      open = function() opened = true end,
    })
    logger:write()

    assert.are.same({}, api.calls_to("ShowConsoleMsg"))
    assert.is_false(opened)
  end)

  -- A read-only folder must not take down a run whose edits already succeeded.
  it("still reaches the console when the log file cannot be opened", function()
    local api = fake_reaper.new()
    local logger = log.new({
      project_path = [[D:\P\Song.RPP]],
      api = api,
      clock = function() return "t" end,
      open = function() return nil, "permission denied" end,
    })
    logger:line("planned 3 moves")

    assert.has_no.errors(function() logger:write() end)
    assert.are.equal(1, #api.calls_to("ShowConsoleMsg"))
  end)
end)
