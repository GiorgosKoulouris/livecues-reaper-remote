-- The words for Capture: what LCRR_Arrange_Capture shows, and its run-log
-- entry, built from lib/core/capture.lua's results. Pure: no `reaper.*`.

local refusals = require("lib.text.refusals")

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
  return "The Arrangement file has comments or formatting that Capture does not keep. "
    .. "Saving rewrites the whole file. Continue?"
end

--- What a finished capture tells the user.
--
-- The next step is the one nothing else explains. A captured Arrangement is
-- the *starting point*: the usual move is to duplicate it and reorder the
-- copy, so the original stays as a record of how the project was laid out.
-- Duplicating is done on the Arrange page's Edit tab (ADR-0009); there is no
-- Action for it -- which is exactly why it is named here rather than left to
-- be inferred. This is shown by the script, so it names the Action for the
-- last step, which the page's wording does not need to.
function text.summary(result)
  return ('%s %q with %d regions. Next: duplicate it on the Arrange page\'s Edit tab, '
    .. 'reorder the copy, then run "LCRR Arrange: Check Arrangement".')
    :format(result.replaced and "Replaced" or "Captured", result.name, #result.regions)
end

local FIELD_CHECKS = {
  name_empty = "An Arrangement needs a name.",
}

--- A refusal, worded.
function text.error(err)
  return refusals.error(err) or FIELD_CHECKS[err.code] or err.code
end

return text
