-- lib/bridge/service.lua: the bridge front end over the cores, with nothing of
-- REAPER behind it. Raw request in, JSON reply out.
--
-- Pinned here: request parsing and its refusals, the check token, the host
-- never seeing a console window or a dialog, and what each reply carries.
-- The cores' own behaviour is core_*_spec.lua's.

local service = require("lib.bridge.service")
local core_env = require("spec.support.core_env")
local projects = require("spec.support.projects")

local merge = projects.merge

-- JSON is only ever written by the bridge, so the specs read it back with a
-- tiny parser rather than comparing strings. (Lua has no JSON; this is enough
-- for what the encoder emits.)
local function decode(text)
  local pos = 1
  local value

  local function skip()
    pos = text:find("[^ \n]", pos) or #text + 1
  end

  local function string_value()
    local out = {}
    pos = pos + 1
    while true do
      local char = text:sub(pos, pos)
      if char == '"' then
        pos = pos + 1
        return table.concat(out)
      elseif char == "\\" then
        local esc = text:sub(pos + 1, pos + 1)
        local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\" }
        if esc == "u" then
          out[#out + 1] = utf8.char(tonumber(text:sub(pos + 2, pos + 5), 16))
          pos = pos + 6
        else
          out[#out + 1] = map[esc]
          pos = pos + 2
        end
      else
        out[#out + 1] = char
        pos = pos + 1
      end
    end
  end

  function value()
    skip()
    local char = text:sub(pos, pos)
    if char == "{" then
      local object = {}
      pos = pos + 1
      skip()
      if text:sub(pos, pos) == "}" then
        pos = pos + 1
        return object
      end
      while true do
        skip()
        local key = string_value()
        skip()
        pos = pos + 1 -- :
        object[key] = value()
        skip()
        local sep = text:sub(pos, pos)
        pos = pos + 1
        if sep == "}" then
          return object
        end
      end
    elseif char == "[" then
      local list = {}
      pos = pos + 1
      skip()
      if text:sub(pos, pos) == "]" then
        pos = pos + 1
        return list
      end
      while true do
        list[#list + 1] = value()
        skip()
        local sep = text:sub(pos, pos)
        pos = pos + 1
        if sep == "]" then
          return list
        end
      end
    elseif char == '"' then
      return string_value()
    elseif text:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
    elseif text:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
    elseif text:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return nil
    end
    local number = text:match("^-?[%d.eE+-]+", pos)
    pos = pos + #number
    return tonumber(number)
  end

  return value()
end

local function encode_field(value)
  return (value:gsub("[^%w_.~-]", function(char) return ("%%%02X"):format(char:byte()) end))
end

--- A raw request: id|length|body.
local function raw(id, fields)
  local keys = {}
  for key in pairs(fields) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = key .. "=" .. encode_field(fields[key])
  end
  local body = table.concat(parts, "&")
  return ("%s|%d|%s"):format(id, #body, body)
end

--- A bridge over a project, plus the pieces a spec watches.
local function bridge(options)
  options = options or {}
  local path = options.path or projects.BARS_PATH
  local world_state = { changes = options.changes or 10, path = path }

  local api = merge({
    EnumProjects = function() return 0, world_state.path end,
    TimeMap2_timeToBeats = function() return 0, 1 end,
    GetProjectStateChangeCount = function() return world_state.changes end,
  }, options.api)

  local given, world = core_env.new(merge({
    snapshots = options.snapshots or { projects.BARS },
    files = projects.bars_files(),
    tempo = projects.bars_tempo(),
    api = api,
  }, options.core))
  given.random = options.random

  local handler = service.new(given)
  local state = world_state
  local count = 0
  local function ask(command, fields)
    count = count + 1
    local id, reply = handler.handle(raw("q" .. count, merge({ cmd = command }, fields)))
    return decode(reply), id, reply
  end
  return ask, world, state, handler
end

describe("lib/bridge/service.lua requests", function()
  it("answers under the request's id, naming the command and the project", function()
    local ask = bridge()
    local reply, id = ask("info", {})
    assert.are.equal("q1", id)
    assert.are.equal("info", reply.command)
    assert.are.equal(1, reply.v)
    assert.are.equal("Bars", reply.project.name)
    assert.are.equal(projects.BARS_PATH, reply.project.path)
  end)

  it("names an unsaved project with an empty name and path", function()
    local ask = bridge({ path = "" })
    local reply = ask("info", {})
    assert.are.equal("", reply.project.name)
    assert.are.equal("", reply.project.path)
  end)

  it("refuses a command it does not have", function()
    local ask = bridge()
    local reply = ask("format_disk", {})
    assert.are.equal("refused", reply.status)
    assert.are.equal("unknown_command", reply.error.code)
    assert.are.equal("format_disk", reply.error.command)
  end)

  it("refuses a request with no command", function()
    local _, handler = select(1, bridge()), select(4, bridge())
    local id, reply = handler.handle(raw("z1", { name = "x" }))
    assert.are.equal("z1", id)
    assert.are.equal("unknown_command", decode(reply).error.code)
  end)

  it("refuses a request that arrived short, and says how short", function()
    local handler = select(4, bridge())
    local whole = raw("z1", { cmd = "check", name = "Identity" })
    local id, reply = handler.handle(whole:sub(1, #whole - 5))
    assert.are.equal("z1", id)
    local decoded = decode(reply)
    assert.are.equal("refused", decoded.status)
    assert.are.equal("request_truncated", decoded.error.code)
    assert.are.equal(5, decoded.error.declared - decoded.error.received)
  end)

  it("refuses a malformed request, and stays silent when it has no id", function()
    local handler = select(4, bridge())
    local id, reply = handler.handle("z1|3|cmd=check")
    assert.are.equal("z1", id)
    assert.are.equal("bad_request", decode(reply).error.code)

    id, reply = handler.handle("no id here")
    assert.is_nil(id)
    assert.is_nil(reply)
  end)

  it("asks for a name when a command needs one", function()
    local ask = bridge()
    for _, command in ipairs({ "check", "verify", "capture" }) do
      local reply = ask(command, {})
      assert.are.equal("missing_field", reply.error.code, command)
      assert.are.equal("name", reply.error.field, command)
    end
  end)

  it("turns a failure inside a core into an internal refusal, not silence", function()
    local ask = bridge({ core = { snapshots = {} } })
    local reply = ask("duplicates", {})
    assert.are.equal("refused", reply.status)
    assert.are.equal("internal", reply.error.code)
  end)
end)

describe("lib/bridge/service.lua and the host", function()
  local commands = {
    { "info", {} },
    { "duplicates", {} },
    { "barlines", {} },
    { "check", { name = "Identity" } },
    { "verify", { name = "Identity" } },
    { "capture", { name = "Fresh" } },
  }
  for _, case in ipairs(commands) do
    it(case[1] .. " opens no console window and no dialog", function()
      local ask, world = bridge()
      ask(case[1], case[2])
      for _, event in ipairs(world.events) do
        assert.is_nil(type(event) == "table" and event.console or nil, "the console was written to")
      end
    end)
  end

  it("still writes the run log beside the project", function()
    local ask, world = bridge()
    ask("check", { name = "Identity" })
    local log = world.files["/proj/Bars.arrange.log"]
    assert.is_not_nil(log)
    assert.is_truthy(log:find('Check Arrangement -- "Identity"', 1, true))
  end)

  it("opens no dialog even when Apply refuses or asks", function()
    -- core_env makes ShowMessageBox, GetUserInputs and GetUserFileNameForRead
    -- throw; the service would turn that into an `internal` refusal.
    local ask = bridge({ snapshots = { projects.BARS, projects.BARS, projects.BARS_ANCHORED } })
    local checked = ask("check", { name = "Headroom" })
    local reply = ask("apply", { token = checked.token })
    assert.are_not.equal("internal", reply.error and reply.error.code)
  end)
end)

describe("lib/bridge/service.lua info", function()
  it("lists the Arrangements and the regions", function()
    local ask = bridge()
    local reply = ask("info", {})
    assert.are.equal("ok", reply.status)
    assert.are.equal("ok", reply.sidecar)
    assert.are.same({ "Ghost", "Headroom", "Identity", "Reordered", "Shrink", "Subset" }, reply.arrangements)
    assert.are.equal(4, #reply.regions)
    assert.are.same({ name = "Alpha", start_time = 0, end_time = 8 }, reply.regions[1])
    assert.is_true(reply.saved)
  end)

  it("says why there is nothing to choose from", function()
    local ask = bridge({ core = { files = { [projects.BARS_PATH] = projects.RPP_TIME } } })
    local reply = ask("info", {})
    assert.are.equal("ok", reply.status)
    assert.are.equal("missing", reply.sidecar)
    assert.are.same({}, reply.arrangements)
  end)
end)

describe("lib/bridge/service.lua read-only commands", function()
  it("finds duplicate and unnamed regions", function()
    local ask = bridge({ snapshots = { projects.DUPES }, core = { files = projects.packed_files() } })
    local reply = ask("duplicates", {})
    assert.are.equal("problems", reply.verdict)
    assert.are.equal(3, reply.region_count)
    assert.are.equal("duplicate", reply.problems[1].code)
    assert.are.equal("empty", reply.problems[2].code)
  end)

  it("sends bar lines per region", function()
    local ask = bridge()
    local reply = ask("barlines", {})
    assert.are.equal("ok", reply.status)
    assert.are.equal(4, #reply.regions)
    assert.are.equal("Alpha", reply.regions[1].name)
  end)

  it("sends the track timebase tally as a list, since modes are numbers", function()
    local tracks = { "Gtr", "Keys", "Perc" }
    local ask = bridge({
      api = {
        CountTracks = function() return #tracks end,
        GetTrack = function(_, index) return index end,
        GetMediaTrackInfo_Value = function(track) return track == 2 and 1 or 0 end,
        GetSetMediaTrackInfo_String = function(track) return true, tracks[track + 1] end,
      },
    })
    local reply = ask("timebase", {})
    assert.are.equal(3, #reply.tracks)
    assert.are.equal("Perc", reply.tracks[3].name)
    assert.are.same({ { mode = 0, count = 2 }, { mode = 1, count = 1 } }, reply.tally)
  end)

  it("passes a core's refusal through", function()
    local ask = bridge({ snapshots = { projects.EMPTY } })
    local reply = ask("barlines", {})
    assert.are.equal("refused", reply.status)
    assert.are.equal("no_regions", reply.error.code)
  end)
end)

describe("lib/bridge/service.lua capture", function()
  it("captures, and asks before replacing", function()
    local ask, world = bridge()
    local first = ask("capture", { name = "Fresh" })
    assert.are.equal("ok", first.status)
    assert.is_false(first.replaced)
    assert.are.same({ "Alpha", "Bravo", "Charlie", "Delta" }, first.regions)
    assert.is_truthy(world.files[projects.BARS_SIDECAR]:find("Fresh", 1, true))

    local again = ask("capture", { name = "Fresh" })
    assert.are.equal("confirm", again.status)
    assert.are.equal("replace", again.confirm.code)
    assert.are.equal("Fresh", again.confirm.name)

    local replaced = ask("capture", { name = "Fresh", replace = "1" })
    assert.are.equal("ok", replaced.status)
    assert.is_true(replaced.replaced)
  end)

  it("passes a refusal through", function()
    local ask = bridge({ snapshots = { projects.UNSAVED_BARS }, path = "" })
    local reply = ask("capture", { name = "Fresh" })
    assert.are.equal("refused", reply.status)
    assert.are.equal("project_unsaved", reply.error.code)
  end)

  it("reads a Region Name with every awkward character back whole", function()
    local name = 'A & B = C | 100% "x" \u{e9}'
    local ask = bridge({ snapshots = { projects.merge(projects.BARS, {
      regions = { { name = name, number = 1, start_time = 0, end_time = 8 } },
    }) } })
    local reply = ask("capture", { name = name })
    assert.are.equal(name, reply.name)
    assert.are.same({ name }, reply.regions)
  end)
end)

describe("lib/bridge/service.lua verify", function()
  it("reports a verdict and findings", function()
    local ask = bridge()
    local reply = ask("verify", { name = "Identity" })
    assert.are.equal("ok", reply.status)
    assert.are.equal("fail", reply.verdict)
    assert.is_true(#reply.findings > 0)
    assert.are.same({ "headroom_count" }, reply.blind_spots)
  end)

  it("refuses an Arrangement it does not know", function()
    local ask = bridge()
    local reply = ask("verify", { name = "Nope" })
    assert.are.equal("refused", reply.status)
    assert.are.equal("arrangement_unknown", reply.error.code)
  end)
end)

describe("lib/bridge/service.lua check and apply", function()
  -- check, then apply's prepare, then the snapshot after phase 1's anchors
  local function flow(options)
    return bridge(merge({
      snapshots = { projects.BARS, projects.BARS, projects.BARS_ANCHORED },
    }, options))
  end

  it("gives a token only to a Check that would proceed", function()
    local ask = flow()
    local ok = ask("check", { name = "Identity" })
    assert.are.equal("will proceed", ok.verdict)
    assert.are.equal(6, #ok.token)

    local refused = ask("check", { name = "Ghost" })
    assert.are.equal("will refuse", refused.verdict)
    assert.is_nil(refused.token)
  end)

  it("sends findings and blind spots, and whether Padding is exact", function()
    local ask = flow()
    local reply = ask("check", { name = "Identity" })
    assert.are.equal("Identity", reply.name)
    assert.is_true(#reply.findings > 0)
    assert.are.same({ "padding_grid", "anchor_drift", "padding_overlap" }, reply.blind_spots)
    assert.is_false(reply.padding_exact)
  end)

  it("applies a checked Arrangement from the token alone", function()
    local ask, world = flow()
    local checked = ask("check", { name = "Identity" })
    local reply = ask("apply", { token = checked.token })

    assert.are.equal("ok", reply.status)
    assert.are.equal("Identity", reply.name)
    assert.is_false(reply.noop)
    assert.is_true(reply.counts.regions > 0)
    assert.is_true(reply.anchors.changing > 0)
    local labels = table.concat(world.labels(), ",")
    assert.is_truthy(labels:find("undo begin", 1, true))
    assert.is_truthy(labels:find("apply.plan", 1, true))
    assert.is_truthy(world.files["/proj/Bars.arrange.log"]:find('Apply Arrangement -- "Identity"', 1, true))
  end)

  it("does not let a token be used twice", function()
    local ask = flow()
    local checked = ask("check", { name = "Identity" })
    ask("apply", { token = checked.token })
    local again = ask("apply", { token = checked.token })
    assert.are.equal("refused", again.status)
    assert.are.equal("token_unknown", again.error.code)
  end)

  it("refuses a token it never issued, and a request with none", function()
    local ask = flow()
    assert.are.equal("token_unknown", ask("apply", { token = "zzzzzz" }).error.code)
    local none = ask("apply", {})
    assert.are.equal("missing_field", none.error.code)
    assert.are.equal("token", none.error.field)
  end)

  it("refuses a token once the project has changed", function()
    local ask, world, state = flow()
    local checked = ask("check", { name = "Identity" })
    state.changes = state.changes + 1
    local reply = ask("apply", { token = checked.token })
    assert.are.equal("token_stale", reply.error.code)
    assert.are.equal("project_changed", reply.error.reason)
    assert.is_nil(world.files["/proj/Bars.arrange.log"]:find("Apply Arrangement", 1, true))
    assert.are.equal("token_unknown", ask("apply", { token = checked.token }).error.code)
  end)

  it("refuses a token when another project is active", function()
    local ask, _, state = flow()
    local checked = ask("check", { name = "Identity" })
    state.path = "/proj/Other.rpp"
    local reply = ask("apply", { token = checked.token })
    assert.are.equal("token_stale", reply.error.code)
    assert.are.equal("other_project", reply.error.reason)
    assert.are.equal("Other", reply.project.name)
  end)

  it("refuses a token from before the bridge restarted", function()
    local first = select(1, flow())
    local checked = first("check", { name = "Identity" })
    local second = flow()
    assert.are.equal("token_unknown", second("apply", { token = checked.token }).error.code)
  end)

  it("refuses an answer that is not apply, zero or cancel", function()
    local ask = flow()
    local checked = ask("check", { name = "Identity" })
    local reply = ask("apply", { token = checked.token, headroom = "yes" })
    assert.are.equal("bad_request", reply.error.code)
    assert.are.equal("headroom", reply.error.field)
    assert.are.equal("ok", ask("apply", { token = checked.token }).status)
  end)

  describe("with a Headroom", function()
    it("asks first, writing nothing, and keeps the token", function()
      local ask, world = flow()
      local checked = ask("check", { name = "Headroom" })
      assert.are.equal("will proceed", checked.verdict)
      local before = #world.events

      local reply = ask("apply", { token = checked.token })
      assert.are.equal("confirm", reply.status)
      assert.are.equal("headroom", reply.confirm.code)
      assert.are.same({ { name = "Bravo", seconds = 4 } }, reply.confirm.headroom)
      for index = before + 1, #world.events do
        local event = world.events[index]
        assert.is_true(type(event) == "string" and event:match("^write ") ~= nil,
          "something other than a log write reached the project")
      end
      assert.is_nil(world.files["/proj/Bars.arrange.log"]:find("Apply Arrangement", 1, true))
    end)

    it("applies on `apply`, and drops the token", function()
      local ask = flow({ snapshots = { projects.BARS, projects.BARS, projects.BARS, projects.BARS_ANCHORED } })
      local checked = ask("check", { name = "Headroom" })
      ask("apply", { token = checked.token })
      local reply = ask("apply", { token = checked.token, headroom = "apply" })
      assert.are.equal("ok", reply.status)
      assert.are.equal(1, #reply.headroom)
      assert.are.equal("Bravo", reply.headroom[1].name)
      assert.are.equal("token_unknown", ask("apply", { token = checked.token }).error.code)
    end)

    it("repacks without it on `zero`", function()
      local ask = flow()
      local checked = ask("check", { name = "Headroom" })
      local reply = ask("apply", { token = checked.token, headroom = "zero" })
      assert.are.equal("ok", reply.status)
      assert.are.same({}, reply.headroom)
    end)

    it("does nothing on `cancel`, and drops the token", function()
      local ask, world = flow()
      local checked = ask("check", { name = "Headroom" })
      local reply = ask("apply", { token = checked.token, headroom = "cancel" })
      assert.are.equal("cancelled", reply.status)
      assert.is_nil(table.concat(world.labels(), ","):find("apply.", 1, true))
      assert.are.equal("token_unknown", ask("apply", { token = checked.token }).error.code)
    end)
  end)

  it("passes an Apply refusal through, with the token spent", function()
    local ask = bridge({ snapshots = { projects.BARS, projects.BARS_UNSAFE },
      core = { files = projects.bars_files() } })
    local checked = ask("check", { name = "Identity" })
    local reply = ask("apply", { token = checked.token })
    assert.are.equal("refused", reply.status)
    assert.is_truthy(reply.error.code)
    assert.are.equal("token_unknown", ask("apply", { token = checked.token }).error.code)
  end)

  it("reports what Apply dropped, since the log is the only other record", function()
    local ask = flow()
    local checked = ask("check", { name = "Subset" })
    local reply = ask("apply", { token = checked.token })
    assert.are.equal("ok", reply.status)
    assert.is_table(reply.dropped.items)
    assert.is_table(reply.dropped.envelope_points)
    assert.is_truthy(reply.parked.regions)
  end)
end)
