-- The bridge front end: one request in, one JSON reply out, over the same
-- headless cores the dialog scripts use (ADR-0008).
--
--   local bridge = service.new({ api = reaper })
--   local id, reply = bridge.handle(raw)        -- raw: the `req` ExtState value
--   -- write id .. "|" .. reply to the `res` ExtState value
--
-- This module owns no ExtState and no loop (LCRR_Arrange_Bridge.lua has those),
-- so the whole of it runs under busted.
--
-- **What the page can ask for** (`cmd`): `info`, `arrangements`, `duplicates`,
-- `timebase`, `barlines`, `capture`, `edit`, `verify`, `check` and `apply`. Each reply is
--
--   { v, command, project = { name, path }, status, ... }
--
-- with the core's own statuses: `ok`, `refused` (with `error = { code, ... }`),
-- `confirm` (the page asks, then repeats the request with its answer) and
-- `cancelled`. A problem with the request itself is a refusal too: `bad_request`,
-- `request_truncated`, `unknown_command`, `missing_field`, and for Apply
-- `token_unknown` and `token_stale`. Wording is the page's: a reply is codes
-- and fields, as a core's result is.
--
-- **The page never causes a dialog on the host.** The cores never open one.
-- Their run log (`Logger:write`) also prints to REAPER's console, which would
-- open that window on the host, so the cores here get an `api` whose
-- ShowConsoleMsg does nothing. The log *file* beside the project is still
-- written: for Dropped Material it is the only record.
--
-- **Apply only after Check** (`.scratch/arrange/spec.md`). A Check that would
-- proceed returns a `token`. Apply carries the token and the Headroom answer
-- and nothing else: the bridge looks up the Arrangement name, and refuses
-- unless the project's path and state-change count are what the Check saw and
-- the Arrangement's entries and Headroom are what the Check read.
--
-- A reply is never a core result passed through whole: those carry `env`,
-- the snapshot and plans keyed by number. Each view below picks its fields.

local env_lib = require("lib.core.env")
local project = require("lib.project")
local sidecar = require("lib.sidecar")
local json = require("lib.bridge.json")
local request = require("lib.bridge.request")
local tokens = require("lib.bridge.tokens")

local apply = require("lib.core.apply")
local capture = require("lib.core.capture")
local check = require("lib.core.check")
local edit = require("lib.core.edit")
local verify = require("lib.core.verify")
local find_duplicates = require("lib.core.find_duplicate_region_names")
local show_bar_lines = require("lib.core.show_bar_lines")
local show_track_timebase = require("lib.core.show_track_timebase")

local service = {}

service.VERSION = 1

local HEADROOM_ANSWERS = { apply = true, zero = true, cancel = true }

--- `api`, with the console silenced. Everything else is REAPER's own.
local function quiet(api)
  return setmetatable({ ShowConsoleMsg = function() end }, { __index = api })
end

local function copy_of(given)
  local out = {}
  for key, value in pairs(given) do
    out[key] = value
  end
  return out
end

local function refusal(code, fields)
  local err = fields or {}
  err.code = code
  return { status = "refused", error = err }
end

-- Wire views -----------------------------------------------------------------

local function plain_list(list)
  return list or {}
end

