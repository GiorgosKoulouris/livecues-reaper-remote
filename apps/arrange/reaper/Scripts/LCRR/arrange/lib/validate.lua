-- Precondition checks that every Arrangement-aware script runs before it
-- touches anything.
--
-- Per ADR-0003, Region Names are the primary key an Arrangement uses, an
-- invariant REAPER itself does not impose. These checks are what make that
-- invariant real: a script validates, aborts via ShowMessageBox listing the
-- offenders, and does not open an undo block.
--
-- Pure functions over plain tables -- no `reaper.*` here.

-- The one dependency: membership tolerance is `lib/regions.lua`'s, shared
-- rather than restated, because a check that disagreed with the planner about
-- what counts as float noise would refuse runs the planner considers clean
-- (`BOUNDARY_TOLERANCE`'s own comment there says so).
local planner = require("lib.regions")

local validate = {}

--- Is the project saved to disk?
-- Arrangements and logs both live beside the .RPP, so an unsaved project has
-- nowhere to put them.
-- @return boolean ok, string|nil error message
function validate.project_saved(project_path)
  if type(project_path) ~= "string" or project_path == "" then
    return false, "This project has never been saved. Save it first -- Arrangements "
      .. "and the run log are stored beside the .RPP file."
  end
  return true
end

--- Is the tempo/time-signature envelope on a *time* timebase?
--
-- Project Settings -> "Timebase for tempo/time signature env", stored in the
-- .RPP as `TEMPOENVLOCKMODE` (`1` = Beats, `0` = Time -- read off a real
-- project paired with its Project Settings dialog, so this mapping is
-- primary; secondary sources state it backwards).
--
-- On `Beats`, a tempo marker holds its measure/beat and REAPER *derives* its
-- time, so writing one marker re-derives the time of every marker after it.
-- Measured against real REAPER: one write slid all 64 downstream markers by
-- exactly 1.121486470s, and `apply.tempo_moves` then aborted mid-run unable to
-- re-locate its second marker. There is no applier-side fix -- re-locating by
-- measure/beat would find the right marker but write it to a time that the
-- next write invalidates again, turning a clean crash into a scrambled tempo
-- map. The setting has to be `Time`, so this is a precondition, not a repair.
--
-- Read from the saved .RPP rather than the live project because the setting
-- has no confirmed vanilla ReaScript accessor (research §4.4a: the candidate
-- is `projectconfig_var_getoffs`/`projectconfig_var_addr`, which hand back a
-- pointer Lua cannot obviously write through, and the SWS route is an
-- extension ADR-0001 keeps out of `lib/`). The cost is that an *unsaved*
-- change to this setting reads stale -- which refuses a run that would have
-- worked, never the reverse, and the message says so.
-- @param rpp_text string contents of the project's .RPP, or nil if unreadable
-- @return boolean ok, string|nil error message
function validate.tempo_env_is_time_based(rpp_text)
  if type(rpp_text) ~= "string" then
    return true -- unreadable: not grounds to block a run this check only advises on
  end
  local mode = rpp_text:match("\n%s*TEMPOENVLOCKMODE%s+(%-?%d+)")
  if mode == nil or tonumber(mode) == 0 then
    return true
  end
  return false, "This project's tempo/time-signature envelope is on a Beats timebase, and a "
    .. "Repack cannot move tempo markers reliably while it is.\n\n"
    .. "Every tempo marker holds its bar position and REAPER works out its time from the "
    .. "markers before it, so moving one marker silently moves all the later ones -- a real "
    .. "run drifted by 1.121s and stopped partway through.\n\n"
    .. "Fix: Project Settings -> \"Timebase for tempo/time signature env\" -> Time. "
    .. "Save the project, then run this again.\n\n"
    .. "(This is read from the saved .RPP. If you just changed it, save first.)"
end

-- REAPER's ruler renders a whitespace-only name identically to an empty one,
-- so both are treated as unnamed rather than as a nameable key.
local function is_blank(name)
  return type(name) ~= "string" or name:match("^%s*$") ~= nil
end

--- Check the unique, non-empty Region Name invariant.
-- @param regions table list of { name = string, number = integer }
-- @return boolean ok, table problems
--   Each problem is { code = "duplicate"|"empty", name = string|nil,
--   numbers = { Region Number, ... } }, ordered by name for stable output.
function validate.region_names(regions)
  local by_name, order, unnamed = {}, {}, {}

  for _, region in ipairs(regions) do
    if is_blank(region.name) then
      unnamed[#unnamed + 1] = region.number
    else
      if not by_name[region.name] then
        by_name[region.name] = {}
        order[#order + 1] = region.name
      end
      local numbers = by_name[region.name]
      numbers[#numbers + 1] = region.number
    end
  end

  table.sort(order)

  local problems = {}
  for _, name in ipairs(order) do
    if #by_name[name] > 1 then
      problems[#problems + 1] = {
        code = "duplicate",
        name = name,
        numbers = by_name[name],
      }
    end
  end

  -- Unnamed regions are a single problem, not duplicates of one another:
  -- naming any one of them individually is the fix.
  if #unnamed > 0 then
    problems[#problems + 1] = { code = "empty", numbers = unnamed }
  end

  return #problems == 0, problems
end

--- Does every Region Name an Arrangement mentions exist in the project?
-- @param region_names table ordered list of Region Names from an Arrangement
-- @param regions table list of { name = string }
-- @return boolean ok, table missing names, sorted
function validate.arrangement_regions_exist(region_names, regions)
  local present = {}
  for _, region in ipairs(regions) do
    present[region.name] = true
  end

  local missing, seen = {}, {}
  for _, name in ipairs(region_names) do
    if not present[name] and not seen[name] then
      seen[name] = true
      missing[#missing + 1] = name
    end
  end
  table.sort(missing)

  return #missing == 0, missing
end

--- Does an Arrangement name every region in the project?
-- Parking omitted regions is #7's job and its clamp is not yet ratified,
-- so until then an Arrangement that omits a region is refused
-- rather than silently parked.
-- @param region_names table ordered list of Region Names from an Arrangement
-- @param regions table list of { name = string }
-- @return boolean ok, table omitted Region Names, sorted
function validate.arrangement_is_exhaustive(region_names, regions)
  local named = {}
  for _, name in ipairs(region_names) do
    named[name] = true
  end

  local omitted = {}
  for _, region in ipairs(regions) do
    if not named[region.name] then
      omitted[#omitted + 1] = region.name
    end
  end
  table.sort(omitted)

  return #omitted == 0, omitted
end

--- Is a name one of the Arrangements a sidecar actually has?
-- @param name string the requested Arrangement name
-- @param arrangements table Arrangements keyed by name (lib/sidecar.lua's shape)
-- @return boolean ok, table Arrangement names that do exist, sorted
function validate.arrangement_name_exists(name, arrangements)
  local available = {}
  for known in pairs(arrangements) do
    available[#available + 1] = known
  end
  table.sort(available)

  return arrangements[name] ~= nil, available
end

-- What each plan category needs before it can be applied.
--
-- **This list is empty, and that is the finished state, not an unfinished
-- one.** Every category a plan can carry now has an applier: `parks` was the
-- last, and left with #7 (`apply.split_parks` routes each parked kind into the
-- applier its category already had). The list survives its own contents
-- because it is the registry a *new* category has to be entered in -- adding
-- one to `lib/regions.lua` without either an applier or an entry here is the
-- exact shape of the failure #12 was filed about, and an empty table is a
-- cheaper place to notice that than a deleted function.
--
-- `splits` is deliberately absent: lib/apply.lua cuts straddling items now
-- (#6's core), so a plan carrying splits is applicable rather than blocked.
-- `tempo_moves` is absent for the same reason as of #4's tempo transplant:
-- lib/apply.lua now writes it (`apply.tempo_moves`), so a plan carrying tempo
-- moves is applicable too.
--
-- **`pads` is absent as of #4's Padding, and it left by a different door from
-- the others.** There is no `apply.pads`: a pad changes a region's end, and a
-- region's bounds are written by `apply.places` in one `SetProjectMarker4`
-- carrying both. `lib/regions.lua` therefore emits a place for any region whose
-- *either* bound changed, so a pad on a region that does not move still gets
-- written. `plan.pads` is the record of why an end moved, not a separate
-- instruction -- which means the thing to check when reviewing this list is not
-- "is there an applier function", it is "does some applier function write it".
local PLAN_CATEGORIES = {}

--- Is a plan limited to the slice this suite's applier can run?
-- lib/apply.lua applies every category a plan can carry, so this passes
-- everything today; refusing here means an unexpectedly richer plan is
-- reported rather than silently applied with everything else left behind.
--
-- **This check counts what the planner produced, which is not the same
-- question as what the project contains** -- that gap is issue #12, which
-- once let a real Repack strand the entire tempo map and every automation
-- lane without refusing. #12's own guard, `moving_regions_are_carryable`,
-- asked the project directly rather than counting plan categories; it was
-- removed once both categories it protected -- tempo markers (#4) and
-- envelope points (#8) -- had a working carry, leaving this check as the
-- only gate. That gate is now open for every category. This check still
-- only catches plan categories, and cannot see
-- work the planner never learned to express, which is the reason #12's own
-- guard existed in the first place and why any new category added to a plan
-- needs the same scrutiny before being trusted to this check alone.
-- @param plan table a plan from lib/regions.lua's plan_pack
-- @return boolean ok, string|nil error message
function validate.plan_is_region_move_only(plan)
  local blocking = {}
  for _, category in ipairs(PLAN_CATEGORIES) do
    local count = #plan[category.field]
    if count > 0 then
      blocking[#blocking + 1] = ("  %d %s (needs %s)"):format(count, category.label, category.needs)
    end
  end

  if #blocking == 0 then
    return true
  end

  return false, table.concat({
    "This Arrangement needs work this action cannot do yet:",
    "",
    table.concat(blocking, "\n"),
  }, "\n")
end

--- Did every media item stay where it was while phase 1 wrote its Tempo
--- Anchors? (Issue #19.)
--
-- Writing an anchor edits the tempo map, and beat-attached material follows a
-- tempo-map edit. That is a legitimate thing for a Repack to cause -- what is
-- not legitimate is causing it *silently*, which is what made #19 invisible
-- through several sessions: ADR-0006 has phase 2 re-read the project after the
-- anchors land, so the planner sees the drifted positions as the truth and
-- plans a perfectly self-consistent Repack against them. Everything downstream
-- behaves correctly given its input, and nothing is in a position to notice
-- that the input moved. This is the thing in that position.
--
-- With #19's anchor fix the anchor writes are tempo-neutral on real data, so
-- this should never fire; it is the assertion that the fix held, not a routine
-- part of a run.
--
-- **Pairing is by track, then by snapshot order** -- REAPER's own enumeration
-- within a track. Phase 1 writes only tempo markers, so no item is created,
-- deleted or reordered between the two reads, and a tempo edit maps time
-- monotonically so an item cannot overtake another on its own track.
-- @param before table the snapshot taken before the anchors were written
-- @param after table the snapshot taken after
-- @return boolean ok, table problems
--   Each problem is { code = "item_moved", track_index, track_name, from, to }.
function validate.items_did_not_move(before, after)
  local by_track = {}
  for _, item in ipairs(after.items or {}) do
    local track = by_track[item.track_index]
    if not track then
      track = {}
      by_track[item.track_index] = track
    end
    track[#track + 1] = item
  end

  local seen, problems = {}, {}
  for _, item in ipairs(before.items or {}) do
    local index = (seen[item.track_index] or 0) + 1
    seen[item.track_index] = index

    local moved = (by_track[item.track_index] or {})[index]
    if moved and math.abs(moved.position - item.position) > planner.BOUNDARY_TOLERANCE then
      problems[#problems + 1] = {
        code = "item_moved",
        track_index = item.track_index,
        track_name = item.track_name,
        from = item.position,
        to = moved.position,
      }
    end
  end

  return #problems == 0, problems
end

local function join_numbers(numbers)
  local parts = {}
  for index, number in ipairs(numbers) do
    parts[index] = tostring(number)
  end
  return table.concat(parts, ", ")
end

--- Render problems as a message body for ShowMessageBox.
function validate.format_problems(problems)
  local lines = {}
  for _, problem in ipairs(problems) do
    if problem.code == "duplicate" then
      lines[#lines + 1] = ("  %q is used by %d regions (Region Numbers %s)")
        :format(problem.name, #problem.numbers, join_numbers(problem.numbers))
    elseif problem.code == "empty" then
      lines[#lines + 1] = ("  %d region(s) have no name (Region Numbers %s)")
        :format(#problem.numbers, join_numbers(problem.numbers))
    elseif problem.code == "item_moved" then
      -- Named the way REAPER's UI numbers tracks (from 1), because the reader
      -- is about to go and look at it -- printing the 0-based index sends them
      -- one track off, which has happened for real. The cause is stated on the
      -- line rather than left to a heading: a pair of positions on its own
      -- reads as a Repack move, which is the opposite of what this is.
      local name = (problem.track_name and problem.track_name ~= "")
        and (" %q"):format(problem.track_name) or ""
      lines[#lines + 1] = ("  track %d%s: beat-attached item at %.3f followed the tempo-map edit to %.3f")
        :format(problem.track_index + 1, name, problem.from, problem.to)
    end
  end
  return table.concat(lines, "\n")
end

return validate
