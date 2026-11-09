-- The replies the web page is written against, recorded from the real service.
--
-- test/fixtures/bridge-replies.txt holds one line per scenario: `<name>\t<reply json>`.
-- This spec compares what the service says now with that file, so a change to a
-- reply's shape cannot go unnoticed; apps/arrange/test/words.test.js then pushes
-- the same file through the page's wording, so the page cannot drift from it.
-- After a deliberate change: LCRR_RECORD_BRIDGE=1 busted spec/bridge_contract_spec.lua,
-- and read the diff.

local service = require("lib.bridge.service")
local sidecar = require("lib.sidecar")
local core_env = require("spec.support.core_env")
local projects = require("spec.support.projects")

local merge = projects.merge
local FIXTURE = "test/fixtures/bridge-replies.txt"

local function encode_field(value)
  return (value:gsub("[^%w_.~-]", function(char) return ("%%%02X"):format(char:byte()) end))
end

local function raw(id, fields)
  local keys = {}
  for key in pairs(fields) do keys[#keys + 1] = key end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do parts[#parts + 1] = key .. "=" .. encode_field(fields[key]) end
  local body = table.concat(parts, "&")
  return ("%s|%d|%s"):format(id, #body, body)
end

local function bridge(options)
  options = options or {}
  local state = { changes = 10, path = options.path or projects.BARS_PATH }
  local given, world = core_env.new(merge({
    snapshots = options.snapshots or { projects.BARS, projects.BARS, projects.BARS_ANCHORED },
    files = options.files or projects.bars_files(),
    tempo = projects.bars_tempo(),
    api = {
      EnumProjects = function() return 0, state.path end,
      GetProjectStateChangeCount = function() return state.changes end,
      TimeMap2_timeToBeats = function() return 0, 1 end,
      CountTracks = function() return 2 end,
      GetTrack = function(_, index) return index end,
      GetMediaTrackInfo_Value = function(track) return track end,
      GetSetMediaTrackInfo_String = function(track) return true, track == 0 and "Gtr" or "Keys" end,
    },
  }, {}))
  given.random = function() return 1 end
  local handler = service.new(given)
  local count = 0
  return function(command, fields)
    count = count + 1
    local _, reply = handler.handle(raw("q" .. count, merge({ cmd = command }, fields)))
    return reply
  end, state, world
end

local function token_of(reply)
  return reply:match('"token":"(%w+)"')
end

-- An edit based on the sidecar as it stands (rewrite answered, since the fixture is hand-written).
local function edit_fields(world, fields)
  return merge({
    revision = sidecar.revision(world.files[projects.BARS_SIDECAR]),
    project = projects.BARS_PATH,
    rewrite = "1",
  }, fields)
end

local scenarios = {
  { "info", function(ask) return ask("info", {}) end },
  { "info_no_sidecar", function()
    local ask = bridge({ files = { [projects.BARS_PATH] = projects.RPP_TIME } })
    return ask("info", {})
  end },
  { "arrangements", function(ask) return ask("arrangements", {}) end },
  { "arrangements_missing", function()
    local ask = bridge({ files = { [projects.BARS_PATH] = projects.RPP_TIME } })
    return ask("arrangements", {})
  end },
  { "arrangements_invalid", function()
    local ask = bridge({ files = projects.bars_files({ [projects.BARS_SIDECAR] = "return {" }) })
    return ask("arrangements", {})
  end },
  { "arrangements_unsaved", function()
    return bridge({ snapshots = { projects.UNSAVED_BARS } })("arrangements", {})
  end },
  { "edit_move", function(ask, _, world)
    local fields = { operation = "move", arrangement = "Identity", region = "Delta", slot = "1" }
    return ask("edit", edit_fields(world, fields))
  end },
  { "edit_new", function(ask, _, world)
    return ask("edit", edit_fields(world, { operation = "new", name = "Fresh" }))
  end },
  { "edit_duplicate", function(ask, _, world)
    return ask("edit", edit_fields(world, { operation = "duplicate", arrangement = "Headroom", name = "Copy" }))
  end },
  { "edit_delete", function(ask, _, world)
    return ask("edit", edit_fields(world, { operation = "delete", arrangement = "Headroom" }))
  end },
  { "edit_confirm", function(ask, _, world)
    local fields = edit_fields(world, { operation = "clear_headroom", arrangement = "Headroom" })
    fields.rewrite = nil
    return ask("edit", fields)
  end },
  { "edit_name_taken", function(ask, _, world)
    return ask("edit", edit_fields(world, { operation = "new", name = "Identity" }))
  end },
  { "edit_sidecar_changed", function(ask, _, world)
    local fields = edit_fields(world, { operation = "new", name = "Fresh" })
    fields.revision = "0000000000000000"
    return ask("edit", fields)
  end },
  { "edit_other_project", function(ask, _, world)
    local fields = edit_fields(world, { operation = "new", name = "Fresh" })
    fields.project = "/elsewhere/Other.rpp"
    return ask("edit", fields)
  end },
  { "edit_invalid", function(ask, _, world)
    local fields = { operation = "set_headroom", arrangement = "Identity", region = "Alpha", headroom = "nan" }
    return ask("edit", edit_fields(world, fields))
  end },
  { "duplicates_problems", function()
    return bridge({ snapshots = { projects.DUPES }, files = projects.packed_files() })("duplicates", {})
  end },
  { "duplicates_clean", function()
    local ask = bridge({ snapshots = { projects.PACKED }, files = projects.packed_files() })
    return ask("duplicates", {})
  end },
  { "timebase", function(ask) return ask("timebase", {}) end },
  { "barlines", function(ask) return ask("barlines", {}) end },
  { "capture_ok", function(ask) return ask("capture", { name = "Fresh", rewrite = "1" }) end },
  -- The fixture sidecar is hand-written, so the first Capture asks before rewriting it.
  { "capture_rewrite", function(ask) return ask("capture", { name = "Fresh" }) end },
  { "capture_confirm", function(ask)
    ask("capture", { name = "Fresh", rewrite = "1" })
    return ask("capture", { name = "Fresh" })
  end },
  { "capture_refused", function()
    return bridge({ snapshots = { projects.UNSAVED_BARS } })("capture", { name = "Fresh" })
  end },
  { "verify_fail", function(ask) return ask("verify", { name = "Identity" }) end },
  { "verify_pass", function()
    return (bridge({ snapshots = { projects.PACKED }, files = projects.packed_files() }))("verify", { name = "Packed" })
  end },
  { "verify_refused", function(ask) return ask("verify", { name = "Nope" }) end },
  { "check_proceed", function(ask) return ask("check", { name = "Identity" }) end },
  { "check_refuse", function(ask) return ask("check", { name = "Ghost" }) end },
  { "check_empty", function()
    local ask = bridge({ files = projects.bars_files({ [projects.BARS_SIDECAR] = 'return { ["Empty"] = {} }' }) })
    return ask("check", { name = "Empty" })
  end },
  { "check_headroom", function(ask) return ask("check", { name = "Headroom" }) end },
  { "check_subset", function(ask) return ask("check", { name = "Subset" }) end },
  { "check_unsafe", function()
    return (bridge({ snapshots = { projects.BARS_UNSAFE } }))("check", { name = "Identity" })
  end },
  { "apply_ok", function(ask) return ask("apply", { token = token_of(ask("check", { name = "Identity" })) }) end },
  { "apply_subset", function(ask) return ask("apply", { token = token_of(ask("check", { name = "Subset" })) }) end },
  { "apply_confirm", function(ask) return ask("apply", { token = token_of(ask("check", { name = "Headroom" })) }) end },
  { "apply_headroom", function()
    local ask = bridge({ snapshots = { projects.BARS, projects.BARS, projects.BARS, projects.BARS_ANCHORED } })
    local token = token_of(ask("check", { name = "Headroom" }))
    ask("apply", { token = token })
    return ask("apply", { token = token, headroom = "apply" })
  end },
  { "apply_cancelled", function(ask)
    local token = token_of(ask("check", { name = "Headroom" }))
    return ask("apply", { token = token, headroom = "cancel" })
  end },
  { "apply_noop", function()
    local ask = bridge({ snapshots = { projects.PACKED }, files = projects.packed_files() })
    return ask("apply", { token = token_of(ask("check", { name = "Packed" })) })
  end },
  { "apply_refused", function()
    local ask = bridge({ snapshots = { projects.BARS, projects.BARS_UNSAFE } })
    return ask("apply", { token = token_of(ask("check", { name = "Identity" })) })
  end },
  { "token_unknown", function(ask) return ask("apply", { token = "zzzzzz" }) end },
  { "token_stale", function()
    local ask, state = bridge()
    local token = token_of(ask("check", { name = "Identity" }))
    state.changes = state.changes + 1
    return ask("apply", { token = token })
  end },
  { "token_stale_arrangement", function()
    local ask, _, world = bridge()
    local token = token_of(ask("check", { name = "Identity" }))
    world.files[projects.BARS_SIDECAR] =
      projects.BARS_ARRANGEMENTS:gsub('"Alpha", "Bravo", "Charlie"', '"Bravo", "Alpha", "Charlie"')
    return ask("apply", { token = token })
  end },
  { "unknown_command", function(ask) return ask("nope", {}) end },
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
    local ask, state, world = bridge()
    local reply = play(ask, state, world)
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
