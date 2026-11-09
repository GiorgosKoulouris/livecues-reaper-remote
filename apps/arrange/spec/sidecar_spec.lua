local sidecar = require("lib.sidecar")

describe("sidecar.path_for", function()
  it("swaps a .RPP extension for .arrangements.lua", function()
    assert.are.equal(
      [[D:\Projects\LiveSession\Rehearsal_Current.arrangements.lua]],
      sidecar.path_for([[D:\Projects\LiveSession\Rehearsal_Current.RPP]])
    )
  end)

  it("accepts lowercase .rpp, since REAPER writes either", function()
    assert.are.equal(
      "/home/g/MySong.arrangements.lua",
      sidecar.path_for("/home/g/MySong.rpp")
    )
  end)

  -- A project named "Take.2.rpp" must not become "Take.arrangements.lua".
  it("only replaces the final extension", function()
    assert.are.equal(
      "/x/Take.2.arrangements.lua",
      sidecar.path_for("/x/Take.2.rpp")
    )
  end)

  -- An unsaved project has no path to sit beside (ADR-0003).
  it("refuses an empty path", function()
    local path, err = sidecar.path_for("")
    assert.is_nil(path)
    assert.is_truthy(err)
  end)

  it("refuses a path that is not a REAPER project", function()
    local path, err = sidecar.path_for("/x/notes.txt")
    assert.is_nil(path)
    assert.is_truthy(err)
  end)
end)

