-- Edit, headless: one small operation on the Arrangement sidecar, for the page
-- (ADR-0009). Only the bridge fronts it; there is no Action-list script.
--
--   local result = edit.run({ api = reaper }, {
--     operation = "move", arrangement = "Live", region = "Intro", slot = 3,
--     revision = "…", project_path = "C:/…/Song.rpp",
--   })
--
-- Operations and their fields:
--   move            arrangement, region, slot
--   set_headroom    arrangement, region, headroom (seconds)
--   add             arrangement, region, slot (optional; default the end)
--   remove          arrangement, region
--   clear_headroom  arrangement
--   new             name
--   duplicate       arrangement, name (the copy's)
--   rename          arrangement, name (the new one)
--   delete          arrangement
--
-- Every request also carries the `revision` the page read (`sidecar.revision`
-- of the file's text, "none" for a missing file) and the `project_path` it was
-- made against; `rewrite = true` answers the rewrite question.
--
-- Results:
--   { status = "ok", operation, name, revision, path, names, entries,
--     from?, deleted_entries? }  `entries` is the edited Arrangement as a list
--     of { name, headroom } (absent after delete); `names` is every
--     Arrangement's name, sorted.
--   { status = "refused", error = { code } }  project_unsaved, other_project,
--     sidecar_changed, sidecar_invalid { error }, operation_unknown, the codes
--     of lib/arrangement_ops.lua, would_be_invalid, save_failed { error }
--   { status = "confirm", confirm = { code = "rewrite" } }  the file is not in
--     canonical form, so saving would drop comments; nothing is written
--
-- Nothing is written unless the result is `ok`.

local env_lib = require("lib.core.env")
local ops = require("lib.arrangement_ops")
local sidecar = require("lib.sidecar")
local validate = require("lib.validate")
local text = require("lib.text.edit")

local edit = {}

-- Fields reach the bridge as flat strings; a number may arrive as one.
local function number(value)
  if type(value) == "string" then
    return tonumber(value)
  end
  return value
end

local function integer(value)
  value = number(value)
  if math.type(value) == "float" and value == math.floor(value) and value > -2^53 and value < 2^53 then
    return math.tointeger(value)
  end
  return value
end

-- Each applies the operation and returns the new Arrangements, or nil and a
-- refusal code.
local OPERATIONS = {
  move = function(arrangements, request)
    return ops.move(arrangements, request.arrangement, request.region, integer(request.slot))
  end,
  set_headroom = function(arrangements, request)
    return ops.set_headroom(arrangements, request.arrangement, request.region,
      number(request.headroom))
  end,
  add = function(arrangements, request)
    return ops.add(arrangements, request.arrangement, request.region, integer(request.slot))
  end,
  remove = function(arrangements, request)
    return ops.remove(arrangements, request.arrangement, request.region)
  end,
  clear_headroom = function(arrangements, request)
    return ops.clear_headroom(arrangements, request.arrangement)
  end,
  new = function(arrangements, request)
    return ops.new(arrangements, env_lib.trim(request.name))
  end,
  duplicate = function(arrangements, request)
    return ops.duplicate(arrangements, request.arrangement, env_lib.trim(request.name))
  end,
  rename = function(arrangements, request)
    return ops.rename(arrangements, request.arrangement, env_lib.trim(request.name))
  end,
  delete = function(arrangements, request)
    return ops.delete(arrangements, request.arrangement)
  end,
}

-- The Arrangement an edit leaves behind: the new name where one is given.
local RENAMES = { new = true, duplicate = true, rename = true }

local function entries_of(arrangement)
  local entries = {}
  for index, region in ipairs(arrangement) do
    entries[index] = { name = region, headroom = (arrangement.headroom or {})[region] or 0 }
  end
  return entries
end

edit.entries_of = entries_of

--- Run one edit.
-- @param given table { api = reaper, ... } as for every core
-- @param request table see the header
function edit.run(given, request)
  local env = env_lib.new(given)

  local operation = OPERATIONS[request.operation]
  if not operation then
    return env_lib.refused({ code = "operation_unknown" })
  end

  local project_path = env.project_path()
  local saved = validate.project_saved(project_path)
  if not saved then
    return env_lib.refused({ code = "project_unsaved" })
  end
  if request.project_path ~= project_path then
    return env_lib.refused({ code = "other_project" })
  end

  local path = sidecar.path_for(project_path)
  if not path then
    return env_lib.refused({ code = "project_unsaved" })
  end

  local source = env.read(path)
  if request.revision ~= sidecar.revision(source) then
    return env_lib.refused({ code = "sidecar_changed" })
  end

  local arrangements = {}
  if source ~= nil then
    local parsed, parse_err = sidecar.parse(source)
    if not parsed then
      return env_lib.refused({ code = "sidecar_invalid", error = parse_err })
    end
    arrangements = parsed
  end

  local updated, code = operation(arrangements, request)
  if not updated then
    return env_lib.refused({ code = code })
  end
  local name = RENAMES[request.operation] and env_lib.trim(request.name) or request.arrangement

  -- The edited table must survive the round trip, or the file would not load.
  local rendered = sidecar.serialize(updated)
  local reparsed = sidecar.parse(rendered)
  if not reparsed then
    return env_lib.refused({ code = "would_be_invalid" })
  end

  if source ~= nil and request.rewrite ~= true
      and not sidecar.is_canonical(source) then
    return { status = "confirm", confirm = { code = "rewrite" } }
  end

  local written, save_err = sidecar.save(project_path, updated, env.open)
  if not written then
    return env_lib.refused({ code = "save_failed", error = save_err })
  end

  local result = {
    status = "ok",
    operation = request.operation,
    name = name,
    revision = sidecar.revision(rendered),
    path = written,
    names = sidecar.names(updated),
    entries = updated[name] and entries_of(updated[name]) or nil,
  }
  if request.operation == "duplicate" or request.operation == "rename" then
    result.from = request.arrangement
  end
  if request.operation == "delete" then
    result.deleted_entries = entries_of(arrangements[name])
  end

  if text.is_logged(request.operation) then
    local logger = env.logger(project_path)
    logger:heading(text.heading(result))
    for _, line in ipairs(text.log_lines(result)) do
      logger:line(line)
    end
    logger:write()
  end

  return result
end

return edit
