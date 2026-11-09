-- Run logging.
--
-- A run's detail is appended to a log beside the .RPP and never shown: the
-- console is not opened (the screens are short, the run log holds the detail).
-- Aborts and precondition failures do not come through here -- those use
-- ShowMessageBox, because they must be seen.
--
-- Because a plan is a value (ADR-0001), logging what a script did is free, so
-- every script does it. The log is the audit trail that makes running without a
-- confirmation prompt acceptable.

local paths = require("lib.paths")

local log = {}

local LOG_SUFFIX = ".arrange.log"

--- Derive the log path that sits beside a project file.
function log.path_for(project_path)
  return paths.sibling(project_path, LOG_SUFFIX, "a run log")
end

local Logger = {}
Logger.__index = Logger

--- Append a line, optionally formatted.
-- With no extra arguments the text is taken literally, so a Region Name
-- containing "%" cannot be mistaken for a format directive.
function Logger:line(text, ...)
  if select("#", ...) > 0 then
    text = text:format(...)
  end
  self.lines[#self.lines + 1] = text
  return self
end

--- Append an already-rendered block, one log line per line of text.
-- A script that builds a report for the console has it as one string; without
-- this, each caller chops it back into lines itself, which is how two scripts
-- ended up with the same `gmatch` loop. Text is taken literally -- no format
-- directives -- for the reason `Logger:line` gives.
function Logger:block(text)
  for line in text:gmatch("([^\n]*)\n") do
    self.lines[#self.lines + 1] = line
  end
  return self
end

--- Start a run with a timestamped heading.
function Logger:heading(title)
  self.lines[#self.lines + 1] = ("[%s] %s"):format(self.clock(), title)
  return self
end

function Logger:is_empty()
  return #self.lines == 0
end

function Logger:text()
  return table.concat(self.lines, "\n") .. "\n"
end

--- Append the body to the log file.
-- Does nothing at all when nothing was logged, so an empty plan leaves no
-- trace, matching the undo convention.
-- @return boolean whether the log file was written
function Logger:write()
  if self:is_empty() then
    return false
  end

  local body = self:text()

  local path = log.path_for(self.project_path)
  if not path then
    return false
  end

  -- A log that cannot be written must not fail a run whose edits already
  -- succeeded.
  local handle = self.open(path, "a")
  if not handle then
    return false
  end

  handle:write(body)
  handle:write("\n")
  handle:close()
  return true
end

--- Create a logger.
-- @param opts table
--   project_path string path to the saved .RPP
--   api          the `reaper` table
--   clock        function returning a timestamp string (injected for specs)
--   open         io.open-alike (injected for specs)
function log.new(opts)
  return setmetatable({
    project_path = opts.project_path,
    api = opts.api,
    clock = opts.clock or function() return os.date("%Y-%m-%d %H:%M:%S") end,
    open = opts.open or io.open,
    lines = {},
  }, Logger)
end

return log