-- `parse` normalises both entry shapes to a list of Region Names carrying a
-- `headroom` field, so a deep comparison against a bare list would compare the
-- field too. These pull the two halves apart, which is also how every consumer
-- reads the result.
local function order_of(arrangement)
  local names = {}
  for _, name in ipairs(arrangement) do
    names[#names + 1] = name
  end
  return names
end

local function headroom_of(arrangement)
  return arrangement.headroom
end

describe("sidecar.parse", function()
  it("reads a table of named Region Name lists", function()
    local arrangements = assert(sidecar.parse([[
      return {
        ["Set 1"] = { "Intro", "Sundown", "Payback" },
        ["Encore"] = { "Maze" },
      }
    ]]))

    assert.are.same({ "Intro", "Sundown", "Payback" }, order_of(arrangements["Set 1"]))
    assert.are.same({ "Maze" }, order_of(arrangements["Encore"]))
  end)

  -- Every sidecar written before Headroom existed keeps its exact meaning.
  it("reads a bare Region Name as a Headroom of zero", function()
    local arrangements = assert(sidecar.parse([[return { ["Set 1"] = { "Intro", "Maze" } }]]))
    assert.are.same({ Intro = 0, Maze = 0 }, headroom_of(arrangements["Set 1"]))
  end)

  it("reads a Headroom off the table form", function()
    local arrangements = assert(sidecar.parse([[
      return { ["Set 1"] = { { "Intro", headroom = -2 }, { "Maze", headroom = 4.5 } } }
    ]]))

    assert.are.same({ "Intro", "Maze" }, order_of(arrangements["Set 1"]))
    assert.are.same({ Intro = -2, Maze = 4.5 }, headroom_of(arrangements["Set 1"]))
  end)

  it("mixes both entry shapes within one Arrangement", function()
    local arrangements = assert(sidecar.parse([[
      return { ["Set 1"] = { "Intro", { "Maze", headroom = 8 }, "Payback" } }
    ]]))

    assert.are.same({ "Intro", "Maze", "Payback" }, order_of(arrangements["Set 1"]))
    assert.are.same({ Intro = 0, Maze = 8, Payback = 0 }, headroom_of(arrangements["Set 1"]))
  end)

  it("defaults a table entry with no headroom to zero", function()
    local arrangements = assert(sidecar.parse([[return { ["Set 1"] = { { "Intro" } } }]]))
    assert.are.same({ Intro = 0 }, headroom_of(arrangements["Set 1"]))
  end)

  it("rejects a non-numeric headroom", function()
    local arrangements, err = sidecar.parse(
      [[return { ["Set 1"] = { { "Intro", headroom = "4" } } }]])
    assert.is_nil(arrangements)
    assert.is_truthy(err:find("Set 1", 1, true))
    assert.is_truthy(err:find("Intro", 1, true))
  end)

  it("rejects an infinite headroom", function()
    local arrangements, err = sidecar.parse(
      [[return { ["Set 1"] = { { "Intro", headroom = 1/0 } } }]])
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)

  it("rejects a NaN headroom", function()
    local arrangements, err = sidecar.parse(
      [[return { ["Set 1"] = { { "Intro", headroom = 0/0 } } }]])
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)

  -- The alternative to refusing is a run that silently does nothing to the one
  -- region the user was editing.
  it("rejects a misspelled field rather than ignoring it", function()
    local arrangements, err = sidecar.parse(
      [[return { ["Set 1"] = { { "Intro", headrom = 4 } } }]])
    assert.is_nil(arrangements)
    assert.is_truthy(err:find("headrom", 1, true))
  end)

  it("rejects a table entry that does not name a region first", function()
    local arrangements, err = sidecar.parse([[return { ["Set 1"] = { { headroom = 4 } } }]])
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)

  it("rejects an empty Region Name in the table form", function()
    local arrangements, err = sidecar.parse([[return { ["Set 1"] = { { "", headroom = 0 } } }]])
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)

  it("rejects a Region Name repeated across the two entry shapes", function()
    local arrangements, err = sidecar.parse(
      [[return { ["Set 1"] = { "Intro", { "Intro", headroom = 2 } } }]])
    assert.is_nil(arrangements)
    assert.is_truthy(err:find("twice", 1, true))
  end)

  it("accepts an empty sidecar", function()
    assert.are.same({}, assert(sidecar.parse("return {}")))
  end)

  it("reports a syntax error rather than raising", function()
    local arrangements, err = sidecar.parse("return {")
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)

  it("rejects a chunk that returns a non-table", function()
    local arrangements, err = sidecar.parse("return 42")
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)

  it("rejects a chunk that returns nothing", function()
    local arrangements, err = sidecar.parse("local x = 1")
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)

  -- The sidecar is hand-edited, so a typo must not be able to reach the host.
  it("runs in an empty environment, so globals are unreachable", function()
    local arrangements, err = sidecar.parse("return { X = os.time() }")
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)

  it("refuses a precompiled binary chunk", function()
    local arrangements, err = sidecar.parse(string.dump(load("return {}")))
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)

  it("rejects an arrangement that is not a list", function()
    local arrangements, err = sidecar.parse([[return { ["Set 1"] = "Intro" }]])
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)

  it("rejects a non-string Region Name", function()
    local arrangements, err = sidecar.parse([[return { ["Set 1"] = { "Intro", 7 } }]])
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)

  -- Empty names are unaddressable, exactly as they are on a region.
  it("rejects an empty Region Name", function()
    local arrangements, err = sidecar.parse([[return { ["Set 1"] = { "" } }]])
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)

  it("rejects a non-string arrangement name", function()
    local arrangements, err = sidecar.parse([[return { [1] = { "Intro" } }]])
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)

  -- A hole would silently truncate the arrangement.
  it("rejects a sparse arrangement", function()
    local arrangements, err = sidecar.parse([[return { ["Set 1"] = { [1] = "A", [3] = "B" } }]])
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)

  -- Repacking the same region twice cannot be expressed on one timeline.
  it("rejects a Region Name repeated within one arrangement", function()
    local arrangements, err = sidecar.parse([[return { ["Set 1"] = { "Intro", "Intro" } }]])
    assert.is_nil(arrangements)
    assert.is_truthy(err)
  end)
end)

describe("sidecar.load", function()
  local function opener(contents)
    return function()
      local handle = {}
      function handle.read() return contents end
      function handle:close() self.closed = true end
      return handle
    end
  end

  it("parses the file beside the project", function()
    local arrangements = assert(sidecar.load(
      [[D:\P\Song.RPP]], opener([[return { ["Set 1"] = { "Intro" } }]])))
    assert.are.same({ "Intro" }, order_of(arrangements["Set 1"]))
  end)

  it("reads from the sidecar path, not the project path", function()
    local seen
    sidecar.load([[D:\P\Song.RPP]], function(path)
      seen = path
      return nil
    end)
    assert.are.equal([[D:\P\Song.arrangements.lua]], seen)
  end)

  -- A project with no Arrangements yet is normal, not broken.
  it("reports a missing sidecar as missing, not as an error", function()
    local arrangements, err, reason = sidecar.load([[D:\P\Song.RPP]], function() return nil end)
    assert.is_nil(arrangements)
    assert.is_nil(err)
    assert.are.equal("missing", reason)
  end)

  it("reports a sidecar that will not parse as invalid", function()
    local arrangements, err, reason = sidecar.load([[D:\P\Song.RPP]], opener("return {"))
    assert.is_nil(arrangements)
    assert.is_truthy(err)
    assert.are.equal("invalid", reason)
  end)

  it("reports an unsaved project distinctly", function()
    local arrangements, err, reason = sidecar.load("", opener("return {}"))
    assert.is_nil(arrangements)
    assert.is_truthy(err)
    assert.are.equal("unsaved", reason)
  end)
end)

describe("sidecar.save", function()
  local function recorder(written)
    return function(path, mode)
      written.path, written.mode = path, mode
      local handle = {}
      function handle.write(_, text) written.text = (written.text or "") .. text end
      function handle.close() written.closed = true end
      return handle
    end
  end

  it("writes serialized Arrangements to the sidecar path", function()
    local written = {}
    local path = assert(sidecar.save(
      [[D:\P\Song.RPP]], { ["Set 1"] = { "Intro" } }, recorder(written)))

    assert.are.equal([[D:\P\Song.arrangements.lua]], path)
    assert.are.equal("w", written.mode)
    assert.is_true(written.closed)
    assert.are.same({ "Intro" }, order_of(assert(sidecar.parse(written.text))["Set 1"]))
  end)

  it("reports a project that has never been saved", function()
    local path, err = sidecar.save("", {}, recorder({}))
    assert.is_nil(path)
    assert.is_truthy(err)
  end)

  it("reports a sidecar it cannot open for writing", function()
    local path, err = sidecar.save([[D:\P\Song.RPP]], {}, function()
      return nil, "permission denied"
    end)
    assert.is_nil(path)
    assert.is_truthy(err:find("permission denied", 1, true))
  end)
end)

describe("sidecar.serialize", function()
  it("round-trips through parse", function()
    local original = {
      ["Set 1"] = { "Intro", "Sundown" },
      ["Encore"] = { "Maze" },
    }
    local read_back = assert(sidecar.parse(sidecar.serialize(original)))
    assert.are.same({ "Intro", "Sundown" }, order_of(read_back["Set 1"]))
    assert.are.same({ "Maze" }, order_of(read_back["Encore"]))
  end)

  -- The sidecar is the only authoring surface, so it is the only place the
  -- feature can be discovered (ADR-0003).
  it("writes the table form with an explicit headroom on every entry", function()
    local source = sidecar.serialize({ ["Set 1"] = { "Intro" } })
    assert.is_truthy(source:find('{ "Intro", headroom = 0 }', 1, true))
  end)

  it("round-trips a Headroom", function()
    local original = { ["Set 1"] = { "Intro", "Maze", headroom = { Intro = -2, Maze = 4.5 } } }
    local read_back = assert(sidecar.parse(sidecar.serialize(original)))
    assert.are.same({ "Intro", "Maze" }, order_of(read_back["Set 1"]))
    assert.are.same({ Intro = -2, Maze = 4.5 }, headroom_of(read_back["Set 1"]))
  end)

  it("orders arrangements by name, so the file diffs cleanly", function()
    local source = sidecar.serialize({ B = { "X" }, A = { "Y" }, C = { "Z" } })
    assert.is_true(source:find("%[\"A\"%]") < source:find("%[\"B\"%]"))
    assert.is_true(source:find("%[\"B\"%]") < source:find("%[\"C\"%]"))
  end)

  it("preserves Region Name order within an arrangement", function()
    local order = { "Zebra", "Apple", "Mango" }
    assert.are.same(order, order_of(assert(sidecar.parse(sidecar.serialize({ S = order })))["S"]))
  end)

  -- Region Names are free text; REAPER lets them contain quotes and backslashes.
  it("escapes names that would otherwise break the chunk", function()
    local names = { [[back\slash]], "tab\there", "new\nline" }
    local original = { ['He said "hi"'] = names }
    local read_back = assert(sidecar.parse(sidecar.serialize(original)))
    assert.are.same(names, order_of(read_back['He said "hi"']))
  end)

  it("emits an empty sidecar as a parseable chunk", function()
    assert.are.same({}, assert(sidecar.parse(sidecar.serialize({}))))
  end)
end)
