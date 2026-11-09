-- @description LCRR Arrange: Apply a named Arrangement
-- @author George Koulouris
-- @version 1.0
-- @about
--   Prompts for an Arrangement name and repacks the project's regions into
--   that order.
--
--   A Repack (issues #4/#5): it moves regions, the plain markers inside them,
--   the tempo/time-signature markers and envelope points inside a moved region
--   or (for tempo markers) belonging to none (issues #4 and #8's transplants),
--   and media items fully contained in a moved region, all by the same delta
--   ADR-0004's packing computes.
--
--   **The run is two phases inside one undo block** (ADR-0006). Phase 1 writes
--   a Tempo Anchor at every region start, which is what puts every region start
--   on a bar line; only then can the tempo oracle say where the bar lines are,
--   so phase 2 plans Padding, placement and everything carried against a grid
--   that now exists. A region whose length is not a whole number of bars has
--   its end extended to the next bar line, which permanently grows it and puts
--   silence inside its bounds -- expected, per ADR-0004.
--
--   **An Arrangement entry may carry Headroom**: an adjustment to that
--   region's end, in seconds, rounded to the nearest bar line. `0` -- the
--   default, and what Capture writes -- means exactly the behaviour above. A
--   shrink may only remove silence: the run refuses rather than let anything
--   inside a region end up past its end. Headroom is **relative, not
--   absolute**, so applying an Arrangement twice moves those ends twice --
--   this action asks for confirmation before it moves any of them, and that
--   prompt is the only guard, since the finished timeline records nothing
--   about it.
--
--   **An Arrangement may name a subset of the project's regions** (#7). The
--   ones it omits become Parked Material: they are moved out beyond the Packed
--   Block, together with everything belonging to them -- their items, markers,
--   envelope points and tempo markers -- by one shared offset the log records,
--   so parking is reversible by negating it. Nothing is deleted for being
--   omitted. What still refuses is an Arrangement naming a region the project
--   does not have, because a misspelled Region Name is an error the user wants
--   caught, while an absent one is an instruction.
--
--   **A Tempo Anchor records the tempo the region actually starts at**, taking
--   it from a tempo marker sitting on that start when there is one and from
--   REAPER's own reading otherwise, so writing the anchors does not change how
--   the project sounds (#19). Should any media item move while they are being
--   written, the run refuses instead of planning against a timeline that
--   shifted underneath it, and names the tracks and positions that moved.
--
--   It refuses rather than applying partially when an item has a timebase this
--   suite cannot confirm safe to reposition (moving an item stretches its
--   content under full beat-attachment -- research/reaper-scripting.md §4.1c),
--   when writing the Tempo Anchors moves beat-attached material, when Padding
--   would run a region into its neighbour, when two regions share a name
--   (ADR-0003), or when the project's tempo envelope is beat-based
--   rather than time-based. A Straddling Item is cut, not refused (#6), and
--   the piece left outside every region is discarded -- the run log is the
--   only record of that, so keep it.

-- The dialog front end. The Repack itself -- both phases, the undo block and
-- the run log -- is lib/core/apply.lua; the wording is lib/text/apply.lua.
local script_dir = ({ reaper.get_action_context() })[2]:match("^(.*)[\\/]")
package.path = script_dir .. "/?.lua;" .. package.path

local apply = require("lib.core.apply")
local text = require("lib.text.apply")

local TITLE = apply.TITLE

local function abort(err)
  reaper.ShowMessageBox(text.error(err), TITLE, 0)
end

local function main()
  local prepared = apply.prepare({ api = reaper })
  if prepared.status == "refused" then
    return abort(prepared.error)
  end

  -- Host-only: importing a sidecar needs a file picker on this machine, so
  -- only this front end offers it.
  if prepared.sidecar_missing then
    local do_import = reaper.ShowMessageBox(text.IMPORT_QUESTION, TITLE, 4) -- 4 = Yes/No
    if do_import ~= 6 then -- 6 = Yes
      return
    end

    local picked_ok, picked = reaper.GetUserFileNameForRead("", text.IMPORT_PICKER_TITLE, "")
    if not picked_ok then
      return
    end

    prepared = apply.import_sidecar(prepared, picked)
    if prepared.status == "refused" then
      return abort(prepared.error)
    end
  end

  -- GetUserInputs's caption argument is itself comma-delimited (one field per
  -- comma), so the name list needs a separator that can't collide with that --
  -- ", " would silently fragment the caption across extra fields once a
  -- sidecar has more than one Arrangement.
  local ok, name = reaper.GetUserInputs(TITLE, 1,
    ("Arrangement name (%s):,extrawidth=200"):format(table.concat(prepared.available, " / ")), "")
  if not ok then
    return
  end

  local request = { name = name }
  local result = apply.run(prepared, request)

  -- **The one confirmation prompt this suite has** (ADR-0007), shown only for
  -- an Arrangement with a non-zero Headroom, before anything is written.
  if result.status == "confirm" then
    local answer = reaper.ShowMessageBox(text.headroom_prompt(result.confirm.headroom), TITLE, 3)
    if answer == 7 then -- 7 = No: repack, treating every Headroom as zero
      request.headroom = "zero"
    elseif answer == 6 then -- 6 = Yes
      request.headroom = "apply"
    else
      -- 2 = Cancel, and so is closing the dialog. Anything that is not an
      -- explicit Yes or No stops the run. Defaulting the other way would make
      -- an unrecognised return value -- a dialog dismissed some way this does
      -- not enumerate -- apply the one operation in the suite that a second
      -- run cannot take back.
      return
    end
    result = apply.run(prepared, request)
  end

  if result.status == "refused" then
    return abort(result.error)
  end

  return reaper.ShowMessageBox(text.summary(result), TITLE, 0)
end

main()
