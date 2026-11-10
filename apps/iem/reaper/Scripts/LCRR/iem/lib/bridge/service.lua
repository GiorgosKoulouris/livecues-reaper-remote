-- The bridge front end: one request in, one JSON reply out, over the headless
-- cores (Arrange's pattern, ADR-0008; the wire format is
-- apps/arrange/docs/bridge.md, shared by both bridges).
--
--   local bridge = service.new({ api = reaper })
--   local id, reply = bridge.handle(raw)        -- raw: the `req` ExtState value
--   -- write id .. "|" .. reply to the `res` ExtState value
--
-- This module owns no ExtState and no loop (LCRR_IEM_Bridge.lua has those), so
-- the whole of it runs under busted.
--
-- **What the page can ask for** (`cmd`): `state`, `create` (name, optional `copy`: a mix GUID),
-- `rename` (guid, name),
-- `colour` (colour, `rrggbb`), `move_to_end` (guid of the folder), `delete` (guid of a mix) and
-- `output` (guid of a mix, channel or `none`, mono) and
-- `cell` (source and mix GUIDs, `on` 1 or 0), `row` (source GUID, `on`) and
-- `column` (mix GUID, `on`), `adopt` (guid of a stray mix), `cue` (no fields: the cue track and its sends; `output`
-- also takes the cue track's guid) and, in project ExtState with no undo step,
-- `snapshots` (list), `snapshot_save` (name, optional `overwrite`) and `snapshot_delete` (name); and
-- `snapshot_recall` (name, optional `mix`: a mix GUID), which writes sends and is one undo step. Each reply is
--
--   { v, command, project = { name, path }, status, ... }
--
-- `ok`, or `refused` with `error = { code, ... }`. A problem with the request
-- itself is a refusal too: `bad_request`, `request_truncated`,
-- `unknown_command`, `internal`. Wording is the page's: a reply is codes and
-- fields.
--
-- A write names the tracks it touches by GUID and is refused (`track_gone`) if
-- one is gone; each runs its whole change inside one undo block (lib/core/undo.lua).
-- A new command is a core in lib/core and one `h.<command> = core(...)` line below.
-- Locking is the page's: the bridge has no lock.

local json = require("shared.bridge.json")
local request = require("shared.bridge.request")
local state = require("lib.core.state")
local create = require("lib.core.create")
local rename = require("lib.core.rename")
local colour = require("lib.core.colour")
local move_to_end = require("lib.core.move_to_end")
local delete = require("lib.core.delete")
local output = require("lib.core.output")
local cell = require("lib.core.cell")
local bulk = require("lib.core.bulk")
local adopt = require("lib.core.adopt")
local cue = require("lib.core.cue")
local snapshots = require("lib.core.snapshots")
local snapshot_save = require("lib.core.snapshot_save")
local snapshot_delete = require("lib.core.snapshot_delete")
local snapshot_recall = require("lib.core.snapshot_recall")

local service = {}

service.VERSION = 1

local function refusal(code, fields)
  local err = fields or {}
  err.code = code
  return { status = "refused", error = err }
end

-- Handlers: (fields) -> reply fields ------------------------------------------

local function handlers(given)
  local h = {}

  function h.state()
    return state.run(given)
  end

  local function core(module)
    return function(fields)
      return module.run({ api = given.api, fields = fields })
    end
  end
  h.create = core(create)
  h.rename = core(rename)
  h.colour = core(colour)
  h.move_to_end = core(move_to_end)
  h.delete = core(delete)
  h.output = core(output)
  h.cell = core(cell)
  h.adopt = core(adopt)
  h.cue = core(cue)
  h.row = core(bulk.row)
  h.column = core(bulk.column)
  -- Snapshots live in project ExtState, which ignores undo: no undo block, no undo step (issue 10).
  h.snapshots = core(snapshots)
  h.snapshot_delete = core(snapshot_delete)
  -- Recall writes the project's sends, so it is one undo step (lib/core/snapshot_recall.lua).
  h.snapshot_recall = core(snapshot_recall)
  function h.snapshot_save(fields)
    return snapshot_save.run({ api = given.api, fields = fields, now = given.now })
  end

  return h
end

-- ----------------------------------------------------------------------------

--- Create the bridge front end.
-- @param given table { api = reaper }
function service.new(given)
  local api = given.api
  local table_of = handlers(given)
  local bridge = {}

  local function reply_for(command, body)
    local _, path = api.EnumProjects(-1, "")
    path = path or ""
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
    local handler = command and table_of[command]
    if not handler then
      return parsed.id, reply_for(command, refusal("unknown_command", { command = command }))
    end

    local ok, body = pcall(handler, parsed.fields)
    if not ok then
      -- A bug, or REAPER refusing a call: say so rather than going silent.
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
