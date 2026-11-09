-- Find Duplicate Region Names, headless: every Region Name used more than
-- once, and every region with no name. Reads only; writes its result to the
-- run log (console plus the file beside the .RPP).
--
--   local result = find.run({ api = reaper })

local env_lib = require("lib.core.env")
local validate = require("lib.validate")
local text = require("lib.text.find_duplicate_region_names")

local find = {}

find.TITLE = text.TITLE

--- @return table { status = "ok", verdict = "no_regions" | "clean" | "problems",
---   problems, region_count, region_reader, project_path }
function find.run(given)
  local env = env_lib.new(given)
  local snapshot = env.snapshot()

  local result = {
    status = "ok",
    region_count = #snapshot.regions,
    region_reader = snapshot.region_reader,
    project_path = snapshot.project_path,
    problems = {},
  }

  if #snapshot.regions == 0 then
    result.verdict = "no_regions"
  else
    local ok, problems = validate.region_names(snapshot.regions)
    result.verdict = ok and "clean" or "problems"
    result.problems = problems
  end

  -- Console plus a timestamped append to the log beside the .RPP, on every
  -- outcome. An unsaved project has nowhere to put the file; lib/log.lua skips
  -- it and still reaches the console.
  local logger = env.logger(snapshot.project_path)
  logger:heading(text.TITLE)
  for _, line in ipairs(text.log_lines(result)) do
    logger:line(line)
  end
  logger:write()

  return result
end

return find
