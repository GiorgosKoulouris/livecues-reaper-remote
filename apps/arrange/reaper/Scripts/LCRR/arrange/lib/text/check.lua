-- The words for Check: what LCRR_Arrange_Check shows and logs, built from
-- lib/core/check.lua's structured results (lib/report.lua's `check`).
--
-- Pure: no `reaper.*`. Everything a sentence needs arrives in the result, so
-- the wording lives here and nowhere else -- the bridge (spec step 4) sends the
-- same results as JSON and words them in the page.

local validate = require("lib.validate")

local text = {}

text.TITLE = "Check Arrangement"

local SEVERITY_HEADING = {
  refusal = "WOULD REFUSE",
  permanent = "WOULD HAPPEN, AND RUNNING AGAIN WILL NOT UNDO IT",
  informational = "FOR INFORMATION",
}

-- lib/report.lua's BLIND_SPOTS, worded. The reasoning for the list is there.
local BLIND_SPOTS = {
  padding_grid = "Padding measured against the grid the Tempo Anchors will create. Until they "
    .. "are written, Padding is computed against the grid as it stands now.",
  anchor_drift = "Whether writing the Tempo Anchors moves beat-attached material. That can "
    .. "only be detected after the write, and the run refuses if it happens.",
  padding_overlap = "Whether Padding would run a region into its neighbour once the anchors "
    .. "exist, which follows from the two above.",
}

function text.blind_spot(code)
  return BLIND_SPOTS[code] or code
end