local function apply_view(result)
  local plan, anchor_plan = result.plan, result.anchor_plan
  local regions_parked = 0
  for _, park in ipairs(plan.parks) do
    if park.kind == "region" then
      regions_parked = regions_parked + 1
    end
  end
  return {
    status = "ok",
    name = result.name,
    noop = result.noop,
    counts = {
      regions = #plan.places,
      markers = #plan.marker_moves,
      tempo_markers = #plan.tempo_moves,
      envelope_points = #plan.envelope_moves,
      items = #plan.item_moves,
      cuts = #plan.splits,
      envelope_anchors = #plan.envelope_anchors,
    },
    anchors = { total = #anchor_plan.anchors, changing = anchor_plan.changing },
    places = plain_list(plan.places),
    headroom = plain_list(plan.headroom),
    pads = plain_list(plan.pads),
    parked = { regions = regions_parked, other = #plan.parks - regions_parked, delta = plan.park_delta or 0 },
    dropped = { items = plain_list(plan.drops), envelope_points = plain_list(plan.envelope_drops) },
  }
end

local function report_view(result, extra)
  local view = {
    status = "ok",
    name = result.name,
    verdict = result.verdict,
    findings = result.findings,
    blind_spots = result.blind_spots,
    region_reader = result.region_reader,
  }
  for key, value in pairs(extra or {}) do
    view[key] = value
  end
  return view
end

local function tally_view(tally)
  local rows = {}
  for mode, count in pairs(tally) do
    rows[#rows + 1] = { mode = mode, count = count }
  end
  table.sort(rows, function(a, b) return a.mode < b.mode end)
  return rows
end

-- A core's refusal, or nil when `result` is not one.
local function refused_or(result, view)
  if result.status == "refused" then
    return { status = "refused", error = result.error }
  end
  return view(result)
end

-- Handlers: (self, fields) -> reply fields -----------------------------------

local function handlers(self)
  local given, api = self.given, self.given.api
  local h = {}

  local function need(fields, key)
    local value = fields[key]
    if value == nil or value == "" then
      return nil, refusal("missing_field", { field = key })
    end
    return value
  end

  function h.info()
    local env = env_lib.new(given)
    local snapshot = env.snapshot()
    local arrangements, _, reason = sidecar.load(snapshot.project_path, env.open)
    local names = (arrangements and next(arrangements)) and sidecar.names(arrangements) or {}

    local regions = {}
    for _, region in ipairs(snapshot.regions) do
      regions[#regions + 1] = { name = region.name, start_time = region.start_time, end_time = region.end_time }
    end

    return {
      status = "ok",
      bridge_version = service.VERSION,
      saved = (snapshot.project_path or "") ~= "",
      -- "ok", or why there are no Arrangements to choose from: missing,
      -- invalid or unsaved (lib/sidecar.lua's reasons).
      sidecar = arrangements and "ok" or reason,
      arrangements = names,
      regions = regions,
    }
  end

  -- The sidecar as the editor needs it: its state, revision, every Arrangement
  -- with its Headroom, and the project's regions in timeline order.
  function h.arrangements()
    local env = env_lib.new(given)
    local snapshot = env.snapshot()
    local project_path = snapshot.project_path or ""

    local regions = {}
    for _, region in ipairs(snapshot.regions) do
      regions[#regions + 1] = { name = region.name, start_time = region.start_time, end_time = region.end_time }
    end

    local view = {
      status = "ok",
      saved = project_path ~= "",
      sidecar = "unsaved",
      revision = "none",
      arrangements = {},
      regions = regions,
    }
    local path = sidecar.path_for(project_path)
    if not path then
      return view
    end

    local source = env.read(path)
    view.revision = sidecar.revision(source)
    if source == nil then
      view.sidecar = "missing"
      return view
    end
    local parsed, parse_err = sidecar.parse(source)
    if not parsed then
      view.sidecar = "invalid"
      view.parse_error = parse_err
      return view
    end
    view.sidecar = "ok"
    view.canonical = sidecar.is_canonical(source)
    for _, name in ipairs(sidecar.names(parsed)) do
      view.arrangements[#view.arrangements + 1] = { name = name, entries = edit.entries_of(parsed[name]) }
    end
    return view
  end

  -- One edit (lib/core/edit.lua). `revision` and `project` are what the page
  -- read; the core refuses when either no longer holds.
  function h.edit(fields)
    local operation, bad = need(fields, "operation")
    if not operation then
      return bad
    end
    local revision
    revision, bad = need(fields, "revision")
    if not revision then
      return bad
    end
    local project_path
    project_path, bad = need(fields, "project")
    if not project_path then
      return bad
    end
    local result = edit.run(given, {
      operation = operation,
      arrangement = fields.arrangement,
      region = fields.region,
      slot = fields.slot,
      headroom = fields.headroom,
      name = fields.name,
      revision = revision,
      project_path = project_path,
      rewrite = fields.rewrite == "1",
    })
    if result.status ~= "ok" then
      return result
    end
    return {
      status = "ok",
      operation = result.operation,
      name = result.name,
      from = result.from,
      revision = result.revision,
      path = result.path,
      names = result.names,
      entries = result.entries,
      deleted_entries = result.deleted_entries,
    }
  end

  function h.duplicates()
    local result = find_duplicates.run(given)
    return {
      status = "ok",
      verdict = result.verdict,
      problems = result.problems,
      region_count = result.region_count,
      region_reader = result.region_reader,
    }
  end

  function h.timebase()
    return refused_or(show_track_timebase.run(given), function(result)
      return { status = "ok", tracks = result.tracks, tally = tally_view(result.tally) }
    end)
  end

  function h.barlines()
    return refused_or(show_bar_lines.run(given), function(result)
      return {
        status = "ok",
        region_reader = result.region_reader,
        origin_measure = result.origin_measure,
        origin = result.origin,
        pad_threshold = result.pad_threshold,
        regions = result.regions,
        padded = result.padded,
        total_pad = result.total_pad,
      }
    end)
  end

  function h.capture(fields)
    local name, bad = need(fields, "name")
    if not name then
      return bad
    end
    local prepared = capture.prepare(given)
    if prepared.status == "refused" then
      return prepared
    end
    local result = capture.run(prepared, { name = name, replace = fields.replace == "1",
      rewrite = fields.rewrite == "1" })
    if result.status ~= "ok" then
      return result
    end
    return {
      status = "ok",
      name = result.name,
      replaced = result.replaced,
      regions = result.regions,
      path = result.path,
      region_reader = result.region_reader,
    }
  end

  function h.verify(fields)
    local name, bad = need(fields, "name")
    if not name then
      return bad
    end
    local prepared = verify.prepare(given)
    if prepared.status == "refused" then
      return prepared
    end
    return refused_or(verify.run(prepared, { name = name }), report_view)
  end

  function h.check(fields)
    local name, bad = need(fields, "name")
    if not name then
      return bad
    end
    local prepared = check.prepare(given)
    if prepared.status == "refused" then
      return prepared
    end
    local result = check.run(prepared, { name = name })

    local view = report_view(result, { padding_exact = result.padding_exact })
    if result.verdict == "will proceed" then
      view.token = self.tokens.issue({
        name = result.name,
        fingerprint = tokens.fingerprint(prepared.arrangements[result.name]),
        path = project.path(api),
        changes = api.GetProjectStateChangeCount(0),
      })
    end
    return view
  end

  function h.apply(fields)
    local token, bad = need(fields, "token")
    if not token then
      return bad
    end
    local answer = fields.headroom
    if answer ~= nil and not HEADROOM_ANSWERS[answer] then
      return refusal("bad_request", { field = "headroom" })
    end

    local checked = self.tokens.get(token)
    if not checked then
      return refusal("token_unknown")
    end
    if project.path(api) ~= checked.path then
      self.tokens.drop(token)
      return refusal("token_stale", { reason = "other_project" })
    end
    if api.GetProjectStateChangeCount(0) ~= checked.changes then
      self.tokens.drop(token)
      return refusal("token_stale", { reason = "project_changed" })
    end

    local prepared = apply.prepare(given)
    if prepared.status == "refused" then
      self.tokens.drop(token)
      return prepared
    end

    -- Edited since the Check, from the page or a text editor: this Apply would
    -- do something the user has not read. Other Arrangements don't matter.
    local current = prepared.arrangements[checked.name]
    if not current or tokens.fingerprint(current) ~= checked.fingerprint then
      self.tokens.drop(token)
      return refusal("token_stale", { reason = "arrangement_changed" })
    end

    local result = apply.run(prepared, { name = checked.name, headroom = answer })

    -- The one answer that keeps the token: nothing has been written, and the
    -- page repeats the request with its choice.
    if result.status == "confirm" then
      return {
        status = "confirm",
        name = checked.name,
        confirm = result.confirm,
      }
    end

    self.tokens.drop(token)
    if result.status == "ok" then
      return apply_view(result)
    end
    return result
  end

  return h
end

-- ----------------------------------------------------------------------------

--- Create the bridge front end.
-- @param given table the core environment (lib/core/env.lua), plus
--   random  function(n) -> integer in 1..n, for check tokens
function service.new(given)
  local self = { given = copy_of(given) }
  self.given.api = quiet(given.api)
  self.tokens = tokens.new(given.random)
  self.handlers = handlers(self)

  local bridge = {}

  local function reply_for(command, body)
    local path = project.path(self.given.api)
    body.v = service.VERSION
    body.command = command
    body.project = { name = path:match("([^\\/]*)%.[Rr][Pp][Pp]$") or "", path = path }
    return json.encode(body)
  end

  --- Answer one raw request.
  -- @param raw string the `req` ExtState value
  -- @return string|nil id to answer under (nil: unreadable, answer nothing)
  -- @return string|nil the JSON reply
  function bridge.handle(raw)
    local parsed, bad = request.parse(raw)
    if not parsed then
      if not bad.id then
        return nil
      end
      local id = bad.id
      bad.id = nil
      return id, reply_for(nil, refusal(bad.code, bad))
    end

    local command = parsed.fields.cmd
    local handler = command and self.handlers[command]
    if not handler then
      return parsed.id, reply_for(command, refusal("unknown_command", { command = command }))
    end

    local ok, body = pcall(handler, parsed.fields)
    if not ok then
      -- A bug, or REAPER refusing a call. Say so rather than going silent: the
      -- page would otherwise wait out its timeout.
      return parsed.id, reply_for(command, refusal("internal", { message = tostring(body) }))
    end

    local encoded_ok, encoded = pcall(reply_for, command, body)
    if not encoded_ok then
      return parsed.id, reply_for(command, refusal("internal", { message = tostring(encoded) }))
    end
    return parsed.id, encoded
  end

  return bridge
end

return service
