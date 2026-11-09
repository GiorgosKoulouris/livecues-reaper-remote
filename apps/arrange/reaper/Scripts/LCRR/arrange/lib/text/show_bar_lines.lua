-- The words for Show Bar Lines, built from lib/core/show_bar_lines.lua's
-- result. Pure: no `reaper.*`.

local text = {}

text.TITLE = "Show bar lines"

--- The per-region report, for the console.
function text.render(result)
  local out = { ("%s -- %d region(s)\n"):format(text.TITLE, #result.regions) }
  local function line(value)
    out[#out + 1] = value .. "\n"
  end

  line(("tempo at 0.0: %g bpm, %d/%d"):format(result.origin.bpm, result.origin.num,
    result.origin.denom))
  line("")

  for _, row in ipairs(result.regions) do
    line(("%-32.32s %10.5f .. %10.5f  (%.3fs, %g bpm %d/%d)"):format(
      row.name, row.start_time, row.end_time, row.end_time - row.start_time,
      row.bpm, row.num, row.denom))
    line(("    start: nearest bar line at or after = %.5f (%+.6f)%s"):format(
      row.start_bar, row.start_bar - row.start_time,
      row.on_bar and " -- already on a bar line" or " -- a Tempo Anchor will make this one"))
    line(("    end:   next bar line = %.5f -> PAD %+.6f%s"):format(
      row.end_bar, row.pad, row.pads and "  ** would add silence inside the region **" or " (none)"))
  end

  line("")
  line(("%d of %d region(s) would be padded, adding %.6fs of silence in total."):format(
    result.padded, #result.regions, result.total_pad))

  return table.concat(out)
end

--- The dialog shown after the report.
function text.summary(result)
  return ("%d of %d region(s) would be padded, adding %.3fs of silence.\n\n"
    .. "The per-region detail is in the console."):format(
    result.padded, #result.regions, result.total_pad)
end

local ERRORS = {
  no_regions = "This project has no regions.",
}

function text.error(err)
  return ERRORS[err.code] or err.code
end

return text
