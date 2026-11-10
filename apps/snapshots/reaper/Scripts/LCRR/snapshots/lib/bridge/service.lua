-- The bridge front end: one request in, one JSON reply out, over the headless cores (Arrange's pattern, ADR-0008; the
-- wire format is apps/arrange/docs/bridge.md, shared by every bridge).
--
--   local bridge = service.new({ api = reaper })
--   local id, reply = bridge.handle(raw)        -- raw: the `req` ExtState value
--   -- write id .. "|" .. reply to the `res` ExtState value
--
-- This module owns no ExtState and no loop (LCRR_Snapshots_Bridge.lua has those), so the whole of it runs under busted.
--
-- **What the page can ask for** (`cmd`): `state` and `snapshots` (read-only), and
-- `snapshot_save` (`name`, optional `overwrite` 1) and `snapshot_delete` (`name`). Each reply is
--
--   { v, command, project = { name, path }, status, ... }
--
-- `ok`, or `refused` with `error = { code, ... }`. A problem with the request itself is a refusal too: `bad_request`,
-- `request_truncated`, `unknown_command`, `internal`. Wording is the page's: a reply is codes and fields.
--
-- A new command is a core in lib/core and one `h.<command> = ...` line below.

local json = require("shared.bridge.json")
local request = require("shared.bridge.request")
local state = require("lib.core.state")
local snapshots = require("lib.core.snapshots")
local snapshot_save = require("lib.core.snapshot_save")
local snapshot_delete = require("lib.core.snapshot_delete")

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

  -- Snapshots live in project ExtState, which ignores undo: no undo block, no undo step.
  function h.snapshots()
    return snapshots.run(given)
  end

  function h.snapshot_save(fields)
    return snapshot_save.run({ api = given.api, fields = fields, now = given.now })
  end

  function h.snapshot_delete(fields)
    return snapshot_delete.run({ api = given.api, fields = fields })
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