local function lines_of(list, format_one)
  local lines = {}
  for _, entry in ipairs(list) do
    lines[#lines + 1] = format_one(entry)
  end
  return table.concat(lines, "\n")
end

-- One sentence (or paragraph) per finding code.
local FINDINGS = {
  project_unsaved = function(entry)
    return entry.message
  end,

  sidecar_invalid = function(entry)
    return ("The Arrangement sidecar exists but could not be read: %s")
      :format(entry.error or "unknown error")
  end,

  sidecar_missing = function()
    return "This project has no Arrangement sidecar yet. Capture an Arrangement, or import one."
  end,

  tempo_env_beats = function(entry)
    return entry.message
  end,

  region_names = function(entry)
    return "Every region needs a unique, non-empty name before an Arrangement can key on it:\n"
      .. validate.format_problems(entry.problems)
  end,

  arrangement_unknown = function(entry)
    return ("%q is not a known Arrangement. Available: %s")
      :format(entry.name, table.concat(entry.available, ", "))
  end,

  arrangement_missing_regions = function(entry)
    return ("This Arrangement names regions the project does not have:\n  %s")
      :format(table.concat(entry.missing, "\n  "))
  end,

  parked = function(entry)
    return ("%d region(s) this Arrangement omits will be moved beyond the Packed Block as "
      .. "Parked Material. Nothing is deleted, and the run log records the offset that "
      .. "reverses it:\n  %s"):format(#entry.regions, table.concat(entry.regions, "\n  "))
  end,

  unsafe_timebase = function(entry)
    return ("%d item(s) sit on a timebase this suite cannot confirm safe to reposition. A run "
      .. "refuses if any of them is inside a region it moves:\n%s")
      :format(#entry.items, lines_of(entry.items, function(item)
        return ("    track %d %s at %.3f (%.3fs)")
          :format(item.track_index + 1, item.track_name or "", item.position, item.length)
      end))
  end,

  not_planned = function()
    return "The problems above stopped this check before it could plan the Repack, so it has NOT "
      .. "reported Padding, Dropped Material, Straddling Item cuts, or whether the pack "
      .. "itself would refuse. Fix them and run this again."
  end,

  plan_refused = function(entry)
    return entry.error
  end,

  headroom = function(entry)
    return ("%d region(s) will have their end moved by HEADROOM. This is relative, not absolute: "
      .. "applying this Arrangement again moves them again, and Apply asks you to confirm "
      .. "before it does:\n%s"):format(#entry.headroom, lines_of(entry.headroom, function(request)
        return ("    %s: asked %+.3fs, resolves to %+.3fs (%+d bar(s)), "
          .. "end %.3f -> %.3f%s"):format(request.name, request.requested, request.resolved,
          request.bars, request.from_end, request.to_end,
          request.resolved == 0 and " -- NO CHANGE, the request is under half a bar" or "")
      end))
  end,

  padded = function(entry)
    return ("%d region(s) will be PADDED to the next bar line, adding %.3fs of silence inside "
      .. "their bounds -- permanently, and this does not happen again on a later "
      .. "Repack:\n%s"):format(#entry.pads, entry.added, lines_of(entry.pads, function(pad)
        return ("    %s: end %.3f -> %.3f (+%.3fs)")
          :format(pad.name, pad.from_end, pad.to_end, pad.added)
      end))
  end,

  dropped = function(entry)
    local lines = {}
    for _, drop in ipairs(entry.items) do
      lines[#lines + 1] = ("    track %d %s: %.3f..%.3f (%.3fs)")
        :format(drop.track_index + 1, drop.track_name or "", drop.position,
          drop.position + drop.length, drop.length)
    end
    for _, drop in ipairs(entry.envelope_points) do
      lines[#lines + 1] = ("    envelope point, track %d %s, %q: %.3f")
        :format(drop.track_index + 1, drop.track_name or "", drop.envelope_name, drop.position)
    end
    return ("%d piece(s) of material and %d envelope point(s) touch no region and will be "
      .. "DISCARDED. Undo restores them; the run log is the only other record:\n%s")
      :format(#entry.items, #entry.envelope_points, table.concat(lines, "\n"))
  end,

  cut = function(entry)
    return ("%d Straddling Item cut(s) will be made, at region bounds this run moves:\n%s")
      :format(#entry.splits, lines_of(entry.splits, function(split)
        return ("    track %d %s at %.3f")
          :format(split.track_index + 1, split.track_name or "", split.position)
      end))
  end,

  no_change = function()
    return "This Arrangement already matches the timeline. Applying it would change nothing."
  end,

  moves = function(entry)
    local counts = entry.counts
    return ("%d region(s), %d marker(s), %d tempo marker(s), %d envelope point(s) and %d item(s) "
      .. "will move."):format(counts.regions, counts.markers, counts.tempo_markers,
      counts.envelope_points, counts.items)
  end,
}

--- One finding, worded.
function text.finding(entry)
  local format_one = FINDINGS[entry.code]
  return format_one and format_one(entry) or entry.code
end

--- The full report: console and run log.
function text.render(result)
  local out = {}
  local function line(value)
    out[#out + 1] = value .. "\n"
  end

  line(("%s -- %q"):format(text.TITLE, result.arrangement))
  line(("regions read via %s"):format(result.region_reader))
  line("")
  line(result.verdict == "will refuse"
    and "VERDICT: applying this Arrangement WOULD REFUSE. Details below."
    or "VERDICT: applying this Arrangement would proceed.")

  local current
  for _, entry in ipairs(result.findings) do
    if entry.severity ~= current then
      current = entry.severity
      line("")
      line(SEVERITY_HEADING[current])
    end
    line(("  [%s] %s"):format(entry.code, text.finding(entry)))
  end

  -- Padding's accuracy is stated once, next to the blind spots rather than
  -- buried in the Padding finding, because it is the same fact: on a first run
  -- the grid the anchors will create does not exist yet.
  line("")
  line(result.padding_exact
    and "Padding and Headroom above are EXACT: every Tempo Anchor this project needs is already "
      .. "present, so the current bar grid is the one a run would plan against."
    or "Padding and Headroom above are ESTIMATES: this project still needs Tempo Anchors, and "
      .. "they are what put region starts on bar lines. Both are measured against bar lines, so "
      .. "both move with the grid. Run this again after applying to see exact figures.")

  line("")
  line("WHAT THIS CHECK CANNOT SEE")
  for _, code in ipairs(result.blind_spots) do
    line("  - " .. text.blind_spot(code))
  end

  line("")
  line("Nothing has been changed -- this action only reads.")

  return table.concat(out)
end

--- The run log's heading for a check of `name`.
function text.heading(name)
  return ("%s -- %q"):format(text.TITLE, name)
end

--- The dialog shown once the check has run.
function text.summary(result)
  local refusals, permanent = 0, 0
  for _, entry in ipairs(result.findings) do
    if entry.severity == "refusal" then
      refusals = refusals + 1
    elseif entry.severity == "permanent" then
      permanent = permanent + 1
    end
  end

  if refusals > 0 then
    return ("Applying %q WOULD REFUSE -- %d problem(s) found%s.\n\nThe full report is in the "
      .. "console and in the log beside the project. Nothing has been changed."):format(
      result.arrangement, refusals,
      permanent > 0 and (", plus %d permanent effect(s) to be aware of"):format(permanent) or "")
  end

  if permanent > 0 then
    return ("Applying %q would proceed, with %d permanent effect(s) worth reading first "
      .. "(parking, Padding, cuts or discarded material).\n\nThe full report is in the console "
      .. "and in the log beside the project. Nothing has been changed."):format(
      result.arrangement, permanent)
  end

  return ("Applying %q would proceed, with nothing permanent beyond the Repack itself.\n\n"
    .. "The report lists what this check cannot see -- read it before trusting a first run. "
    .. "Nothing has been changed."):format(result.arrangement)
end

-- Why a check could not start, worded.
local ERRORS = {
  no_regions = "This project has no regions, so there is no Arrangement to check.",
}

function text.error(err)
  return ERRORS[err.code] or err.code
end

return text
