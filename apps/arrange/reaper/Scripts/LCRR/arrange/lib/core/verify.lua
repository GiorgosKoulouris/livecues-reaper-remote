-- Verify, headless: does the timeline hold the properties a Repack promises?
-- lib/report.lua's `verify` is the judgement; this is the reading around it
-- and the run-log entry after it.
--
--   local prepared = verify.prepare({ api = reaper })   -- prepared.available
--   local result = verify.run(prepared, { name = "Radio" })
--
-- Both return `{ status = "refused", error = { code, ... } }` when they
-- cannot go on; nothing is written in that case.

local env_lib = require("lib.core.env")
local sidecar = require("lib.sidecar")
local report = require("lib.report")
local text = require("lib.text.verify")

local verify = {}

verify.TITLE = text.TITLE

--- Read the project and its Arrangements.
-- @return table { status = "ok", available, ... } or a refusal with code
--   no_regions, sidecar_invalid { error }, sidecar_unsaved or no_arrangements
function verify.prepare(given)
  local env = env_lib.new(given)
  local snapshot = env.snapshot()

  if #snapshot.regions == 0 then
    return env_lib.refused({ code = "no_regions" })
  end

  local arrangements, load_err, reason = sidecar.load(snapshot.project_path, env.open)
  if reason == "invalid" then
    return env_lib.refused({ code = "sidecar_invalid", error = load_err })
  end
  if reason == "unsaved" then
    return env_lib.refused({ code = "sidecar_unsaved" })
  end
  if not arrangements or not next(arrangements) then
    return env_lib.refused({ code = "no_arrangements" })
  end

  return {
    status = "ok",
    env = env,
    snapshot = snapshot,
    project_path = snapshot.project_path,
    arrangements = arrangements,
    available = sidecar.names(arrangements),
  }
end

--- Verify the timeline against one Arrangement, and log the report.
-- @param prepared table from `verify.prepare`
-- @param request table { name }
-- @return table lib/report.lua's verify result plus { status = "ok", name,
--   project_path }, or a refusal with code arrangement_unknown { name, available }
function verify.run(prepared, request)
  local env, snapshot = prepared.env, prepared.snapshot
  local name = env_lib.trim(request.name)

  local arrangement = prepared.arrangements[name]
  if not arrangement then
    return env_lib.refused({ code = "arrangement_unknown", name = name, available = prepared.available })
  end

  local result = report.verify({
    snapshot = snapshot,
    arrangement = arrangement,
    tempo = env.tempo(),
  })

  -- Always logged, pass or fail. A confirmation is worth as much as a failure
  -- in the record beside the project, and it is the line that pairs with the
  -- Apply entry above it.
  local logger = env.logger(snapshot.project_path)
  logger:heading(text.heading(name))
  logger:block(text.render(result, name))
  logger:write()

  return env_lib.merge({ status = "ok", name = name, project_path = snapshot.project_path }, result)
end

return verify
