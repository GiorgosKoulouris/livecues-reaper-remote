-- The lasting effects of an Apply, one line each, for Check (what will happen)
-- and Apply (what happened). Pure: no `reaper.*`.
--
-- Only these appear on screen: regions moved because the Arrangement left them
-- out, silence added, Headroom changes, a Headroom too small to act, material
-- discarded, items cut at region edges, and items on an unsafe timebase.
-- Tempo Anchors, automation anchors and move counts are run-log only.
--
-- The page words the same lines in words.js (without the 8-name cap).

local refusals = require("lib.text.refusals")

local effects = {}

local function plural(count, one, many)
  return count == 1 and one or many
end

--- Names inline, capped at refusals.LIMIT.
local function inline(names, extra)
  local shown = {}
  for index = 1, math.min(#names, refusals.LIMIT) do
    shown[index] = names[index]
  end
  local joined = table.concat(shown, ", ")
  if #names > refusals.LIMIT then
    joined = ("%s and %d more (see %s)"):format(joined, #names - refusals.LIMIT, extra or "the run log")
  end
  return joined
end

local function signed(value)
  return ("%+.1f s"):format(value)
end

--- The effect lines.
-- @param what table
--   parked   list of region names moved beyond the Arrangement
--   pads     { count, added }
--   headroom list of { name, resolved }
--   dropped  { items = n, points = n }
--   cuts     number
--   unsafe   list of { track_index, position } (Check only)
-- @param past boolean true after an Apply, false for a Check
-- @param exact boolean|nil whether Padding is exact (Check; nil after Apply)
-- @return table list of lines, in the spec's order
function effects.lines(what, past, exact)
  local lines = {}

  if what.parked and #what.parked > 0 then
    lines[#lines + 1] = ("%s %d left-out %s after the end of the Arrangement: %s"):format(
      past and "Moved" or "Move", #what.parked, plural(#what.parked, "region", "regions"),
      inline(what.parked))
  end

  if what.pads and what.pads.count > 0 then
    if past then
      lines[#lines + 1] = ("Added silence to %d %s (%.1f s)"):format(
        what.pads.count, plural(what.pads.count, "region", "regions"), what.pads.added)
    else
      lines[#lines + 1] = ("Add silence to %d %s so they end on a bar line (%s%.1f s in total)"):format(
        what.pads.count, plural(what.pads.count, "region", "regions"),
        exact == false and "about " or "", what.pads.added)
    end
  end

  local changed, too_small = {}, {}
  for _, entry in ipairs(what.headroom or {}) do
    if entry.resolved == 0 then
      too_small[#too_small + 1] = entry.name
    else
      changed[#changed + 1] = ("%s %s"):format(entry.name, signed(entry.resolved))
    end
  end
  if #changed > 0 then
    lines[#lines + 1] = ("%s the end of %d %s with Headroom: %s"):format(
      past and "Changed" or "Change", #changed, plural(#changed, "region", "regions"), inline(changed))
  end
  if #too_small > 0 then
    lines[#lines + 1] = ("Headroom on %s %s too small to change anything (under half a bar)."):format(
      inline(too_small), past and "was" or "is")
  end

  local dropped = what.dropped or { items = 0, points = 0 }
  if dropped.items + dropped.points > 0 then
    local parts = {}
    if dropped.items > 0 then
      parts[#parts + 1] = ("%d %s"):format(dropped.items, plural(dropped.items, "item", "items"))
    end
    if dropped.points > 0 then
      parts[#parts + 1] = ("%d automation %s"):format(dropped.points, plural(dropped.points, "point", "points"))
    end
    lines[#lines + 1] = ("%s %s that %s in no region"):format(
      past and "Discarded" or "Discard", table.concat(parts, " and "), past and "were" or "are")
  end

  if (what.cuts or 0) > 0 then
    lines[#lines + 1] = ("%s %d %s at region edges"):format(
      "Cut", what.cuts, plural(what.cuts, "item", "items"))
  end

  if what.unsafe and #what.unsafe > 0 then
    local places = {}
    for _, entry in ipairs(what.unsafe) do
      places[#places + 1] = refusals.where(entry)
    end
    lines[#lines + 1] = ("Apply will stop if any of these are inside a moved region: %s. "
      .. "Set those tracks' timebase to Time to avoid this."):format(inline(places))
  end

  return lines
end

--- The effects a Check's findings describe.
function effects.from_findings(findings)
  local what = {}
  for _, entry in ipairs(findings) do
    if entry.code == "parked" then
      what.parked = entry.regions
    elseif entry.code == "padded" then
      what.pads = { count = #entry.pads, added = entry.added }
    elseif entry.code == "headroom" then
      what.headroom = entry.headroom
    elseif entry.code == "dropped" then
      what.dropped = { items = #entry.items, points = #entry.envelope_points }
    elseif entry.code == "cut" then
      what.cuts = #entry.splits
    elseif entry.code == "unsafe_timebase" then
      what.unsafe = entry.items
    end
  end
  return what
end

--- The effects a finished Apply's plan carried out.
function effects.from_plan(plan)
  local what = { headroom = plan.headroom, cuts = #plan.splits, parked = {},
    pads = { count = #plan.pads, added = 0 },
    dropped = { items = #plan.drops, points = #plan.envelope_drops } }
  for _, pad in ipairs(plan.pads) do
    what.pads.added = what.pads.added + pad.added
  end
  for _, park in ipairs(plan.parks) do
    if park.kind == "region" then
      what.parked[#what.parked + 1] = park.name
    end
  end
  return what
end

return effects
