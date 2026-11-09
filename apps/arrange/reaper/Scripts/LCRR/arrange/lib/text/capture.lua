-- The words for Capture: what LCRR_Arrange_Capture shows, and its run-log
-- entry, built from lib/core/capture.lua's results. Pure: no `reaper.*`.

local validate = require("lib.validate")

local text = {}

text.TITLE = "Capture Region Order"

--- The run-log heading for a capture.
function text.heading(result)
  return ("%s -- %s %q"):format(text.TITLE, result.replaced and "replaced" or "captured", result.name)
end

--- The run log's body for a capture.
function text.log_lines(result)
  local lines = { ("Regions read via %s (issue #11)."):format(result.region_reader) }
  for index, region_name in ipairs(result.regions) do
    lines[#lines + 1] = ("  %2d. %s"):format(index, region_name)
  end
  lines[#lines + 1] = ("Written to %s"):format(result.path)
  return lines
end

--- The question asked before an existing Arrangement is replaced.
function text.replace_question(confirm)
  return ("An Arrangement named %q already exists. Replace it?"):format(confirm.name)
end

--- The question asked before a hand-edited sidecar is rewritten.
function text.rewrite_question()
  return "The Arrangement sidecar has comments or formatting that Capture does not keep. "
    .. "Saving rewrites the whole file. Continue?"
end

--- What a finished capture tells the user.
--
-- The next step is the one nothing else explains. A captured Arrangement is
-- the *starting point*: the usual move is to duplicate it and reorder the
-- copy, so the original stays as a record of how the project was laid out.
-- ADR-0003 makes the sidecar the authoring surface, so duplicating is a text
-- edit and there is no action for it -- which is exactly why it is spelled
-- out here rather than left to be inferred.
function text.summary(result)
  local name = result.name
  return ("%s %q with %d regions.\n\n%s\n\nNext, in a text editor:\n\n"
    .. "  1. Duplicate the [%q] = { ... } block and give the copy a different name.\n"
    .. "  2. Reorder the Region Names inside the copy, or delete some to make a subset.\n"
    .. "  3. Set `headroom` on any entry to add or remove seconds at that region's end. It "
    .. "is rounded to the nearest bar, and it is relative -- applying twice moves twice.\n"
    .. "  4. Run 'Check Arrangement' on the new name, then 'Apply Arrangement', then "
    .. "'Verify Arrangement'.\n\n"
    .. "Editing the copy leaves %q intact as a record of the current order.")
    :format(result.replaced and "Replaced" or "Captured", name, #result.regions, result.path,
      name, name)
end

local ERRORS = {
  project_unsaved = function(err)
    return err.message
  end,
  no_regions = function()
    return "This project has no regions, so there is no order to capture."
  end,
  region_names = function(err)
    return table.concat({
      "Cannot capture an Arrangement until every region has a unique, non-empty name:",
      "",
      validate.format_problems(err.problems),
      "",
      "Run 'Find duplicate or unnamed regions' for the full list.",
    }, "\n")
  end,
  -- Overwriting here would silently discard Arrangements the user hand-wrote.
  sidecar_invalid = function(err)
    return ("The Arrangement sidecar exists but could not be read, so it will not be "
      .. "overwritten:\n\n%s"):format(err.error)
  end,
  name_empty = function()
    return "An Arrangement needs a name."
  end,
  save_failed = function(err)
    return err.error
  end,
}

--- A refusal, worded.
function text.error(err)
  local format_one = ERRORS[err.code]
  return format_one and format_one(err) or err.code
end

return text
