-- The words for Verify: what LCRR_Arrange_Verify shows and logs, built from
-- lib/core/verify.lua's structured results (lib/report.lua's `verify`).
--
-- Pure: no `reaper.*`.

local refusals = require("lib.text.refusals")

local text = {}

text.TITLE = "Verify Arrangement"

-- lib/report.lua's VERIFY_BLIND_SPOTS, worded. The reasoning is there.
local BLIND_SPOTS = {
  headroom_count = "Whether a Headroom was applied once or twice. Headroom describes a change "
    .. "to a region's end rather than a target length, so nothing in the finished timeline "
    .. "records how many times it was applied. Apply's confirmation prompt is the only guard "
    .. "against that.",
}

function text.blind_spot(code)
  return BLIND_SPOTS[code] or code
end

local FINDINGS = {
  region_absent = function(entry)
    return ("Arrangement names region %q, which this project does not have.")
      :format(entry.region_name)
  end,
  order_mismatch = function(entry)
    return ("Region %q starts at %.3f, before %q at %.3f, but the Arrangement puts it after.")
      :format(entry.region_name, entry.at, entry.after, entry.after_at)
  end,
  block_start = function(entry)
    return ("The Packed Block starts at %.3f rather than at the beginning of the timeline.")
      :format(entry.at)
  end,
  gap = function(entry)
    return ("Region %q starts %.3fs after %q ends -- the Packed Block is not contiguous.")
      :format(entry.region_name, entry.size, entry.after)
  end,
  overlap = function(entry)
    return ("Region %q starts %.3fs before %q ends.")
      :format(entry.region_name, entry.size, entry.after)
  end,
  off_bar_line = function(entry)
    return ("Region %q starts at %.3f; the nearest bar line at or after it is %.3f.")
      :format(entry.region_name, entry.at, entry.expected)
  end,
  not_parked = function(entry)
    return ("Region %q is not in the Arrangement but starts at %.3f, inside the Packed Block "
      .. "which ends at %.3f."):format(entry.region_name, entry.at, entry.packed_end)
  end,
}

--- One finding, worded.
function text.finding(entry)
  local format_one = FINDINGS[entry.code]
  return format_one and format_one(entry) or entry.code
end

--- The full report: console and run log.
function text.render(result, name)
  local out = {}
  local function line(value)
    out[#out + 1] = value .. "\n"
  end

  line(("%s -- %q"):format(text.TITLE, name))
  line(("regions read via %s"):format(result.region_reader))
  line("")

  if result.verdict == "pass" then
    line("PASS -- the timeline matches this Arrangement:")
    line("  - the named regions are in Arrangement order")
    line("  - the Packed Block is contiguous, from the start of the timeline")
    line("  - every packed region start lands on a bar line")
    line("  - every omitted region sits beyond the Packed Block")
  else
    line(("FAIL -- %d problem(s):"):format(#result.findings))
    for _, entry in ipairs(result.findings) do
      line(("  [%s] %s"):format(entry.code, text.finding(entry)))
    end
  end

  -- Printed on a pass as well as a fail, and deliberately. A pass is the result
  -- most likely to be read as "the run was correct", and the one thing this
  -- cannot confirm is the one thing in a run that a second application would
  -- silently double (lib/report.lua's VERIFY_BLIND_SPOTS).
  line("")
  line("WHAT THIS CHECK CANNOT SEE")
  for _, code in ipairs(result.blind_spots or {}) do
    line("  - " .. text.blind_spot(code))
  end

  line("")
  line("Nothing has been changed -- this action only reads.")

  return table.concat(out)
end

--- The run log's heading for a verify of `name`.
function text.heading(name)
  return ("%s -- %q"):format(text.TITLE, name)
end

-- One plain line per problem, for the dialog. FINDINGS above keeps the times
-- and numbers for the console and the run log.
local LINES = {
  region_absent = function(entry)
    return ("%q is in the Arrangement but not in the project"):format(entry.region_name)
  end,
  order_mismatch = function(entry)
    return ("%q is before %q"):format(entry.region_name, entry.after)
  end,
  block_start = function()
    return "The first region doesn't start at the beginning of the timeline"
  end,
  gap = function(entry)
    return ("There is a gap after %q"):format(entry.after)
  end,
  overlap = function(entry)
    return ("%q overlaps %q"):format(entry.region_name, entry.after)
  end,
  off_bar_line = function(entry)
    return ("%q isn't on a bar line"):format(entry.region_name)
  end,
  not_parked = function(entry)
    return ("%q isn't in the Arrangement but is still among its regions"):format(entry.region_name)
  end,
}

--- One problem as a plain line.
function text.line(entry)
  local one = LINES[entry.code]
  return one and one(entry) or entry.code
end

--- The dialog shown once the timeline has been verified: the result, one line
--- per problem, and the fix.
function text.summary(result)
  if result.verdict == "pass" then
    return ("The timeline matches %q."):format(result.name)
  end

  local lines, missing = {}, false
  for _, entry in ipairs(result.findings) do
    lines[#lines + 1] = text.line(entry)
    missing = missing or entry.code == "region_absent"
  end

  local fix = missing
    and ("Restore the missing regions in REAPER, or remove them from %q on %s, then Apply again.")
      :format(result.name, refusals.EDIT_TAB)
    or ("Apply %q again to fix this."):format(result.name)

  local shown = {}
  for index = 1, math.min(#lines, refusals.LIMIT) do
    shown[index] = "- " .. lines[index]
  end
  if #lines > refusals.LIMIT then
    shown[#shown + 1] = ("and %d more (see the run log)"):format(#lines - refusals.LIMIT)
  end

  return table.concat({
    ("The timeline doesn't match %q."):format(result.name),
    table.concat(shown, "\n"),
    fix,
  }, "\n\n")
end

function text.error(err)
  return refusals.error(err) or err.code
end

return text
