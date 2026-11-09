-- The words for the Arrangement edits the page makes (lib/core/edit.lua): the
-- run-log entries for New, Duplicate, Rename and Delete, and a plain sentence
-- for each refusal. Pure: no `reaper.*`.

local text = {}

text.TITLE = "Edit Arrangements"

-- Only these four are logged; moves, adds, removes and Headroom changes are not.
local LOGGED = { new = true, duplicate = true, rename = true, delete = true }

--- Whether an operation leaves a run-log entry.
function text.is_logged(operation)
  return LOGGED[operation] == true
end

--- The run-log heading for an edit.
function text.heading(result)
  return ("%s -- %s %q"):format(text.TITLE, result.operation, result.name)
end

local function seconds(value)
  return ("%+.14g s"):format(value)
end

--- The run log's body for an edit.
-- Delete lists every entry, so a deleted Arrangement can be rebuilt from the log.
function text.log_lines(result)
  local lines = {}
  local operation = result.operation
  if operation == "new" then
    lines[1] = ("Created an empty Arrangement %q."):format(result.name)
  elseif operation == "duplicate" then
    lines[1] = ("Duplicated %q as %q (%d regions)."):format(result.from, result.name, #result.entries)
  elseif operation == "rename" then
    lines[1] = ("Renamed %q to %q."):format(result.from, result.name)
  elseif operation == "delete" then
    lines[1] = ("Deleted %q (%d regions)."):format(result.name, #result.deleted_entries)
    for index, entry in ipairs(result.deleted_entries) do
      local suffix = entry.headroom ~= 0 and (" (headroom %s)"):format(seconds(entry.headroom)) or ""
      lines[#lines + 1] = ("  %2d. %s%s"):format(index, entry.name, suffix)
    end
  end
  lines[#lines + 1] = ("Written to %s"):format(result.path)
  return lines
end

local ERRORS = {
  project_unsaved = "This project has never been saved, so there is nowhere to keep Arrangements.",
  other_project = "A different project is active now. Reload before editing.",
  sidecar_changed = "The Arrangement file changed since it was read. Reload and redo the edit.",
  sidecar_invalid = "The Arrangement file could not be read, so it will not be changed.",
  name_empty = "An Arrangement needs a name.",
  name_taken = "An Arrangement with that name already exists.",
  arrangement_not_found = "There is no Arrangement with that name.",
  region_empty = "A region needs a name.",
  region_repeated = "That region is already in the Arrangement.",
  region_not_in_arrangement = "That region is not in the Arrangement.",
  slot_invalid = "That position is outside the Arrangement.",
  headroom_invalid = "Headroom must be a finite number of seconds.",
  operation_unknown = "Unknown edit.",
  would_be_invalid = "That edit would produce a file that cannot be read, so nothing was written.",
  save_failed = "The Arrangement file could not be written.",
}

--- A refusal, worded.
function text.error(err)
  return ERRORS[err.code] or err.code
end

return text
