-- Check, headless: everything knowable about applying an Arrangement, without
-- writing to the project. lib/report.lua's `check` is the judgement; this is
-- the reading around it and the run-log entry after it.
--
-- Two steps, so a front end can ask for the name in between:
--
--   local prepared = check.prepare({ api = reaper })
--   -- prepared.available lists the Arrangement names; empty when the sidecar
--   -- is missing, unreadable or empty, in which case there is nothing to ask
--   local result = check.run(prepared, { name = "Radio" })
--
-- `prepare` refuses only when the project has no regions. Every other problem
-- is a finding in `run`'s result, so one check reports all of them.

local env_lib = require("lib.core.env")
local sidecar = require("lib.sidecar")
local report = require("lib.report")
local text = require("lib.text.check")

local check = {}

check.TITLE = text.TITLE

--- Read what a check needs.
-- @param given table the core environment (lib/core/env.lua)
-- @return table { status = "ok", available, ... } or { status = "refused", error }
function check.prepare(given)
  local env = env_lib.new(given)
  local snapshot = env.snapshot()

  if #snapshot.regions == 0 then
    return env_lib.refused({ code = "no_regions" })
  end

  -- The .RPP text carries the one setting with no confirmed vanilla accessor
  -- (lib/validate.lua's `tempo_env_is_time_based`). An unsaved project has no
  -- .RPP to read, which `report.check` reports in its own right.
  local rpp_text = env.read(snapshot.project_path or "")

  -- A missing sidecar is reported, never repaired. Apply offers to import one
  -- because Apply needs a sidecar to proceed; a check that silently wrote a
  -- file would not be read-only, which is this action's whole contract.
  local arrangements, load_err, reason = sidecar.load(snapshot.project_path, env.open)

  return {
    status = "ok",
    env = env,
    snapshot = snapshot,
    project_path = snapshot.project_path,
    rpp_text = rpp_text,
    arrangements = arrangements,
    sidecar_error = load_err,
    sidecar_reason = reason,
    available = (arrangements and next(arrangements)) and sidecar.names(arrangements) or {},
  }
end

--- Check one Arrangement, and log the report beside the project.
-- @param prepared table from `check.prepare`
-- @param request table { name } -- "" when there were no names to choose from
-- @return table lib/report.lua's check result plus { status = "ok", name,
--   project_path }
function check.run(prepared, request)
  local env, snapshot = prepared.env, prepared.snapshot
  local name = env_lib.trim(request.name)

  local result = report.check({
    snapshot = snapshot,
    name = name,
    arrangements = prepared.arrangements,
    sidecar_reason = prepared.sidecar_reason,
    sidecar_error = prepared.sidecar_error,
    rpp_text = prepared.rpp_text,
    tempo = env.tempo(),
    automation = env.automation(),
  })

  -- Logged as well as printed, through the one call that does both: a check is
  -- the record of what the user was told *before* they ran Apply, and the log
  -- beside the .RPP is where the run that follows writes its own entry.
  --
  -- Unlike a plan, a check always logs. The convention that an empty plan
  -- leaves no trace exists because an empty plan changed nothing; a check that
  -- found nothing wrong is itself the result worth keeping.
  local logger = env.logger(snapshot.project_path)
  logger:heading(text.heading(name))
  logger:block(text.render(result))
  logger:write()

  return env_lib.merge({ status = "ok", name = name, project_path = snapshot.project_path }, result)
end

return check
