-- The words for Verify: what LCRR_Arrange_Verify shows and logs, built from
-- lib/core/verify.lua's structured results (lib/report.lua's `verify`).
--
-- Pure: no `reaper.*`.

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

--- The dialog shown once the timeline has been verified.
function text.summary(result)
  if result.verdict == "pass" then
    return ("PASS -- the timeline matches %q.\n\nThe named regions are in order and contiguous "
      .. "from the start of the timeline, every packed region start is on a bar line, and every "
      .. "omitted region sits beyond the Packed Block.\n\nNothing has been changed."):format(
      result.name)
  end

  return ("FAIL -- the timeline does not match %q. %d problem(s) found; each one is listed in "
    .. "the console and in the log beside the project.\n\nNothing has been changed."):format(
    result.name, #result.findings)
end

-- Why a verify did not run, worded.
local ERRORS = {
  no_regions = function()
    return "This project has no regions, so there is nothing to verify."
  end,
  sidecar_invalid = function(err)
    return ("The Arrangement sidecar exists but could not be read:\n\n%s"):format(err.error)
  end,
  sidecar_unsaved = function()
    return "This project has never been saved, so it has no Arrangement sidecar to verify against."
  end,
  no_arrangements = function()
    return "This project has no Arrangements to verify against. Capture one first."
  end,
  arrangement_unknown = function(err)
    return ("%q is not a known Arrangement. Available: %s")
      :format(err.name, table.concat(err.available, ", "))
  end,
}

function text.error(err)
  local format_one = ERRORS[err.code]
  return format_one and format_one(err) or err.code
end

return text
