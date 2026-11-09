-- lib/core/edit.lua driven headlessly: one operation in, a result out, and
-- nothing written unless it is `ok`.

local edit = require("lib.core.edit")
local sidecar = require("lib.sidecar")
local core_env = require("spec.support.core_env")
local projects = require("spec.support.projects")

local PATH = projects.BARS_SIDECAR
local LOG = "/proj/Bars.arrange.log"
local CANONICAL = sidecar.serialize(assert(sidecar.parse(projects.BARS_ARRANGEMENTS)))

local function setup(files, options)
  return core_env.new(projects.merge({ snapshots = { projects.BARS }, files = files }, options))
end

local function canonical_world(options)
  return setup(projects.bars_files({ [PATH] = CANONICAL }), options)
end

-- A request based on the file as it stands.
-- `text` is the file's text as the page read it; `MISSING` means it read no file.
local MISSING = {}
local function request(fields, text)
  if text == MISSING then
    text = nil
  elseif text == nil then
    text = CANONICAL
  end
  return projects.merge({ revision = sidecar.revision(text),
    project_path = projects.BARS.project_path }, fields)
end

local function saved(world)
  return assert(sidecar.parse(world.files[PATH]))
end

local function order(arrangement)
  return { table.unpack(arrangement) }
end

describe("sidecar.revision", function()
  it("changes with any change of text, and is stable", function()
    assert.are.equal(sidecar.revision("a"), sidecar.revision("a"))
    assert.are_not.equal(sidecar.revision("a"), sidecar.revision("b"))
    assert.are_not.equal(sidecar.revision("a"), sidecar.revision("a\n"))
    assert.are_not.equal(sidecar.revision(""), sidecar.revision(nil))
    assert.are.equal("none", sidecar.revision(nil))
    assert.are.equal(16, #sidecar.revision("anything"))
  end)

  it("matches the published FNV-1a 64 test vector", function()
    assert.are.equal("af63dc4c8601ec8c", sidecar.revision("a"))
  end)
end)

describe("lib/core/edit.lua", function()
  describe("operations", function()
    it("moves a region and saves the file, returning the new revision and Arrangement", function()
      local given, world = canonical_world()
      local result = edit.run(given, request({ operation = "move", arrangement = "Identity",
        region = "Delta", slot = 1 }))

      assert.are.equal("ok", result.status)
      assert.are.same({ "Delta", "Alpha", "Bravo", "Charlie" }, order(saved(world).Identity))
      assert.are.equal(sidecar.revision(world.files[PATH]), result.revision)
      assert.are.equal("Identity", result.name)
      assert.are.same({ "Delta", "Alpha", "Bravo", "Charlie" },
        { result.entries[1].name, result.entries[2].name, result.entries[3].name,
          result.entries[4].name })
      assert.is_true(#result.names >= 6)
    end)

    it("takes numbers sent as text, as the bridge's flat fields arrive", function()
      local given, world = canonical_world()
      local result = edit.run(given, request({ operation = "move", arrangement = "Identity",
        region = "Delta", slot = "2" }))
      assert.are.equal("ok", result.status)
      assert.are.same({ "Alpha", "Delta", "Bravo", "Charlie" }, order(saved(world).Identity))
    end)

    it("sets a Headroom", function()
      local given, world = canonical_world()
      local result = edit.run(given, request({ operation = "set_headroom",
        arrangement = "Identity", region = "Bravo", headroom = "-2.5" }))
      assert.are.equal("ok", result.status)
      assert.are.equal(-2.5, saved(world).Identity.headroom.Bravo)
      assert.are.equal(-2.5, result.entries[2].headroom)
    end)

    it("adds and removes a region", function()
      local given, world = canonical_world()
      local removed = edit.run(given, request({ operation = "remove", arrangement = "Subset",
        region = "Bravo" }))
      assert.are.same({ "Alpha", "Delta" }, order(saved(world).Subset))

      local added = edit.run(given, request({ operation = "add", arrangement = "Subset",
        region = "Charlie", slot = 2 }, world.files[PATH]))
      assert.are.equal("ok", added.status)
      assert.are.equal("ok", removed.status)
      assert.are.same({ "Alpha", "Charlie", "Delta" }, order(saved(world).Subset))
    end)

    it("clears one Arrangement's Headroom", function()
      local given, world = canonical_world()
      local result = edit.run(given, request({ operation = "clear_headroom",
        arrangement = "Headroom" }))
      assert.are.equal("ok", result.status)
      assert.are.equal(0, saved(world).Headroom.headroom.Bravo)
      assert.are.equal(-20, saved(world).Shrink.headroom.Bravo)
    end)

    it("makes an empty Arrangement valid and saved", function()
      local given, world = canonical_world()
      local result = edit.run(given, request({ operation = "new", name = "  Blank " }))
      assert.are.equal("ok", result.status)
      assert.are.equal("Blank", result.name)
      assert.are.same({}, result.entries)
      assert.are.same({}, order(saved(world).Blank))
      assert.is_true(sidecar.is_canonical(world.files[PATH]))
    end)

    it("can empty an Arrangement by removing its last region", function()
      local given, world = setup(projects.bars_files({
        [PATH] = sidecar.serialize({ One = { "Alpha", headroom = { Alpha = 0 } } }) }))
      local text = world.files[PATH]
      local result = edit.run(given, request({ operation = "remove", arrangement = "One",
        region = "Alpha" }, text))
      assert.are.equal("ok", result.status)
      assert.are.same({}, order(saved(world).One))
    end)

    it("duplicates, renames and deletes", function()
      local given, world = canonical_world()
      local dup = edit.run(given, request({ operation = "duplicate", arrangement = "Headroom",
        name = "Copy" }))
      assert.are.equal("ok", dup.status)
      assert.are.equal("Headroom", dup.from)
      assert.are.equal(4, saved(world).Copy.headroom.Bravo)

      local renamed = edit.run(given, request({ operation = "rename", arrangement = "Copy",
        name = "Show" }, world.files[PATH]))
      assert.are.equal("ok", renamed.status)
      assert.is_nil(saved(world).Copy)
      assert.is_not_nil(saved(world).Show)

      local deleted = edit.run(given, request({ operation = "delete", arrangement = "Show" },
        world.files[PATH]))
      assert.are.equal("ok", deleted.status)
      assert.is_nil(deleted.entries)
      assert.is_nil(saved(world).Show)
    end)

    it("refuses name and region mistakes with the operation's code and writes nothing", function()
      local cases = {
        { { operation = "new", name = " " }, "name_empty" },
        { { operation = "new", name = "Identity" }, "name_taken" },
        { { operation = "duplicate", arrangement = "Identity", name = "Subset" }, "name_taken" },
        { { operation = "rename", arrangement = "Identity", name = "Subset" }, "name_taken" },
        { { operation = "rename", arrangement = "Nope", name = "X" }, "arrangement_not_found" },
        { { operation = "delete", arrangement = "Nope" }, "arrangement_not_found" },
        { { operation = "add", arrangement = "Identity", region = "Alpha" }, "region_repeated" },
        { { operation = "remove", arrangement = "Identity", region = "Zed" },
          "region_not_in_arrangement" },
        { { operation = "set_headroom", arrangement = "Identity", region = "Alpha",
            headroom = "abc" }, "headroom_invalid" },
        { { operation = "set_headroom", arrangement = "Identity", region = "Alpha",
            headroom = "1e999" }, "headroom_invalid" },
        { { operation = "move", arrangement = "Identity", region = "Alpha", slot = 9 },
          "slot_invalid" },
        { { operation = "frobnicate" }, "operation_unknown" },
      }
      for _, case in ipairs(cases) do
        local given, world = canonical_world()
        local result = edit.run(given, request(case[1]))
        assert.are.equal("refused", result.status, case[2])
        assert.are.equal(case[2], result.error.code)
        assert.is_true(world.untouched(), case[2])
      end
    end)
  end)

  describe("guards", function()
    it("refuses a stale revision", function()
      local given, world = canonical_world()
      local result = edit.run(given, projects.merge(request({ operation = "delete",
        arrangement = "Identity" }), { revision = sidecar.revision("something else") }))
      assert.are.equal("sidecar_changed", result.error.code)
      assert.is_true(world.untouched())
    end)

    it("refuses another project", function()
      local given, world = canonical_world()
      local result = edit.run(given, projects.merge(request({ operation = "delete",
        arrangement = "Identity" }), { project_path = "/proj/Other.rpp" }))
      assert.are.equal("other_project", result.error.code)
      assert.is_true(world.untouched())
    end)

    it("refuses an unsaved project", function()
      local given, world = core_env.new({ snapshots = { projects.UNSAVED_BARS } })
      local result = edit.run(given, { operation = "new", name = "X", revision = "none",
        project_path = "" })
      assert.are.equal("project_unsaved", result.error.code)
      assert.is_true(world.untouched())
    end)

    it("refuses an invalid sidecar and leaves it alone", function()
      local given, world = setup(projects.bars_files({ [PATH] = "return {" }))
      local result = edit.run(given, request({ operation = "new", name = "X" }, "return {"))
      assert.are.equal("sidecar_invalid", result.error.code)
      assert.are.equal("return {", world.files[PATH])
      assert.is_true(world.untouched())
    end)

    it("refuses a stale base when the file appeared since the page saw it missing", function()
      local given, world = canonical_world()
      local result = edit.run(given, request({ operation = "new", name = "X" }, MISSING))
      assert.are.equal("sidecar_changed", result.error.code)
      assert.is_true(world.untouched())
    end)

    it("reports a failed write", function()
      local given = canonical_world({ unwritable = { [PATH] = true } })
      local result = edit.run(given, request({ operation = "new", name = "X" }))
      assert.are.equal("save_failed", result.error.code)
    end)

    it("never writes a file that would not load back", function()
      local given, world = canonical_world()
      -- A long-bracket-hostile name still round-trips; a table with a bad
      -- Headroom can't be built through the operations, so check the guard directly.
      local result = edit.run(given, request({ operation = "new", name = "Bad\0Name" }))
      if result.status == "ok" then
        assert.is_not_nil(sidecar.parse(world.files[PATH]))
      else
        assert.are.equal("would_be_invalid", result.error.code)
        assert.is_true(world.untouched())
      end
    end)
  end)

  describe("a missing sidecar", function()
    it("is created by New", function()
      local given, world = setup(projects.bars_files({ [PATH] = false }))
      world.files[PATH] = nil
      local result = edit.run(given, request({ operation = "new", name = "First" }, MISSING))
      assert.are.equal("ok", result.status)
      assert.are.same({}, order(saved(world).First))
      assert.are.equal(sidecar.revision(world.files[PATH]), result.revision)
    end)

    it("makes any other operation say the Arrangement is not found", function()
      local given, world = setup(projects.bars_files({ [PATH] = false }))
      world.files[PATH] = nil
      local result = edit.run(given, request({ operation = "delete", arrangement = "X" }, MISSING))
      assert.are.equal("arrangement_not_found", result.error.code)
      assert.is_nil(world.files[PATH])
    end)
  end)

  describe("a non-canonical file", function()
    local function hand_written()
      return setup(projects.bars_files())
    end

    it("asks before rewriting it, and writes nothing", function()
      local given, world = hand_written()
      local result = edit.run(given, request({ operation = "new", name = "X" },
        projects.BARS_ARRANGEMENTS))
      assert.are.equal("confirm", result.status)
      assert.are.equal("rewrite", result.confirm.code)
      assert.are.equal(projects.BARS_ARRANGEMENTS, world.files[PATH])
      assert.is_true(world.untouched())
    end)

    it("rewrites it once the question is answered, then does not ask again", function()
      local given, world = hand_written()
      local first = edit.run(given, request({ operation = "new", name = "X", rewrite = true },
        projects.BARS_ARRANGEMENTS))
      assert.are.equal("ok", first.status)
      assert.is_true(sidecar.is_canonical(world.files[PATH]))

      local second = edit.run(given, request({ operation = "new", name = "Y" }, world.files[PATH]))
      assert.are.equal("ok", second.status)
    end)

    it("refuses a bad edit rather than asking about it", function()
      local given = hand_written()
      local result = edit.run(given, request({ operation = "new", name = "Identity" },
        projects.BARS_ARRANGEMENTS))
      assert.are.equal("name_taken", result.error.code)
    end)

    it("checks the revision before asking", function()
      local given = hand_written()
      local result = edit.run(given, request({ operation = "new", name = "X" }, "stale"))
      assert.are.equal("sidecar_changed", result.error.code)
    end)
  end)

  describe("the run log", function()
    local function log(world)
      return world.files[LOG]
    end

    it("records New, Duplicate and Rename", function()
      local given, world = canonical_world()
      edit.run(given, request({ operation = "new", name = "Blank" }))
      edit.run(given, request({ operation = "duplicate", arrangement = "Headroom", name = "Copy" },
        world.files[PATH]))
      edit.run(given, request({ operation = "rename", arrangement = "Copy", name = "Show" },
        world.files[PATH]))

      assert.is_truthy(log(world):find('Edit Arrangements -- new "Blank"', 1, true))
      assert.is_truthy(log(world):find('Duplicated "Headroom" as "Copy" (3 regions).', 1, true))
      assert.is_truthy(log(world):find('Renamed "Copy" to "Show".', 1, true))
    end)

    it("records Delete with the full entry list and Headroom", function()
      local given, world = canonical_world()
      edit.run(given, request({ operation = "delete", arrangement = "Headroom" }))
      local text = log(world)
      assert.is_truthy(text:find('Deleted "Headroom" (3 regions).', 1, true))
      assert.is_truthy(text:find("1. Alpha\n", 1, true))
      assert.is_truthy(text:find("2. Bravo (headroom +4 s)\n", 1, true))
      assert.is_truthy(text:find("3. Delta\n", 1, true))
    end)

    it("logs nothing for the other operations, or for a refusal", function()
      local given, world = canonical_world()
      edit.run(given, request({ operation = "move", arrangement = "Identity", region = "Alpha",
        slot = 2 }))
      edit.run(given, request({ operation = "set_headroom", arrangement = "Identity",
        region = "Alpha", headroom = 1 }, world.files[PATH]))
      edit.run(given, request({ operation = "clear_headroom", arrangement = "Identity" },
        world.files[PATH]))
      edit.run(given, request({ operation = "new", name = "Identity" }, world.files[PATH]))
      assert.is_nil(log(world))
    end)
  end)
end)
