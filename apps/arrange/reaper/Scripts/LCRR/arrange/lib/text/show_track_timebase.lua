-- The words for Show Track Timebase, built from
-- lib/core/show_track_timebase.lua's result. Pure: no `reaper.*`.

local text = {}

text.TITLE = "Show Track Timebase"

-- Confirmed empirically in REAPER 7.78/win64; see research/reaper-scripting.md
-- 4.1b. Value 1 is inferred by elimination rather than observed, so it is
-- labelled as such rather than stated flatly.
local TIMEBASE = {
  [-1] = "project default",
  [0] = "time",
  [1] = "beats (position, length, rate)?",
  [2] = "beats (position only)",
}

--- The report, for the console.
function text.render(result)
  local lines = { ("%s -- Lua %s, %d tracks\n"):format(text.TITLE, result.lua_version, #result.tracks) }

  for _, track in ipairs(result.tracks) do
    lines[#lines + 1] = ("%3d  %-24s %3d  %s\n")
      :format(track.track_index + 1, track.name, track.mode, TIMEBASE[track.mode] or "UNKNOWN")
  end

  lines[#lines + 1] = "\nTally:\n"
  -- Ascending by mode value, so the output is stable run to run.
  for _, mode in ipairs({ -1, 0, 1, 2 }) do
    if result.tally[mode] then
      lines[#lines + 1] = ("  %3d  %-32s %d track(s)\n")
        :format(mode, TIMEBASE[mode], result.tally[mode])
    end
  end
  for mode, count in pairs(result.tally) do
    if not TIMEBASE[mode] then
      lines[#lines + 1] = ("  %3d  %-32s %d track(s)\n"):format(mode, "UNKNOWN", count)
    end
  end

  lines[#lines + 1] =
    "\nTrack timebase only. Items can override it; that is not shown here.\n"

  return table.concat(lines)
end

local ERRORS = {
  no_tracks = "This project has no tracks.",
}

function text.error(err)
  return ERRORS[err.code] or err.code
end

return text
