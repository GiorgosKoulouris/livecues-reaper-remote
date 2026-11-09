-- The words for Find Duplicate Region Names, built from
-- lib/core/find_duplicate_region_names.lua's result. Pure: no `reaper.*`.

local validate = require("lib.validate")

local text = {}

text.TITLE = "Find Duplicate Region Names"

--- The run log's body (after its heading).
function text.log_lines(result)
  local lines = { ("Regions read via %s (issue #11)."):format(result.region_reader) }
  if result.verdict == "no_regions" then
    lines[#lines + 1] = "This project has no regions."
  elseif result.verdict == "clean" then
    lines[#lines + 1] = ("All %d region names are unique and non-empty."):format(result.region_count)
    lines[#lines + 1] = "This project is ready for Arrangements."
  else
    lines[#lines + 1] = ("%d problem(s) across %d regions:"):format(#result.problems, result.region_count)
    lines[#lines + 1] = validate.format_problems(result.problems)
    lines[#lines + 1] = "Rename them so every region has a unique, non-empty name."
  end
  return lines
end

--- The dialog shown when problems were found.
function text.problems_message(result)
  return table.concat({
    ("%d problem(s) found across %d regions:"):format(#result.problems, result.region_count),
    "",
    validate.format_problems(result.problems),
    "",
    "Rename them so every region has a unique, non-empty name.",
  }, "\n")
end

return text
