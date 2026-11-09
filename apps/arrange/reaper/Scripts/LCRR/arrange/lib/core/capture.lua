-- Capture, headless: write the project's regions, in timeline order, into the
-- Arrangement sidecar as a named Arrangement. Changes no project state.
--
--   local prepared = capture.prepare({ api = reaper })
--   local result = capture.run(prepared, { name = "Live" })
--   -- result.status == "confirm": an Arrangement of that name exists. Nothing
--   -- has been written; run again with replace = true to overwrite it.
--
-- Every step returns `{ status = "refused", error = { code, ... } }` when it
-- cannot go on, with nothing written.

local env_lib = require("lib.core.env")
local project = require("lib.project")
local validate = require("lib.validate")
local sidecar = require("lib.sidecar")
local text = require("lib.text.capture")

local capture = {}

capture.TITLE = text.TITLE

-- What the name prompt offers before the user types anything.
capture.DEFAULT_NAME = "Captured"

--- Read the project and its sidecar.
-- @return table { status = "ok", ... } or a refusal with code
--   project_unsaved { message }, no_regions, region_names { problems } or
--   sidecar_invalid { error }
function capture.prepare(given)
  local env = env_lib.new(given)
  local snapshot = env.snapshot()

  local saved, saved_err = validate.project_saved(snapshot.project_path)
  if not saved then
    return env_lib.refused({ code = "project_unsaved", message = saved_err })
  end

  if #snapshot.regions == 0 then
    return env_lib.refused({ code = "no_regions" })
  end

  -- Names are the primary key an Arrangement uses, so they are checked before
  -- anything is written rather than after (ADR-0003).
  local names_ok, problems = validate.region_names(snapshot.regions)
  if not names_ok then
    return env_lib.refused({ code = "region_names", problems = problems })
  end

  local existing, load_err, reason = sidecar.load(snapshot.project_path, env.open)
  if reason == "invalid" then
    -- Overwriting here would silently discard Arrangements the user hand-wrote.
    return env_lib.refused({ code = "sidecar_invalid", error = load_err })
  end

  return {
    status = "ok",
    env = env,
    snapshot = snapshot,
    project_path = snapshot.project_path,
    arrangements = existing or {},
  }
end

--- Capture the current order under `name`, and log it.
-- @param prepared table from `capture.prepare`
-- @param request table { name, replace }
-- @return table { status = "ok", name, replaced, regions, path, region_reader,
--   project_path }, { status = "confirm", confirm = { code = "replace", name } },
--   or a refusal with code name_empty or save_failed { error }
function capture.run(prepared, request)
  local env, snapshot, arrangements = prepared.env, prepared.snapshot, prepared.arrangements

  local name = env_lib.trim(request.name)
  if name == "" then
    return env_lib.refused({ code = "name_empty" })
  end

  local replacing = arrangements[name] ~= nil
  if replacing and request.replace ~= true then
    return { status = "confirm", confirm = { code = "replace", name = name } }
  end

  arrangements[name] = project.region_names(snapshot)

  local written, save_err = sidecar.save(snapshot.project_path, arrangements, env.open)
  if not written then
    return env_lib.refused({ code = "save_failed", error = save_err })
  end

  local result = {
    status = "ok",
    name = name,
    replaced = replacing,
    regions = arrangements[name],
    path = written,
    region_reader = snapshot.region_reader,
    project_path = snapshot.project_path,
  }

  local logger = env.logger(snapshot.project_path)
  logger:heading(text.heading(result))
  for _, line in ipairs(text.log_lines(result)) do
    logger:line(line)
  end
  logger:write()

  return result
end

return capture
