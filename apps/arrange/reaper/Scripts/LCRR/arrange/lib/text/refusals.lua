-- The words for refusals and failures that more than one action can hit: what
-- stopped, then what to do about it. Pure: no `reaper.*`.
--
-- The page words the same codes in www/lcrr/arrange/js/words.js; keep the two in
-- step. The differences are deliberate: here the Edit tab is "the Arrange page's
-- Edit tab", because the reader is looking at REAPER, and long lists are capped
-- at LIMIT names because a message box does not scroll.

local validate = require("lib.validate")

local refusals = {}

refusals.EDIT_TAB = "the Arrange page's Edit tab"
refusals.LIMIT = 8

local NEEDS_UPDATING = "Arrange needs updating. Run the LCRR installer again, then restart REAPER."

--- Seconds to one decimal, as the screen shows them.
function refusals.seconds(value)
  return ("%.1f s"):format(value)
end

--- Names one per line, indented, capped at LIMIT.
-- @param names table list of strings
-- @param extra string|nil where the rest can be read ("the run log" by default)
function refusals.list(names, extra)
  local lines = {}
  for index = 1, math.min(#names, refusals.LIMIT) do
    lines[index] = "  " .. names[index]
  end
  if #names > refusals.LIMIT then
    lines[#lines + 1] = ("  and %d more (see %s)"):format(#names - refusals.LIMIT, extra or "the run log")
  end
  return table.concat(lines, "\n")
end

--- "track 3 at 12.0 s", the way REAPER numbers tracks (from 1).
function refusals.where(entry)
  return ("track %d at %s"):format(entry.track_index + 1, refusals.seconds(entry.position or entry.from))
end

local function wheres(entries)
  local out = {}
  for _, entry in ipairs(entries) do
    out[#out + 1] = refusals.where(entry)
  end
  return out
end

local function region_names_problems(problems)
  local lines = {}
  for line in validate.format_problems(problems):gmatch("[^\n]+") do
    lines[#lines + 1] = (line:gsub("^%s+", ""))
  end
  return lines
end

local PLAN_REASONS = {
  region_overlap = function(err)
    return ("%q ends after %q starts. Separate them in REAPER so there is a gap, then try again.")
      :format(err.region, err.next_region)
  end,
  region_missing = function(err)
    return ("%q is in the Arrangement but not in the project. Restore it in REAPER, or remove it "
      .. "from the Arrangement on %s."):format(err.name, refusals.EDIT_TAB)
  end,
  headroom = function(err)
    local lines = {}
    for _, problem in ipairs(err.problems) do
      if problem.kind == "shrink_too_far" then
        lines[#lines + 1] = ("%q can't shrink by %s. The most it can lose without cutting into its "
          .. "content is %s. Lower its Headroom on %s, then try again.")
          :format(problem.name, refusals.seconds(math.abs(problem.requested)),
            refusals.seconds(problem.most), refusals.EDIT_TAB)
      else
        lines[#lines + 1] = ("The Headroom on %q is too large. Check the value on %s.")
          :format(problem.name, refusals.EDIT_TAB)
      end
    end
    return table.concat(lines, "\n")
  end,
  items_unsafe = function(err)
    return ("Apply can't move some items because their track's timebase isn't Time:\n\n%s\n\n"
      .. "Set those tracks' timebase to Time, then try again."):format(refusals.list(wheres(err.items)))
  end,
  planner_bug = function()
    return "Apply stopped before changing anything because the plan didn't add up. "
      .. "If it happens again, send the run log beside the project."
  end,
}

-- Each takes the refusal's fields and returns the sentence(s). `at_edit_tab`
-- is the Edit tab's name for this surface.
local ERRORS = {
  project_unsaved = function()
    return "This project hasn't been saved. Save it in REAPER, then try again."
  end,
  sidecar_unsaved = function()
    return "This project hasn't been saved. Save it in REAPER, then try again."
  end,
  tempo_env_beats = function()
    return "The project's tempo timebase is set to Beats. In Project Settings, set "
      .. "\"Timebase for tempo/time signature env\" to Time, save the project, and try again."
  end,
  no_regions = function()
    return "This project has no regions. Add some in REAPER, then try again."
  end,
  no_tracks = function()
    return "This project has no tracks."
  end,
  region_names = function(err)
    return "Every region needs its own name:\n\n" .. refusals.list(region_names_problems(err.problems))
      .. "\n\nRename these in REAPER, then try again."
  end,
  sidecar_invalid = function(err)
    return ("The Arrangement file can't be read: %s. Fix it in a text editor, then try again.")
      :format(err.error or "unknown error")
  end,
  sidecar_missing = function()
    return "This project has no Arrangements yet. Capture one, or run \"LCRR Arrange: Apply "
      .. "Arrangement\" in REAPER to import a file."
  end,
  no_arrangements = function()
    return "This project has no Arrangements yet. Capture one first."
  end,
  arrangement_unknown = function(err)
    return ("%q isn't an Arrangement in this project. Choose one of: %s.")
      :format(err.name, table.concat(err.available, ", "))
  end,
  arrangement_empty = function(err)
    return ("%q has no regions. Add some on %s."):format(err.name, refusals.EDIT_TAB)
  end,
  arrangement_missing_regions = function(err)
    return ("%q uses regions this project doesn't have:\n\n%s\n\nRestore them in REAPER, or "
      .. "remove them from %q on %s."):format(err.name, refusals.list(err.missing), err.name,
      refusals.EDIT_TAB)
  end,
  plan_refused = function(err)
    local one = PLAN_REASONS[err.reason]
    return one and one(err) or NEEDS_UPDATING
  end,
  -- Not reachable today: no plan category is blocked (lib/validate.lua's
  -- PLAN_CATEGORIES is empty). Worded in case one is added.
  plan_out_of_scope = function(err)
    return ("Arrange can't apply %q yet. %s"):format(err.name or "", NEEDS_UPDATING)
  end,
  anchors_moved_items = function(err)
    local moved = {}
    for _, item in ipairs(err.moved) do
      moved[#moved + 1] = ("track %d at %s"):format(item.track_index + 1, refusals.seconds(item.from))
    end
    return "Apply stopped because these items moved with the tempo:\n\n" .. refusals.list(moved)
      .. "\n\nPress Ctrl+Z in REAPER, set those tracks' timebase to Time, then try again."
  end,
  import_unreadable = function(err)
    return ("That file can't be imported: %s. Choose a different Arrangement file.")
      :format(err.error or "unknown error")
  end,
  import_invalid = function(err)
    return ("That file can't be imported: %s. Choose a different Arrangement file.")
      :format(err.error or "unknown error")
  end,
  save_failed = function(err)
    return ("The Arrangement file couldn't be saved: %s. Check that the project folder can be "
      .. "written to, then try again."):format(err.error or "unknown error")
  end,
  other_project = function()
    return "A different project is open in REAPER. Press Refresh, then redo the edit. "
      .. "Nothing was changed."
  end,
  sidecar_changed = function()
    return "The Arrangement file changed elsewhere and has been reloaded. Redo the edit. "
      .. "Nothing was changed."
  end,
  would_be_invalid = function()
    return "That edit can't be saved. Reload the page and try again. Nothing was changed."
  end,
  bad_request = function() return NEEDS_UPDATING end,
  unknown_command = function() return NEEDS_UPDATING end,
  operation_unknown = function() return NEEDS_UPDATING end,
  missing_field = function() return NEEDS_UPDATING end,
  request_truncated = function()
    return "That name is too long. Use a shorter one."
  end,
  request_too_long = function()
    return "That name is too long. Use a shorter one."
  end,
  internal = function()
    return "Apply stopped partway. Press Ctrl+Z in REAPER to undo what it did, then try again. "
      .. "If it happens again, send the run log beside the project."
  end,
  no_reply = function()
    return "REAPER didn't answer in time. Apply may still be running. Look at the project in "
      .. "REAPER before trying again."
  end,
}

refusals.ERRORS = ERRORS

--- A refusal, worded. Returns nil for a code this module does not word, so a
--- front end can fall back to its own short checks.
function refusals.error(err)
  local one = ERRORS[err.code]
  if not one then
    return nil
  end
  local message = one(err)
  -- A refusal after the Tempo Anchors were written changed the project, so
  -- it says how to take that back. Moved items already say it.
  if err.anchors_written and err.code ~= "anchors_moved_items" then
    message = message .. "\n\nPress Ctrl+Z in REAPER to remove the changes made so far."
  end
  return message
end

--- What a script shows when an error is raised mid-run: the plain text, never
--- the raw error (the run log has that).
function refusals.failure()
  return ERRORS.internal()
end

return refusals
