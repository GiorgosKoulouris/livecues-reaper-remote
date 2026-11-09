-- Deriving the paths of files that sit beside a project.
--
-- Both the Arrangement sidecar (ADR-0003) and the run log live next to the
-- .RPP, and both need the same guard: an unsaved project has no path to sit
-- beside, and only a real project file has a sibling worth naming.

local paths = {}

local PROJECT_EXT = "[Rr][Pp][Pp]"

--- Swap a project's extension for a suffix, giving a path beside it.
-- @param project_path string absolute path to a saved .RPP
-- @param suffix string e.g. ".arrangements.lua"
-- @param what string what the sibling is, for the unsaved-project message
-- @return string|nil path, string|nil error message
function paths.sibling(project_path, suffix, what)
  if type(project_path) ~= "string" or project_path == "" then
    return nil, ("project has never been saved, so there is nowhere to put %s"):format(what)
  end

  -- Anchored at the end, so "Take.2.rpp" keeps its "2".
  local stem = project_path:match("^(.*)%." .. PROJECT_EXT .. "$")
  if not stem then
    return nil, ("not a REAPER project file: %s"):format(project_path)
  end

  return stem .. suffix
end

return paths
