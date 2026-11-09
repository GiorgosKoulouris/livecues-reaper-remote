-- What a core needs from the world, gathered in one place.
--
-- Every LCRR_Arrange_* action is a headless **core** (`lib/core/<action>.lua`:
-- request table in, result table out) with thin front ends over it: the
-- dialog front end each LCRR_Arrange_*.lua script is, and the bridge of spec
-- step 4. A core never opens a dialog. It reads the project, plans, applies,
-- writes the run log, and returns plain tables of codes and fields; the front
-- end decides how to ask for input and how to word the answer.
--
-- A core is handed `{ api = reaper }` and builds everything else from it. Each
-- other field overrides one dependency, which is how specs drive a core
-- without REAPER:
--
--   api         the `reaper` table (required)
--   snapshot    function() -> lib/project.lua snapshot
--   tempo       tempo oracle (ADR-0006)
--   automation  automation oracle
--   applier     lib/apply.lua or a stand-in
--   open        io.open-alike, for the .RPP, the sidecar and the run log
--   clock       timestamp function for the run log

local project = require("lib.project")
local tempo_oracle = require("lib.tempo_oracle")
local automation_oracle = require("lib.automation_oracle")
local apply = require("lib.apply")
local log = require("lib.log")

local env = {}

--- Resolve a core's environment from what the front end handed it.
function env.new(given)
  local api = assert(given and given.api, "a core needs env.api")
  local resolved = { api = api, applier = given.applier or apply }

  function resolved.snapshot()
    if given.snapshot then
      return given.snapshot()
    end
    return project.snapshot(api)
  end

  function resolved.tempo()
    return given.tempo or tempo_oracle.new(api, 0)
  end

  function resolved.automation()
    return given.automation or automation_oracle.new(api, 0)
  end

  -- Looked up per call rather than captured, so `io.open` is whatever it is
  -- when the core runs.
  function resolved.open(path, mode)
    return (given.open or io.open)(path, mode)
  end

  --- A file's whole contents, or nil when it cannot be opened.
  function resolved.read(path)
    local handle = resolved.open(path, "r")
    if not handle then
      return nil
    end
    local contents = handle:read("a")
    handle:close()
    return contents
  end

  --- A run logger for the project at `project_path` (lib/log.lua).
  function resolved.logger(project_path)
    return log.new({
      project_path = project_path,
      api = api,
      clock = given.clock,
      open = resolved.open,
    })
  end

  return resolved
end

--- Copy every field of `from` into `into`, and return `into`.
function env.merge(into, from)
  for key, value in pairs(from or {}) do
    into[key] = value
  end
  return into
end

--- Trim an Arrangement name the way every prompt always has.
function env.trim(name)
  return (name or ""):match("^%s*(.-)%s*$")
end

--- A refusal: nothing was done, and `fields.code` says why.
function env.refused(fields)
  return { status = "refused", error = fields }
end

return env
