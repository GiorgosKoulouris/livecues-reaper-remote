-- The applier's write half -- the only module that mutates project state for
-- a Repack plan (ADR-0001). Thin by design: it just walks the categories of
-- `lib/regions.lua`'s plan and calls `reaper.*`, kept small enough to verify
-- by eye and by recording the call sequence against a fake (ADR-0001,
-- spec/support/fake_reaper.lua).
--
-- Cutting straddling items, discarding material touching no region, region
-- moves, the tempo/time-signature and envelope-point transplants, the plain
-- markers carried with them, and the item pieces that travel with a moved
-- region, Padding, Tempo Anchors, Automation Anchors and Parked Material are
-- all wired up here -- every category a plan can currently carry. `apply.plan`
-- itself checks none of that: it only ever sees the categories this module
-- applies, by construction, and the refusal if a plan somehow carries more
-- lives in the caller, via lib/validate.lua's `plan_is_region_move_only` (see
-- LCRR_Arrange_Apply.lua). That check passes everything today; it
-- earns its keep the day a new category is added to a plan and not to this
-- module, so a future direct caller of `apply.plan` must still run it first.
--
local apply = {}

local regions = require("lib.regions")

-- Items are identified by track and position in the plan, not by a live
-- object reference (lib/regions.lua's comment on why), so the applier has to
-- re-locate the actual item at apply time. Position is a plain float
-- round-tripped from the same GetMediaItemInfo_Value call the snapshot used,
-- with nothing recomputed in between, so an exact match is expected; the
-- tolerance only guards against float round-trip noise. Also used for
-- envelope points (`find_envelope_point_index`), whose `time` is likewise a
-- directly-stored value rather than one REAPER recomputes.
local POSITION_EPSILON = 1e-6

-- A tempo/time-signature marker's `timepos` is not a directly-stored value
-- the way an item's `D_POSITION` or an envelope point's `time` is -- it is
-- derived from REAPER's own tempo-ramp integration.
--
-- **This tolerance did not fix the failure it was written for, and the
-- diagnosis it originally carried was wrong.** A real run failed to re-locate
-- a marker ("could not find the tempo marker to move at 643.516s"), and this
-- was first blamed on ramp-integration drift. The real cause was the project
-- setting `TEMPOENVLOCKMODE` (Project Settings -> "Timebase for tempo/time
-- signature env" = Beats), under which a tempo marker holds its measure/beat
-- and REAPER *derives* its time -- so writing one marker re-derives the time
-- of every marker after it. Measured from the saved project: the first write
-- slid all 64 downstream markers by exactly 1.121486470s, which is 11,000x
-- this tolerance. Setting that project setting to Time fixed it; no tolerance
-- value could have. See research/reaper-scripting.md §4.4a.
--
-- Kept, at `BOUNDARY_TOLERANCE`'s value, only because a computed `timepos`
-- genuinely can round-trip less exactly than a stored one and this run cannot
-- prove otherwise either way. It is belt-and-braces, not a fix. It is safe at
-- this width: a project with ~69 markers over ~8000s has no two anywhere near
-- 1e-4s apart, so it cannot match the wrong marker.
local TEMPO_POSITION_TOLERANCE = regions.BOUNDARY_TOLERANCE

local function find_item(api, track_index, position)
  local track = api.GetTrack(0, track_index)
  for index = 0, api.CountTrackMediaItems(track) - 1 do
    local item = api.GetTrackMediaItem(track, index)
    if math.abs(api.GetMediaItemInfo_Value(item, "D_POSITION") - position) < POSITION_EPSILON then
      return item
    end
  end
  return nil
end

-- Every item on the track that the given time falls strictly inside. Items on
-- one track may overlap in REAPER, so a cut can land in more than one, and a
-- snapshot of the handles has to be taken before any of them is split -- the
-- track's item list is reindexed by each cut.
local function items_spanning(api, track_index, position)
  local track = api.GetTrack(0, track_index)
  local spanning = {}
  for index = 0, api.CountTrackMediaItems(track) - 1 do
    local item = api.GetTrackMediaItem(track, index)
    local start_time = api.GetMediaItemInfo_Value(item, "D_POSITION")
    local end_time = start_time + api.GetMediaItemInfo_Value(item, "D_LENGTH")
    if position - start_time > POSITION_EPSILON and end_time - position > POSITION_EPSILON then
      spanning[#spanning + 1] = item
    end
  end
  return spanning
end

-- Located by position *and* length, unlike a move. Items may overlap on one
-- track, so two can share a start position; picking the wrong one is
-- recoverable for a move and not for a delete.
local function find_exact_item(api, track_index, position, length)
  local track = api.GetTrack(0, track_index)
  for index = 0, api.CountTrackMediaItems(track) - 1 do
    local item = api.GetTrackMediaItem(track, index)
    if math.abs(api.GetMediaItemInfo_Value(item, "D_POSITION") - position) < POSITION_EPSILON
      and math.abs(api.GetMediaItemInfo_Value(item, "D_LENGTH") - length) < POSITION_EPSILON then
      return track, item
    end
  end
  return track, nil
end

--- Discard every piece the plan drops: material touching no region at all.
-- Runs after the cuts, because most of what it deletes are the tails those
-- cuts create, and before the moves, so nothing is repositioned only to be
-- deleted afterwards.
--
-- This is the one destructive category -- everything else in a plan is a
-- reposition. The undo block and the run log are the safety net (CLAUDE.md);
-- the log records every piece by track, position and length, because once
-- this has run the project no longer does.
-- @param api table the `reaper` table
-- @param drops table plan.drops -- { track_index, track_name, position, length }
function apply.drops(api, drops)
  for _, drop in ipairs(drops) do
    local track, item = find_exact_item(api, drop.track_index, drop.position, drop.length)
    if not item then
      error(("could not find the item to discard on track %d at %.3fs (%.3fs long) -- "
        .. "did the project change after this run started?")
        :format(drop.track_index + 1, drop.position, drop.length), 0)
    end
    api.DeleteTrackMediaItem(track, item)
  end
end

-- Give one edge of one freshly cut piece ADR-0002's `CUT_FADE`.
--
-- `key` is `D_FADEINLEN` or `D_FADEOUTLEN` -- the *manual* fade lengths, in
-- seconds, confirmed primary in research/reaper-scripting.md §4.3a. The
-- `_AUTO` pair `apply.item_moves` writes is a different property, and is left
-- alone here: a cut creates no overlap, so it creates no auto-crossfade. The
-- 0.01s a split preference leaves behind is a manual fade -- `repack_bars`'
-- cut piece carried `FADEIN 1 0.01 0 1 0 0 0`, the manual field set and the
-- auto field zero -- so the manual key is the one that has to be overwritten
-- for the result to stop depending on the preference.
--
-- The piece is re-located by position *and* length, the way apply.drops
-- locates a delete rather than the way a move locates an item. Position
-- alone is not enough and the difference is the whole risk here: a cut
-- position usually has untouched neighbours touching it -- an item that
-- already ended there, or one that already began there -- and ADR-0002
-- requires the original outer fades be preserved, so fading a neighbour is a
-- wrong edit, not a harmless one. Locating by geometry also means this does
-- not depend on which piece SplitMediaItem returns, or on the original
-- handle staying the left-hand piece; neither is settled (§4.3a).
local function fade_cut_edge(api, track_index, position, length, key)
  local _, item = find_exact_item(api, track_index, position, length)
  if not item then
    error(("could not find the cut piece to fade on track %d at %.3fs (%.3fs long) -- "
      .. "did the project change after this run started?")
      :format(track_index + 1, position, length), 0)
  end
  api.SetMediaItemInfo_Value(item, key, regions.CUT_FADE)
end

--- Cut every item that crosses a boundary the plan splits at.
-- Runs before anything moves: `plan.item_moves` names the pieces these cuts
-- create, by the position each piece will have once cut (lib/regions.lua).
--
-- SplitMediaItem's return value is deliberately ignored. Two fetches of the
-- primary reference in the same pass disagreed about what it even returns
-- (research/reaper-scripting.md §4.3a), and REAPER is unreachable from this
-- container, so the ambiguity cannot be settled here. Instead the cut is
-- confirmed the way the rest of this module already identifies items: the
-- right-hand piece has to be findable at the cut position afterwards. That
-- holds under every candidate semantics, so a wrong guess can only produce a
-- clear error, never a wrong edit. Do not "simplify" this to trusting the
-- returned handle until the signature is confirmed in-app.
-- @param api table the `reaper` table
-- @param splits table plan.splits -- { track_index, track_name, position }
function apply.splits(api, splits)
  for _, split in ipairs(splits) do
    local spanning = items_spanning(api, split.track_index, split.position)
    if #spanning == 0 then
      error(("nothing to cut on track %d at %.3fs -- "
        .. "did the project change after this run started?")
        :format(split.track_index + 1, split.position), 0)
    end

    -- The span of each item about to be cut, read before the cut, because
    -- that is what the two resulting pieces are re-located by afterwards.
    local spans = {}
    for index, item in ipairs(spanning) do
      local start_time = api.GetMediaItemInfo_Value(item, "D_POSITION")
      spans[index] = {
        start_time = start_time,
        end_time = start_time + api.GetMediaItemInfo_Value(item, "D_LENGTH"),
      }
    end

    for _, item in ipairs(spanning) do
      api.SplitMediaItem(item, split.position)
    end

    if not find_item(api, split.track_index, split.position) then
      error(("the cut on track %d at %.3fs did not take -- "
        .. "no item begins there afterwards"):format(split.track_index + 1, split.position), 0)
    end

    for _, span in ipairs(spans) do
      fade_cut_edge(api, split.track_index,
        span.start_time, split.position - span.start_time, "D_FADEOUTLEN")
      fade_cut_edge(api, split.track_index,
        split.position, span.end_time - split.position, "D_FADEINLEN")
    end
  end
end

--- Move every region the plan repositioned.
--
-- This is also where Headroom lands, and it needs no code of its own to do so:
-- an adjusted end is just a different `length` on the place the planner already
-- emits (lib/regions.lua's `resolve_headroom`). `plan.headroom` is the record
-- of why the length changed, for the report and the run log, and is
-- deliberately not a category this module routes -- there is nothing left for
-- it to write.
-- @param api table the `reaper` table
-- @param places table plan.places -- { name, number, to_start, length }
function apply.places(api, places)
  for _, place in ipairs(places) do
    api.SetProjectMarker4(0, place.number, true, place.to_start,
      place.to_start + place.length, place.name, 0, 0)
  end
end

-- CountTempoTimeSigMarkers/GetTempoTimeSigMarker exposes no persistent
-- per-marker identity -- unlike a region or a plain marker, which carry a
-- `number` stable across edits (SetProjectMarker4/DeleteProjectMarker key off
-- it), a tempo marker's only handle is `ptidx`, a position-sorted enumeration
-- index that can be invalidated by any edit to the tempo map, including one
-- this same loop just made. So each write re-locates its marker by the
-- original position the plan recorded, immediately before writing it -- the
-- same defensive pattern find_item already uses for items, and for the same
-- reason: research/reaper-scripting.md §4.4 never fetched a confirmed
-- SetTempoTimeSigMarker signature or enumeration-stability guarantee, and
-- REAPER is unreachable from this container to settle it directly.
local function find_tempo_marker_index(api, position)
  for idx = 0, api.CountTempoTimeSigMarkers(0) - 1 do
    local ok, timepos = api.GetTempoTimeSigMarker(0, idx)
    if ok and math.abs(timepos - position) < TEMPO_POSITION_TOLERANCE then
      return idx
    end
  end
  return nil
end

--- Move every tempo/time-signature marker the plan transplanted -- both the
--- ones carried along with a moving region and the ones parked because they
--- belong to no region (lib/regions.lua's `tempo_moves`, issue #4).
--
-- `measurepos`/`beatpos` are passed as `-1`, REAPER's own "derive this from
-- timepos" sentinel for this call (community convention, not independently
-- confirmed -- research/reaper-scripting.md §4.4a) rather than recomputed
-- here. Recomputing them would mean reimplementing REAPER's bar math in Lua,
-- which ADR-0006 already rejected for the planner; the same reasoning holds
-- for the applier. `bpm`, the time signature and `lineartempo` are carried
-- through unchanged -- a transplant moves the tempo slice, it does not
-- redraw it.
--
-- This never touches the master track's "Tempo map" envelope -- the same
-- points in a second view (research §4.4) -- because nothing here calls the
-- envelope-point API at all; only lib/project.lua's reader knows to skip it
-- by name, and this function never reads envelopes in the first place.
-- @param api table the `reaper` table
-- @param tempo_moves table plan.tempo_moves -- { from, to, bpm, timesig_num,
--   timesig_denom, lineartempo }
--
-- **Moves are ordered so that no write ever lands on a position another marker
-- still occupies, and that is not tidiness -- it is the fix for a marker that
-- was silently destroyed against real REAPER.** A tempo map cannot hold two
-- markers at one time, so writing one onto an occupied position collapses the
-- two into one. Measured on `spec/fixtures/repack_bars`, reordering an
-- already-packed project: the plan moved Alpha's marker `0 -> 8` while Bravo's
-- was still at `8`, REAPER merged them, and the next step moved the single
-- survivor `8 -> 22` with Bravo's values. Four markers went in, three came out.
-- Alpha then inherited the tempo of whatever preceded it and its internal bar
-- count changed from 4 bars to 3 -- exactly the failure Tempo Anchors exist to
-- prevent (ADR-0004: "regions of differing tempo each retain their own internal
-- bar count").
--
-- Nothing reported it, either: the loss is invisible to a per-marker check,
-- because every marker the plan asked for *was* found and written. Only the
-- count reveals it, which is why this counts before and after.
--
-- Note why this could not be seen until a second Repack. On a project with gaps
-- every destination lies in a gap being closed, so it is free; the live
-- project's 69/69 successful transplant was that case. Reordering an
-- *already-packed* project makes destinations land exactly where other regions'
-- markers already sit -- and it is the same family of bug as the transient
-- crossfades: moving things one at a time creates intermediate states
-- the plan never describes.
--
-- The ordering is a topological sort done the simple way: repeatedly write any
-- move whose destination is currently free. A genuine cycle (two markers
-- swapping positions) has no such move, so one marker is parked past the end of
-- the map to break it and then written normally. Parking is a transient tempo-map
-- edit, which can reposition beat-based material (issue #10) -- but only
-- transiently, since the map's final state is what the item moves are computed
-- against, and `apply.locate_items` has already resolved every item handle
-- before any tempo write.
function apply.tempo_moves(api, tempo_moves)
  if #tempo_moves == 0 then
    return
  end

  local before_count = api.CountTempoTimeSigMarkers(0)

  local function write(entry, target)
    local idx = find_tempo_marker_index(api, entry.at)
    if not idx then
      error(("could not find the tempo marker to move at %.3fs -- "
        .. "did the project change after this run started?"):format(entry.at), 0)
    end
    local ok = api.SetTempoTimeSigMarker(0, idx, target, -1, -1, entry.move.bpm,
      entry.move.timesig_num, entry.move.timesig_denom, entry.move.lineartempo)
    if ok == false then
      error(("REAPER refused to move the tempo marker at %.3fs to %.3fs"):format(entry.at, target), 0)
    end
    entry.at = target
  end

  -- Somewhere past every marker and every destination, so parking cannot collide
  -- with either.
  local function scratch_position()
    local furthest = 0
    for idx = 0, api.CountTempoTimeSigMarkers(0) - 1 do
      local ok, timepos = api.GetTempoTimeSigMarker(0, idx)
      if ok and timepos > furthest then
        furthest = timepos
      end
    end
    for _, move in ipairs(tempo_moves) do
      if move.to > furthest then
        furthest = move.to
      end
    end
    return furthest + 1000
  end

  local pending = {}
  for _, move in ipairs(tempo_moves) do
    pending[#pending + 1] = { move = move, at = move.from }
  end

  -- Is the marker currently at `position` one this run still has to move? A
  -- blocker that is *not* pending will never move on its own, so waiting for it
  -- is a deadlock rather than a delay.
  local function pending_at(position)
    for _, entry in ipairs(pending) do
      if math.abs(entry.at - position) < TEMPO_POSITION_TOLERANCE then
        return true
      end
    end
    return false
  end

  -- Markers this run deliberately absorbs: see the origin case below. Counted so
  -- the final check can tell a deliberate absorption from an accidental one.
  local absorbed = 0

  -- Each pass writes one move, absorbs one blocker, or parks one marker, and
  -- every move is written once and parked at most once, so this terminates.
  local guard, limit = 0, 3 * #pending + 8
  while #pending > 0 do
    guard = guard + 1
    if guard > limit then
      error(("could not order %d tempo marker move(s) without collisions after %d passes")
        :format(#tempo_moves, limit), 0)
    end

    local wrote = false

    for index, entry in ipairs(pending) do
      local blocker = find_tempo_marker_index(api, entry.move.to)
      -- Free if nothing is there, or if what is there is this very marker.
      if not blocker or math.abs(entry.at - entry.move.to) < TEMPO_POSITION_TOLERANCE then
        write(entry, entry.move.to)
        table.remove(pending, index)
        wrote = true
        break
      end
    end

    -- **The timeline origin always carries a tempo marker, and that is why
    -- waiting is not always enough.** REAPER will not leave 0.0 without one: move
    -- the marker that sits there and a fresh marker appears at 0.0 carrying the
    -- project tempo. So a move *to* 0.0 can be blocked by a marker that is not
    -- going anywhere, and no ordering can free it.
    --
    -- Measured, and this is what a real run failed on: reordering an
    -- already-packed fixture, Charlie's marker had to reach 0.0 while REAPER's
    -- own origin marker held it. The previous version of this loop treated that
    -- as a cycle and parked Charlie repeatedly -- 13 times, ending at 13022s --
    -- before giving up. The saved project showed exactly that: four markers where
    -- they belonged and a stray at 13022.
    --
    -- Overwriting the origin marker is correct rather than merely expedient. Only
    -- one tempo can be in effect at an instant, the map must define one at 0.0,
    -- and the plan says which region starts there -- so the incoming values are
    -- the right ones. The marker being absorbed is REAPER's structural
    -- placeholder, not something the plan meant to keep.
    if not wrote then
      for index, entry in ipairs(pending) do
        if not pending_at(entry.move.to) then
          if math.abs(entry.move.to) < TEMPO_POSITION_TOLERANCE then
            write(entry, entry.move.to)
            table.remove(pending, index)
            absorbed = absorbed + 1
            wrote = true
            break
          end
          -- Anywhere else, a permanent blocker means the plan wants two markers
          -- at one position, which a tempo map cannot represent. Refuse, naming
          -- the position, rather than silently destroying one of them.
          error(("cannot move the tempo marker at %.3fs to %.3fs: another tempo marker "):format(
            entry.at, entry.move.to)
            .. "this run does not move already sits there, and two markers cannot share a position", 0)
        end
      end
    end

    if not wrote then
      -- Every blocked destination is held by a marker that is itself pending: a
      -- genuine cycle. Park one out of the way; its move stays pending and is
      -- written from there on a later pass.
      write(pending[1], scratch_position())
    end
  end

  -- Two checks, because they catch different failures. Every planned destination
  -- must hold a marker -- that catches a merge that swallowed a marker the plan
  -- was still going to place -- and the total must not have dropped by more than
  -- the origin markers deliberately absorbed, which catches a merge that took an
  -- unplanned marker with it.
  for _, move in ipairs(tempo_moves) do
    if not find_tempo_marker_index(api, move.to) then
      error(("the tempo marker planned for %.3fs is not there after the move -- "):format(move.to)
        .. "it was absorbed by another marker at the same position", 0)
    end
  end

  local after_count = api.CountTempoTimeSigMarkers(0)
  if after_count < before_count - absorbed then
    error(("the tempo map lost %d marker(s) while moving %d of them (%d -> %d) -- "):format(
      before_count - absorbed - after_count, #tempo_moves, before_count, after_count)
      .. "two markers cannot share a position, so one was absorbed by another", 0)
  end
end

-- Envelope points have no persistent per-point identity either -- like a
-- tempo marker's ptidx (find_tempo_marker_index above), CountEnvelopePoints/
-- GetEnvelopePoint's ptidx is a position-sorted enumeration index that a
-- previous write in the same run can invalidate, including one to the same
-- envelope. So each write re-locates its point by the original position the
-- plan recorded, immediately before writing it -- the same defensive pattern,
-- for the same reason: research/reaper-scripting.md §4.4b never fetched a
-- confirmed SetEnvelopePoint signature or enumeration-stability guarantee,
-- and REAPER is unreachable from this container to settle it directly.
--
-- The envelope itself is looked up by name via GetTrackEnvelopeByName, the
-- same handle lib/project.lua's reader uses (research §4.4b) -- there is no
-- persistent envelope identity carried through the plan either, only
-- (track, name).
--
-- Writes go through the Ex forms (SetEnvelopePointEx/DeleteEnvelopePointEx),
-- with autoitem_idx hardcoded to -1 -- "the envelope itself, not an
-- automation item" (this suite doesn't read or write automation items at
-- all, research §4.4). This is a confirmed correction, not the original
-- guess: a real run against REAPER 7.78 raised "attempt to call a nil value
-- (field 'DeleteEnvelopePoint')" -- that bare name does not exist. Research
-- §4.4b now records this.
local function describe_envelope_track(track_index)
  return track_index < 0 and "the master track" or ("track %d"):format(track_index + 1)
end

local function find_envelope(api, track_index, envelope_name)
  local track = track_index < 0 and api.GetMasterTrack(0) or api.GetTrack(0, track_index)
  if not track then
    return nil
  end
  return api.GetTrackEnvelopeByName(track, envelope_name)
end

local function find_envelope_point_index(api, envelope, position)
  for idx = 0, api.CountEnvelopePoints(envelope) - 1 do
    local ok, time = api.GetEnvelopePoint(envelope, idx)
    if ok and math.abs(time - position) < POSITION_EPSILON then
      return idx
    end
  end
  return nil
end

--- Take every envelope point the plan moves off the timeline, before the tempo
--- map is touched, and return them ready to be put back by
--- `apply.envelope_moves`.
--
-- **Envelope points follow the tempo map on a beat-timebase track, exactly as
-- items do** (research/reaper-scripting.md §4.1c), and a point's time is
-- therefore no identity once `apply.tempo_moves` has run. This was a real
-- failure, issue 10: on a project whose every track is `BEAT 2`, Payback's
-- 121 bpm marker landed where Deserve's 120 bpm one had been, a point at
-- 275.600s drifted to about 275.583s, and `apply.envelope_moves` stopped the
-- run with "could not find the envelope point to move" -- after the tempo map
-- had been rewritten. Items were fixed by locating their handles first
-- (`apply.locate_items`); a point has no handle (`ptidx` is a sorted index),
-- so the equivalent is to lift it: delete it here, while its recorded time is
-- still right, and insert it at its absolute `to` once the map is final. The
-- plan already carries everything the point holds (value, shape, tension,
-- selected), so nothing is lost by deleting it.
--
-- Each delete re-scans for the first point at `from`, which is the right one
-- even for a step pair: two points at one time are two plan entries, and each
-- takes the first remaining point there. Plan order is read order
-- (`project.sort_by_position`), and the returned list keeps it, so the pair is
-- written back in the order it was read.
-- @param api table the `reaper` table
-- @param envelope_moves table plan.envelope_moves followed by the parked
--   envelope points -- { track_index, envelope_name, from, to, value, shape,
--   tension, selected }
-- @return table the same moves, for `apply.envelope_moves`
function apply.lift_envelope_points(api, envelope_moves)
  for _, move in ipairs(envelope_moves) do
    local envelope = find_envelope(api, move.track_index, move.envelope_name)
    if not envelope then
      error(("could not find envelope %q on %s -- did the project change after this run started?")
        :format(move.envelope_name, describe_envelope_track(move.track_index)), 0)
    end
    local idx = find_envelope_point_index(api, envelope, move.from)
    if not idx then
      error(("could not find the envelope point to move on %s, envelope %q, at %.3fs -- "
        .. "did the project change after this run started?")
        :format(describe_envelope_track(move.track_index), move.envelope_name, move.from), 0)
    end
    api.DeleteEnvelopePointEx(envelope, -1, idx)
  end
  return envelope_moves
end

--- Put back every envelope point `apply.lift_envelope_points` took off, at its
--- planned `to`. Value, shape and tension are carried through unchanged -- a
--- transplant moves the point, it does not redraw the curve -- and `selected`
--- is preserved too, since flipping it would silently change the user's
--- automation-lane selection.
--
-- `to` is an absolute time, so it is right whatever the tempo map now is: a
-- beat-timebase point re-anchors to the beat that sits there (the same
-- argument as `apply.item_moves`). Points are inserted unsorted, in plan order,
-- and each envelope is sorted once at the end -- the documented way to avoid a
-- re-sort per insert, and what keeps a step pair in the order it was read.
-- @param api table the `reaper` table
-- @param envelope_moves table the list `apply.lift_envelope_points` returned
function apply.envelope_moves(api, envelope_moves)
  local touched, order = {}, {}
  for _, move in ipairs(envelope_moves) do
    local envelope = find_envelope(api, move.track_index, move.envelope_name)
    if not envelope then
      error(("could not find envelope %q on %s -- did the project change after this run started?")
        :format(move.envelope_name, describe_envelope_track(move.track_index)), 0)
    end
    api.InsertEnvelopePointEx(envelope, -1, move.to, move.value, move.shape, move.tension,
      move.selected, true)
    if not touched[envelope] then
      touched[envelope] = true
      order[#order + 1] = envelope
    end
  end
  for _, envelope in ipairs(order) do
    api.Envelope_SortPointsEx(envelope, -1)
  end
end

--- Write the Automation Anchors: one point at each bound of every placed
--- region, holding the value that envelope already had there.
--
-- Runs after every envelope point has moved, and takes positions that are
-- already final, so it is unaffected by the move ordering. The values were
-- evaluated against the *original* timeline when the plan was built
-- (lib/regions.lua's `envelope_anchors`), which is the whole point: they
-- capture what each region inherited from its old neighbour before the Repack
-- took that neighbour away.
--
-- `shape` comes from the plan and differs by which bound the anchor sits on
-- (lib/regions.lua's `envelope_anchors`): square at a region end, so nothing
-- interpolates from one song into the next, and the shape already in effect
-- at a region start, so ramps authored inside a region survive. Writing every
-- anchor linear instead is exactly what made a real run ramp across region
-- boundaries. `tension` is zero, which is what square ignores anyway.
--
-- Points are inserted unsorted and the envelope sorted once at the end, which
-- is the documented way to avoid re-sorting on every insert.
--
-- **The plan owns an anchor's time: whatever points exist at that time are
-- deleted first, then the anchors planned for it are written in plan order.**
-- This was a real failure, caught by running the same Repack twice against real
-- REAPER (`spec/fixtures/repack_bars`). The old code inserted unconditionally,
-- so a second run added a *duplicate* point at every region bound rather than
-- rewriting the one already there -- and duplicates are not cosmetic here.
-- Where two points share a time the last one wins (the step-pair rule
-- lib/regions.lua's `envelope_anchors` documents), so re-running turned the
-- points at one bound from `0, 1` into `0, 1, 0` and **silently flipped the
-- value in effect from that bound onward**. Idempotence is not a nicety for this
-- category; without it a repeated Repack quietly rewrites automation, which is
-- the same class of bug as issue #12.
--
-- Deleting per *time* rather than per anchor is what preserves a deliberate step
-- pair: adjacent placed regions share a bound, so one region's end anchor and
-- the next one's start anchor land on the same time, and that two-point step is
-- exactly what a song change wants (ADR-0006's amendment). Replacing "the point
-- at that time" one anchor at a time would have collapsed the pair into a single
-- point -- the second anchor overwriting the first.
--
-- One consequence worth stating, because it is a deliberate loss: a point that
-- some *other* plan category moved onto an anchor's time is deleted too. The
-- anchor's value governs that instant instead. `plan_pack` suppresses the
-- opposite case (a start anchor is not planned where a point already sits, so
-- an authored value is never overwritten by a derived one), and it no longer
-- plans a drop for a point an anchor is about to occupy -- so the remaining
-- overlap is a carried point whose destination happens to be a region bound.
-- @param api table the `reaper` table
-- @param anchors table plan.envelope_anchors -- { track_index, envelope_name,
--   to, value, shape }
function apply.envelope_anchors(api, anchors)
  local touched, order = {}, {}

  -- Group by envelope *and* time, preserving plan order within a group, so a
  -- shared bound's two anchors are written together and in the right order.
  local groups, group_order = {}, {}
  for _, anchor in ipairs(anchors) do
    local key = regions.anchor_group_key(anchor.track_index, anchor.envelope_name, anchor.to)
    if not groups[key] then
      groups[key] = {}
      group_order[#group_order + 1] = key
    end
    local group = groups[key]
    group[#group + 1] = anchor
  end

  for _, key in ipairs(group_order) do
    local group = groups[key]
    local first = group[1]
    local envelope = find_envelope(api, first.track_index, first.envelope_name)
    if not envelope then
      error(("could not find envelope %q on %s -- did the project change after this run started?")
        :format(first.envelope_name, describe_envelope_track(first.track_index)), 0)
    end

    -- Clear the time before writing it. Deleting shifts every later index, so
    -- this re-scans rather than collecting indices up front; a step pair means
    -- there can legitimately be more than one.
    local existing = find_envelope_point_index(api, envelope, first.to)
    while existing do
      api.DeleteEnvelopePointEx(envelope, -1, existing)
      existing = find_envelope_point_index(api, envelope, first.to)
    end

    for _, anchor in ipairs(group) do
      api.InsertEnvelopePointEx(envelope, -1, anchor.to, anchor.value, anchor.shape or 1, 0, false, true)
    end

    if not touched[envelope] then
      touched[envelope] = true
      order[#order + 1] = envelope
    end
  end

  for _, envelope in ipairs(order) do
    api.Envelope_SortPointsEx(envelope, -1)
  end
end

--- Delete every envelope point the plan discarded outright: automation
--- touching no region at all (Dropped Material, CONTEXT.md). Unlike a tempo
--- marker, deleting one carries no risk of repositioning anything else --
--- issue #10's hazard is tempo-specific -- so it follows the same rule as a
--- Loose Item rather than tempo's parked exception (lib/regions.lua's
--- comment on `envelope_drops`).
-- @param api table the `reaper` table
-- @param envelope_drops table plan.envelope_drops -- { track_index,
--   envelope_name, position }
function apply.envelope_drops(api, envelope_drops)
  for _, drop in ipairs(envelope_drops) do
    local envelope = find_envelope(api, drop.track_index, drop.envelope_name)
    if not envelope then
      error(("could not find envelope %q on %s -- did the project change after this run started?")
        :format(drop.envelope_name, describe_envelope_track(drop.track_index)), 0)
    end
    local idx = find_envelope_point_index(api, envelope, drop.position)
    if not idx then
      error(("could not find the envelope point to discard on %s, envelope %q, at %.3fs -- "
        .. "did the project change after this run started?")
        :format(describe_envelope_track(drop.track_index), drop.envelope_name, drop.position), 0)
    end
    api.DeleteEnvelopePointEx(envelope, -1, idx)
  end
end

--- Write the Tempo Anchors of phase 1 (`lib/regions.lua`'s `plan_anchors`,
--- ADR-0004 and ADR-0006).
--
-- **This is phase 1 of a two-phase run, and the order is the whole point.** An
-- anchor starts a new measure at a region's start, which is what puts that start
-- on a bar line -- so until these are written, the tempo oracle cannot answer
-- where the bar lines of phase 2 will be. `LCRR_Arrange_Apply.lua`
-- therefore writes these, re-reads the project, and only then plans the pack.
-- Both phases share one undo block, so this is invisible from REAPER.
--
-- Idempotent by replacement, not by addition, which is what makes a second
-- Repack a no-op rather than a marker pile (ADR-0004 requires an anchor at every
-- region start with no skipping, so the same positions get written every run).
-- `ptidx = -1` inserts a new marker -- confirmed from the primary reference, see
-- research/reaper-scripting.md §4.4a -- so an existing marker at the same
-- position must be located and overwritten instead.
--
-- `measurepos`/`beatpos` are `-1`: "Provide either timepos (with measurepos=-1,
-- beatpos=-1), or measurepos and beatpos (with timepos=-1)", verbatim from the
-- v7.78 reference. That is now a primary-sourced fact rather than the community
-- convention §4.4a originally recorded.
-- @param api table the `reaper` table
-- @param anchors table plan.anchors -- { time, bpm, timesig_num, timesig_denom,
--   lineartempo }
function apply.anchors(api, anchors)
  for _, anchor in ipairs(anchors) do
    -- nil, not an error, when there is no marker here yet: that is the ordinary
    -- case on a project with few tempo markers, and ADR-0004 explicitly accepts
    -- adding markers to projects that had none.
    local idx = find_tempo_marker_index(api, anchor.time) or -1
    local ok = api.SetTempoTimeSigMarker(0, idx, anchor.time, -1, -1, anchor.bpm,
      anchor.timesig_num, anchor.timesig_denom, anchor.lineartempo or false)
    -- Unlike the moves below, this call's failure is not detectable afterwards
    -- by comparing positions -- a refused insert simply leaves the map as it
    -- was, and phase 2 would then plan Padding against a grid that does not
    -- exist. Checking the documented boolean return is the only guard.
    if ok == false then
      error(("REAPER refused to write the Tempo Anchor for region %q at %.3fs"):format(
        anchor.region_name or "?", anchor.time), 0)
    end
  end
end

--- Move every plain marker the plan carried along with its region.
-- @param api table the `reaper` table
-- @param marker_moves table plan.marker_moves -- { name, number, to }
function apply.marker_moves(api, marker_moves)
  for _, move in ipairs(marker_moves) do
    api.SetProjectMarker4(0, move.number, false, move.to, 0, move.name, 0, 0)
  end
end

--- Sort Parked Material into the shapes the existing appliers already take.
--
-- Parking is not a fifth way of moving something (issue #7). A parked region
-- is a region being repositioned, a parked marker is a marker being
-- repositioned, and so on -- the only thing parking adds is *which* offset,
-- and `lib/regions.lua` has already resolved that into a `to` on every entry
-- by the time a plan gets here. So this routes rather than writes: four lists,
-- each in the shape its category's applier already documents, and no new
-- `reaper.*` call anywhere in the parked path.
--
-- Tempo markers are absent by construction -- the planner folds them into
-- `tempo_moves` once `park_delta` is known, so they are never in `parks` to
-- route (`lib/regions.lua`, and ADR-0006's amendment on why tempo parks even
-- when nothing else would).
--
-- Parked regions need no Tempo Anchor written here, which is worth stating
-- because it looks like an omission. `regions.plan_anchors` anchors *every*
-- region in the project, not only the ones an Arrangement places, so phase 1
-- has already put a marker on an omitted region's start. Phase 2 re-reads the
-- project, finds that marker inside no placed region, and parks it by the same
-- offset as the region it belongs to. The anchor therefore travels with its
-- region for free, and a parked region keeps its own tempo instead of
-- inheriting whatever the Packed Block left in effect.
-- @param parks table plan.parks -- entries carrying `kind`, `from`, `to`, `delta`
-- @return table { regions, markers, envelopes, items }, each applier-shaped
function apply.split_parks(parks)
  local sorted = { regions = {}, markers = {}, envelopes = {}, items = {} }
  for _, entry in ipairs(parks or {}) do
    if entry.kind == "region" then
      sorted.regions[#sorted.regions + 1] =
        { name = entry.name, number = entry.number, to_start = entry.to, length = entry.length }
    elseif entry.kind == "marker" then
      sorted.markers[#sorted.markers + 1] = { name = entry.name, number = entry.number, to = entry.to }
    elseif entry.kind == "envelope" then
      sorted.envelopes[#sorted.envelopes + 1] = {
        track_index = entry.track_index,
        envelope_name = entry.envelope_name,
        from = entry.from,
        to = entry.to,
        value = entry.value,
        shape = entry.shape,
        tension = entry.tension,
        selected = entry.selected,
      }
    elseif entry.kind == "item" then
      sorted.items[#sorted.items + 1] =
        { track_index = entry.track_index, from = entry.from, to = entry.to }
    else
      -- A kind nobody routes would be silently left behind, which is exactly
      -- the failure issue #12 was filed about. Refuse instead.
      error(("cannot park %q: lib/apply.lua does not know how to move it")
        :format(tostring(entry.kind)), 0)
    end
  end
  return sorted
end

--- Re-locate every item the plan moves, before anything can disturb it, and
--- return the moves with a live handle attached.
--
-- Split out from `apply.item_moves` because position is only a usable identity
-- for an item *before* the tempo map is rewritten. An item with a beat
-- timebase has its time derived from the tempo map, so `apply.tempo_moves`
-- drags it: confirmed against real REAPER, where all 114 of this project's
-- item-level `BEAT 2` overrides moved (one by 131.6s) while the 216 items
-- without one did not budge, and `find_item` then failed on the very first
-- entry in `plan.item_moves`. See research/reaper-scripting.md §4.1c.
--
-- A `MediaItem*` stays valid as long as the item is not deleted, and nothing
-- between this call and `apply.item_moves` adds or removes an item -- the
-- cuts and drops that do are already finished (`apply.plan`'s order).
-- @param api table the `reaper` table
-- @param item_moves table plan.item_moves -- { track_index, from, to }
-- @return table the same moves, each with an `item` handle
function apply.locate_items(api, item_moves)
  local located = {}
  for index, move in ipairs(item_moves) do
    local item = find_item(api, move.track_index, move.from)
    if not item then
      -- Everything that adds, removes or repositions an item has yet to run,
      -- so this can only mean the project changed since the snapshot was
      -- taken -- a clear message beats a bare "attempt to index a nil value".
      error(("could not find the item to move on track %d at %.3fs -- "
        .. "did the project change after this run started?"):format(move.track_index, move.from), 0)
    end
    located[index] = { item = item, track_index = move.track_index, from = move.from, to = move.to }
  end
  return located
end

--- Move every item the plan carried along with its region, then clear the
--- auto-crossfades REAPER created along the way.
--
-- Takes the output of `apply.locate_items`, not `plan.item_moves` -- by the
-- time this runs the tempo map has been rewritten and a beat-based item is no
-- longer at the position the plan recorded, so it can no longer be found.
-- Writing the planned `to` is still correct: it is an absolute time, and the
-- item re-anchors to whatever beat now sits there.
--
-- **The second pass is not optional, and it is deliberately a second pass.**
-- Items are repositioned one at a time, so an item in transit overlaps items
-- that have not moved yet; REAPER answers a scripted `D_POSITION` write by
-- auto-crossfading that overlap, and the fade length stays behind once the
-- other item moves away. Measured on a real run: items 16s apart left holding
-- a 20.032s crossfade, and one pair on track 21 a 111.503s one, across five
-- tracks -- while the set of genuinely overlapping items was byte-identical
-- before and after. Clearing has to wait until every position is written,
-- because clearing item A's fade does not stop moving item B from giving it
-- a fresh one.
--
-- Clearing *every* moved item's auto-fades, including the few that overlap
-- legitimately, is the user's explicit choice over reconstructing the honest
-- overlap: those are re-created by hand afterwards. This also keeps the
-- result independent of REAPER's auto-crossfade preference, the same reason
-- ADR-0002 gives for never relying on the "move envelope points with media
-- items" preference. `D_FADEINLEN_AUTO`/`D_FADEOUTLEN_AUTO` are the auto-fade
-- lengths (the `.RPP`'s fourth `FADEIN`/`FADEOUT` field); `0` is the value a
-- non-crossfaded item carries there. Manual fades (the third field) are a
-- different pair of properties and are left alone.
-- @param api table the `reaper` table
-- @param located table from apply.locate_items -- { item, track_index, from, to }
function apply.item_moves(api, located)
  for _, move in ipairs(located) do
    api.SetMediaItemInfo_Value(move.item, "D_POSITION", move.to)
  end
  for _, move in ipairs(located) do
    api.SetMediaItemInfo_Value(move.item, "D_FADEINLEN_AUTO", 0)
    api.SetMediaItemInfo_Value(move.item, "D_FADEOUTLEN_AUTO", 0)
  end
end

--- Apply a plan: cut the straddlers, discard what touches no region, then
--- move the regions, transplant the tempo map, and move the markers and
--- items that travel.
--
-- The order is load-bearing. Cuts come first because `plan.drops` and
-- `plan.item_moves` are both expressed in terms of the pieces they create --
-- moving or deleting first would leave the lookups hunting for pieces that do
-- not exist yet. Drops come next so nothing is repositioned only to be
-- deleted -- `envelope_drops` alongside them, since it is the same Dropped
-- Material category, just a different kind of point. Region moves do not
-- disturb items, so item positions stay valid across `apply.places`. Tempo
-- moves run before marker and item moves, deliberately: most of this
-- project's tracks are beat-based (position expressed in QN,
-- research/reaper-scripting.md §4.1b), so an item's effective time can depend
-- on the tempo map even after its own D_POSITION is set. Finishing every
-- tempo-map edit first means later moves are made against the tempo map's
-- final state, not one still partway through being rewritten. Envelope points
-- are the exception that proves it: on a beat-timebase track they follow the
-- tempo map exactly as items do, so they are lifted off the timeline before the
-- first tempo write and inserted at their absolute `to` after the last
-- (`apply.lift_envelope_points`, issue 10).
--
-- That same tempo-map dependency runs the other way too, which is why the item
-- moves are split in half. Writing an item last is right; *finding* it last is
-- not, because the tempo transplant has by then dragged every beat-based item
-- off the position the plan recorded. So the handles are resolved up front --
-- after the cuts and drops that change which items exist, before the first
-- tempo edit -- and only the write waits until the end. This was a real
-- failure against real REAPER, not a hypothetical (`apply.locate_items`).
--
-- Parked Material (issue #7) takes that order as given rather than adding to
-- it: each parked kind joins its own category's list and moves at that
-- category's point in the sequence. Parked items in particular are located in
-- the same up-front pass as carried ones, and for a stronger version of the
-- same reason -- parked items sit furthest out on the timeline, so they are
-- downstream of every tempo edit this run makes and the most exposed of
-- anything here to being dragged off their recorded position.
-- @param api table the `reaper` table
-- @param plan table a plan from lib/regions.lua's plan_pack
function apply.plan(api, plan)
  local parked = apply.split_parks(plan.parks)

  apply.splits(api, plan.splits)
  apply.drops(api, plan.drops)
  apply.envelope_drops(api, plan.envelope_drops)
  local items = apply.locate_items(api, plan.item_moves)
  local parked_items = apply.locate_items(api, parked.items)
  -- Envelope points are lifted before the tempo map is touched and put back
  -- after it, for the reason `apply.lift_envelope_points` gives.
  local lifted = {}
  for _, move in ipairs(plan.envelope_moves) do
    lifted[#lifted + 1] = move
  end
  for _, move in ipairs(parked.envelopes) do
    lifted[#lifted + 1] = move
  end
  apply.lift_envelope_points(api, lifted)
  apply.places(api, plan.places)
  apply.places(api, parked.regions)
  apply.tempo_moves(api, plan.tempo_moves)
  apply.envelope_moves(api, lifted)
  apply.envelope_anchors(api, plan.envelope_anchors or {})
  apply.marker_moves(api, plan.marker_moves)
  apply.marker_moves(api, parked.markers)
  apply.item_moves(api, items)
  apply.item_moves(api, parked_items)
end

return apply
