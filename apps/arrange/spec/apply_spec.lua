local apply = require("lib.apply")
local regions = require("lib.regions")
local fake_reaper = require("spec.support.fake_reaper")

local function api()
  return fake_reaper.new({ SetProjectMarker4 = true })
end

local function place(name, number, to_start, length)
  return { name = name, number = number, to_start = to_start, length = length }
end

local function marker_move(name, number, to)
  return { name = name, number = number, to = to }
end

local function item_move(track_index, from, to)
  return { track_index = track_index, from = from, to = to }
end

local function tempo_move(from, to, bpm, timesig_num, timesig_denom, lineartempo)
  return { from = from, to = to, bpm = bpm, timesig_num = timesig_num,
    timesig_denom = timesig_denom, lineartempo = lineartempo }
end

-- points: { { position = ..., bpm = ..., timesig_num = ..., timesig_denom = ...,
-- lineartempo = ... }, ... }, mutated in place by SetTempoTimeSigMarker so a
-- spec can assert the marker actually moved, not just that the call happened.
local function tempo_api(points, extra)
  local overrides = {
    CountTempoTimeSigMarkers = function() return #points end,
    GetTempoTimeSigMarker = function(_, idx)
      local point = points[idx + 1]
      if not point then
        return false
      end
      return true, point.position, -1, -1, point.bpm, point.timesig_num, point.timesig_denom,
        point.lineartempo or false
    end,
    SetTempoTimeSigMarker = function(_, idx, timepos, _, _, bpm, timesig_num, timesig_denom, lineartempo)
      local point = points[idx + 1]
      point.position, point.bpm, point.timesig_num, point.timesig_denom, point.lineartempo =
        timepos, bpm, timesig_num, timesig_denom, lineartempo
      return true
    end,
  }
  for name, value in pairs(extra or {}) do
    overrides[name] = value
  end
  return fake_reaper.new(overrides)
end

-- tracks: { [track_index] = { items = { { position = ..., length = ... }, ... } } },
-- using the plan's own track_index as the key so a test can address a
-- specific track directly. `length` defaults to 0, which is enough for the
-- move tests -- only the cut tests care about item spans.
local function item_api(tracks, extra)
  local overrides = {
    SetMediaItemInfo_Value = true,
    GetTrack = function(_, idx) return tracks[idx] end,
    CountTrackMediaItems = function(track) return #track.items end,
    GetTrackMediaItem = function(track, idx) return track.items[idx + 1] end,
    GetMediaItemInfo_Value = function(item, key)
      if key == "D_LENGTH" then
        return item.length or 0
      end
      assert(key == "D_POSITION")
      return item.position
    end,
  }
  for name, value in pairs(extra or {}) do
    overrides[name] = value
  end
  return fake_reaper.new(overrides)
end

local function api_with_items(tracks)
  return item_api(tracks)
end

-- Adds a SplitMediaItem that behaves the way the consensus reading of the
-- API describes (research/reaper-scripting.md §4.3a): the original item
-- becomes the left-hand piece and a new right-hand piece joins the track.
-- The applier is written not to depend on the return value, so this fake
-- returns the right-hand piece only for the spec that proves that.
local function api_with_splitting(tracks, split_impl)
  return item_api(tracks, {
    SplitMediaItem = split_impl or function(item, position)
      for _, track in pairs(tracks) do
        for index, candidate in ipairs(track.items) do
          if candidate == item then
            local right = { position = position, length = (item.position + item.length) - position }
            item.length = position - item.position
            table.insert(track.items, index + 1, right)
            return right
          end
        end
      end
      return nil
    end,
  })
end

-- Every SetMediaItemInfo_Value the applier made, as { item, key, value }
-- triples in call order. The cut-fade specs assert on the *item* each write
-- landed on, not just that a write happened: the whole risk in fading a cut
-- edge is fading the wrong piece (ADR-0002 preserves the original outer
-- fades, and a cut position usually has untouched neighbours touching it).
local function item_writes(fake_api)
  local writes = {}
  for _, call in ipairs(fake_api.calls_to("SetMediaItemInfo_Value")) do
    writes[#writes + 1] = { call.args[1], call.args[2], call.args[3] }
  end
  return writes
end

describe("apply.places", function()
  it("repositions a region by its ID number, keeping name and length", function()
    local fake_api = api()
    apply.places(fake_api, { place("Intro", 4, 10, 20) })

    local calls = fake_api.calls_to("SetProjectMarker4")
    assert.are.equal(1, #calls)
    assert.are.same({ 0, 4, true, 10, 30, "Intro", 0, 0, n = 8 }, calls[1].args)
  end)

  it("moves every place in the list, in order", function()
    local fake_api = api()
    apply.places(fake_api, {
      place("Intro", 1, 0, 5),
      place("Maze", 2, 5, 8),
    })

    assert.are.same({ "SetProjectMarker4", "SetProjectMarker4" }, fake_api.call_names())
    assert.are.equal(1, fake_api.calls_to("SetProjectMarker4")[1].args[2])
    assert.are.equal(2, fake_api.calls_to("SetProjectMarker4")[2].args[2])
  end)

  it("does nothing for an empty list", function()
    local fake_api = api()
    apply.places(fake_api, {})
    assert.are.same({}, fake_api.call_names())
  end)
end)

describe("apply.marker_moves", function()
  it("repositions a plain marker by its ID number, with isrgn false", function()
    local fake_api = api()
    apply.marker_moves(fake_api, { marker_move("Verse cue", 9, 42) })

    local calls = fake_api.calls_to("SetProjectMarker4")
    assert.are.equal(1, #calls)
    assert.are.same({ 0, 9, false, 42, 0, "Verse cue", 0, 0, n = 8 }, calls[1].args)
  end)

  it("does nothing for an empty list", function()
    local fake_api = api()
    apply.marker_moves(fake_api, {})
    assert.are.same({}, fake_api.call_names())
  end)
end)

describe("apply.locate_items", function()
  it("finds the item on its track by its recorded position, and keeps the handle", function()
    local target = { position = 12 }
    local fake_api = api_with_items({ [3] = { items = { { position = 1 }, target } } })

    local located = apply.locate_items(fake_api, { item_move(3, 12, 2) })

    assert.are.equal(1, #located)
    assert.are.equal(target, located[1].item)
    assert.are.equal(2, located[1].to)
    assert.are.same({}, fake_api.calls_to("SetMediaItemInfo_Value"))
  end)

  it("returns an empty list for an empty list", function()
    local fake_api = api_with_items({})
    assert.are.same({}, apply.locate_items(fake_api, {}))
  end)

  -- Only reachable if the project changed between the snapshot and this run
  -- (single-threaded, synchronous REAPER scripts, so not in practice) --
  -- worth a clear error over a bare "attempt to index a nil value".
  it("raises a clear error rather than crashing when the item can't be found", function()
    local fake_api = api_with_items({ [1] = { items = {} } })

    local ok, err = pcall(apply.locate_items, fake_api, { item_move(1, 12, 2) })

    assert.is_false(ok)
    assert.is_truthy(err:find("could not find the item", 1, true))
  end)
end)

describe("apply.item_moves", function()
  it("repositions the located item", function()
    local target = { position = 12 }
    local fake_api = api_with_items({ [3] = { items = { { position = 1 }, target } } })

    apply.item_moves(fake_api, apply.locate_items(fake_api, { item_move(3, 12, 2) }))

    local calls = fake_api.calls_to("SetMediaItemInfo_Value")
    assert.are.equal(target, calls[1].args[1])
    assert.are.same({ target, "D_POSITION", 2, n = 3 }, calls[1].args)
  end)

  it("moves every item move in the list, in order", function()
    local track = { items = { { position = 0 }, { position = 5 } } }
    local fake_api = api_with_items({ [1] = track })

    apply.item_moves(fake_api,
      apply.locate_items(fake_api, { item_move(1, 0, 10), item_move(1, 5, 15) }))

    local positions = {}
    for _, call in ipairs(fake_api.calls_to("SetMediaItemInfo_Value")) do
      if call.args[2] == "D_POSITION" then positions[#positions + 1] = call.args[3] end
    end
    assert.are.same({ 10, 15 }, positions)
  end)

  -- REAPER auto-crossfades the transient overlap each reposition creates, and
  -- the fade length outlives the overlap: a real run left items 16s apart
  -- holding a 20.032s crossfade. Clearing must come after *every* position is
  -- written, since moving one item can re-fade an already-cleared neighbour.
  it("clears both auto-fade lengths on every moved item, after all positions are written", function()
    local track = { items = { { position = 0 }, { position = 5 } } }
    local fake_api = api_with_items({ [1] = track })

    apply.item_moves(fake_api,
      apply.locate_items(fake_api, { item_move(1, 0, 10), item_move(1, 5, 15) }))

    local properties = {}
    for _, call in ipairs(fake_api.calls_to("SetMediaItemInfo_Value")) do
      properties[#properties + 1] = call.args[2] .. "=" .. tostring(call.args[3])
    end
    assert.are.same({
      "D_POSITION=10", "D_POSITION=15",
      "D_FADEINLEN_AUTO=0", "D_FADEOUTLEN_AUTO=0",
      "D_FADEINLEN_AUTO=0", "D_FADEOUTLEN_AUTO=0",
    }, properties)
  end)

  it("does nothing for an empty list", function()
    local fake_api = api_with_items({})
    apply.item_moves(fake_api, {})
    assert.are.same({}, fake_api.call_names())
  end)

  -- The regression that made apply.locate_items a separate step. A beat-based
  -- item's time is derived from the tempo map, so apply.tempo_moves drags it;
  -- looking it up by its planned position afterwards finds nothing. Confirmed
  -- against real REAPER: all 114 item-level `BEAT 2` overrides in the live
  -- project moved (one by 131.6s) while the 216 items without one did not.
  it("still moves an item the tempo transplant dragged off its planned position", function()
    local dragged = { position = 436.039 }
    local fake_api = api_with_items({ [1] = { items = { dragged } } })

    local located = apply.locate_items(fake_api, { item_move(1, 436.039, 2890.088) })
    dragged.position = 368.866 -- what apply.tempo_moves does to a beat-based item

    apply.item_moves(fake_api, located)

    local calls = fake_api.calls_to("SetMediaItemInfo_Value")
    assert.are.equal(dragged, calls[1].args[1])
    assert.are.equal("D_POSITION", calls[1].args[2])
    assert.are.equal(2890.088, calls[1].args[3])
  end)
end)

describe("apply.tempo_moves", function()
  it("finds the tempo marker by its recorded position, and repositions it", function()
    local points = { { position = 10, bpm = 120, timesig_num = 4, timesig_denom = 4 } }
    local fake_api = tempo_api(points)

    apply.tempo_moves(fake_api, { tempo_move(10, 0, 120, 4, 4, false) })

    local calls = fake_api.calls_to("SetTempoTimeSigMarker")
    assert.are.equal(1, #calls)
    assert.are.same({ 0, 0, 0, -1, -1, 120, 4, 4, false, n = 9 }, calls[1].args)
  end)

  -- REAPER's own "derive this from timepos" sentinel for this call (community
  -- convention, research/reaper-scripting.md §4.4a) -- recomputing these here
  -- would mean reimplementing REAPER's bar math in Lua, which ADR-0006 already
  -- rejected for the planner.
  it("passes -1 for measurepos and beatpos, letting REAPER derive them", function()
    local points = { { position = 10, bpm = 120 } }
    local fake_api = tempo_api(points)

    apply.tempo_moves(fake_api, { tempo_move(10, 5, 120, 4, 4, false) })

    local args = fake_api.calls_to("SetTempoTimeSigMarker")[1].args
    assert.are.equal(-1, args[4])
    assert.are.equal(-1, args[5])
  end)

  it("carries bpm, time signature and the ramp flag through unchanged", function()
    local points = { { position = 10, bpm = 90 } }
    local fake_api = tempo_api(points)

    apply.tempo_moves(fake_api, { tempo_move(10, 0, 128, 7, 8, true) })

    local args = fake_api.calls_to("SetTempoTimeSigMarker")[1].args
    assert.are.equal(128, args[6])
    assert.are.equal(7, args[7])
    assert.are.equal(8, args[8])
    assert.is_true(args[9])
  end)

  it("moves every tempo move in the list, in order", function()
    local points = { { position = 10, bpm = 120 }, { position = 20, bpm = 90 } }
    local fake_api = tempo_api(points)

    apply.tempo_moves(fake_api, {
      tempo_move(10, 0, 120, 4, 4, false),
      tempo_move(20, 10, 90, 4, 4, false),
    })

    local calls = fake_api.calls_to("SetTempoTimeSigMarker")
    assert.are.equal(2, #calls)
    assert.are.equal(0, calls[1].args[3])
    assert.are.equal(10, calls[2].args[3])
  end)

  -- CountTempoTimeSigMarkers/GetTempoTimeSigMarker exposes no persistent
  -- per-marker ID, only a position-sorted enumeration index that can be
  -- invalidated by any edit -- including one this same loop just made. If
  -- this move (A, 10 -> 25) is applied by whatever index A happened to hold
  -- *before* the write, a position-sorted enumeration would have B's
  -- ptidx shift underneath the second move once A sorts past it. Each move
  -- must instead be found by its own original position, immediately before
  -- it is written.
  it("re-locates by position rather than a stale index, even under re-sorting", function()
    local points = { { position = 10, bpm = 120, label = "A" }, { position = 20, bpm = 90, label = "B" } }
    local function sorted()
      local copy = {}
      for _, entry in ipairs(points) do
        copy[#copy + 1] = entry
      end
      table.sort(copy, function(a, b) return a.position < b.position end)
      return copy
    end
    local fake_api = fake_reaper.new({
      CountTempoTimeSigMarkers = function() return #points end,
      GetTempoTimeSigMarker = function(_, idx)
        local point = sorted()[idx + 1]
        if not point then
          return false
        end
        return true, point.position, -1, -1, point.bpm, 4, 4, false
      end,
      SetTempoTimeSigMarker = function(_, idx, timepos, _, _, bpm)
        local point = sorted()[idx + 1]
        point.position, point.bpm = timepos, bpm
      end,
    })

    apply.tempo_moves(fake_api, {
      tempo_move(10, 25, 120, 4, 4, false), -- A: 10 -> 25, now sorts after B
      tempo_move(20, 5, 90, 4, 4, false),   -- B: 20 -> 5
    })

    local by_label = {}
    for _, entry in ipairs(points) do
      by_label[entry.label] = entry.position
    end
    assert.are.equal(25, by_label.A)
    assert.are.equal(5, by_label.B)
  end)

  it("does nothing for an empty list", function()
    local fake_api = tempo_api({})
    apply.tempo_moves(fake_api, {})
    assert.are.same({}, fake_api.call_names())
  end)

  it("raises a clear error rather than crashing when the marker can't be found", function()
    local fake_api = tempo_api({})

    local ok, err = pcall(apply.tempo_moves, fake_api, { tempo_move(10, 0, 120, 4, 4, false) })

    assert.is_false(ok)
    assert.is_truthy(err:find("could not find the tempo marker", 1, true))
  end)

  -- Regression: a real run against a project with tempo ramps failed to
  -- re-locate a marker at the tight tolerance used for items/envelope
  -- points, because a tempo marker's timepos is computed by REAPER's ramp
  -- integration rather than stored directly, and a second read did not come
  -- back bit-identical to the snapshot's. This mirrors exactly why
  -- lib/regions.lua's BOUNDARY_TOLERANCE exists for region boundaries.
  it("re-locates a marker whose live timepos drifted slightly from the snapshot's", function()
    local points = { { position = 643.516, bpm = 120, timesig_num = 4, timesig_denom = 4 } }
    local fake_api = tempo_api(points)
    -- The plan recorded 643.516 exactly; the live read comes back a hair off,
    -- within BOUNDARY_TOLERANCE (1e-4) but well outside the old 1e-6.
    points[1].position = 643.5160421

    apply.tempo_moves(fake_api, { tempo_move(643.516, 0, 120, 4, 4, false) })

    assert.are.equal(1, #fake_api.calls_to("SetTempoTimeSigMarker"))
  end)
end)

local function envelope_move(track_index, envelope_name, from, to, value, shape, tension, selected)
  return { track_index = track_index, envelope_name = envelope_name, from = from, to = to,
    value = value, shape = shape, tension = tension, selected = selected }
end

-- envelope_map: { [track_index] = { [envelope_name] = { points = { { time, value,
-- shape, tension, selected }, ... } } } }, using -1 as the master track's key
-- (project.MASTER_TRACK_INDEX's convention), mutated in place by
-- SetEnvelopePointEx/DeleteEnvelopePointEx so a spec can assert the point
-- itself changed, not just that the call happened.
local function envelope_api(envelope_map, extra)
  local overrides = {
    GetTrack = function(_, idx) return envelope_map[idx] end,
    GetMasterTrack = function() return envelope_map[-1] end,
    GetTrackEnvelopeByName = function(track, name) return track.envelopes[name] end,
    CountEnvelopePoints = function(envelope) return #envelope.points end,
    GetEnvelopePoint = function(envelope, idx)
      local point = envelope.points[idx + 1]
      if not point then
        return false
      end
      return true, point.time, point.value, point.shape, point.tension, point.selected
    end,
    -- autoitem_idx (arg 2) is always -1 here -- this suite never reads or
    -- writes automation items, only the envelope itself (research §4.4b).
    SetEnvelopePointEx = function(envelope, _, idx, time, value, shape, tension, selected)
      local point = envelope.points[idx + 1]
      point.time, point.value, point.shape, point.tension, point.selected =
        time, value, shape, tension, selected
      return true
    end,
    DeleteEnvelopePointEx = function(envelope, _, idx)
      table.remove(envelope.points, idx + 1)
      return true
    end,
  }
  for name, value in pairs(extra or {}) do
    overrides[name] = value
  end
  return fake_reaper.new(overrides)
end

describe("apply.envelope_anchors", function()
  local function anchor_api(envelope_map)
    return envelope_api(envelope_map, {
      InsertEnvelopePointEx = function(envelope, _, time, value, shape, tension, selected)
        envelope.points[#envelope.points + 1] =
          { time = time, value = value, shape = shape, tension = tension, selected = selected }
        return true
      end,
      Envelope_SortPointsEx = function(envelope) envelope.sorted = (envelope.sorted or 0) + 1 end,
    })
  end

  -- Shape comes from the plan and differs per bound: square at a region end so
  -- nothing interpolates into the next region, inherited at a region start so
  -- an intentional ramp inside the region survives (lib/regions.lua).
  it("inserts a point at each anchor's final position, with its evaluated value and shape", function()
    local env = { points = {} }
    local fake_api = anchor_api({ [3] = { envelopes = { Volume = env } } })

    apply.envelope_anchors(fake_api, {
      { track_index = 3, envelope_name = "Volume", to = 0, value = 0.3, shape = 0 },
      { track_index = 3, envelope_name = "Volume", to = 6, value = 0.4, shape = 1 },
    })

    assert.are.equal(2, #env.points)
    assert.are.same({ time = 0, value = 0.3, shape = 0, tension = 0, selected = false }, env.points[1])
    assert.are.same({ time = 6, value = 0.4, shape = 1, tension = 0, selected = false }, env.points[2])
  end)

  -- Square, not linear: an anchor with no shape must hold its value forward
  -- rather than ramp to whatever follows.
  it("defaults a shapeless anchor to square", function()
    local env = { points = {} }
    local fake_api = anchor_api({ [3] = { envelopes = { Volume = env } } })

    apply.envelope_anchors(fake_api, { { track_index = 3, envelope_name = "Volume", to = 0, value = 0.3 } })

    assert.are.equal(1, env.points[1].shape)
  end)

  -- Inserted unsorted, then sorted once per envelope rather than once per
  -- point -- the documented way to avoid re-sorting on every insert.
  it("sorts each touched envelope exactly once, after all its inserts", function()
    local env = { points = {} }
    local fake_api = anchor_api({ [3] = { envelopes = { Volume = env } } })

    apply.envelope_anchors(fake_api, {
      { track_index = 3, envelope_name = "Volume", to = 0, value = 0.3 },
      { track_index = 3, envelope_name = "Volume", to = 6, value = 0.4 },
    })

    assert.are.equal(1, env.sorted)
    local names = fake_api.call_names()
    assert.are.equal("Envelope_SortPointsEx", names[#names])
  end)

  it("does nothing for an empty list", function()
    local fake_api = anchor_api({})
    apply.envelope_anchors(fake_api, {})
    assert.are.same({}, fake_api.call_names())
  end)

  it("raises a clear error rather than crashing when the envelope can't be found", function()
    local fake_api = anchor_api({ [1] = { envelopes = {} } })

    local ok, err = pcall(apply.envelope_anchors, fake_api,
      { { track_index = 1, envelope_name = "Volume", to = 0, value = 0 } })

    assert.is_false(ok)
    assert.is_truthy(err:find("could not find envelope", 1, true))
  end)
end)

describe("apply.envelope_moves", function()
  it("finds the envelope point by its recorded position, and repositions it, preserving its shape", function()
    local env = { points = { { time = 12, value = 0.5, shape = 0, tension = 0, selected = false } } }
    local fake_api = envelope_api({ [3] = { envelopes = { Volume = env } } })

    apply.envelope_moves(fake_api, { envelope_move(3, "Volume", 12, 2, 0.75, 1, 0.2, true) })

    assert.are.equal(2, env.points[1].time)
    assert.are.equal(0.75, env.points[1].value)
    assert.are.equal(1, env.points[1].shape)
    assert.are.equal(0.2, env.points[1].tension)
    assert.is_true(env.points[1].selected)
  end)

  -- track_index < 0 is this suite's master-track convention
  -- (project.MASTER_TRACK_INDEX), read via GetMasterTrack rather than GetTrack.
  it("finds the envelope on the master track when track_index is negative", function()
    local env = { points = { { time = 12, value = 0.5, shape = 0, tension = 0, selected = false } } }
    local fake_api = envelope_api({ [-1] = { envelopes = { Volume = env } } })

    apply.envelope_moves(fake_api, { envelope_move(-1, "Volume", 12, 2, 0.5, 0, 0, false) })

    assert.are.equal(2, env.points[1].time)
  end)

  it("moves every envelope move in the list, in order", function()
    local env = { points = {
      { time = 10, value = 0.1, shape = 0, tension = 0, selected = false },
      { time = 20, value = 0.2, shape = 0, tension = 0, selected = false },
    } }
    local fake_api = envelope_api({ [1] = { envelopes = { Volume = env } } })

    apply.envelope_moves(fake_api, {
      envelope_move(1, "Volume", 10, 0, 0.1, 0, 0, false),
      envelope_move(1, "Volume", 20, 5, 0.2, 0, 0, false),
    })

    local by_value = {}
    for _, point in ipairs(env.points) do
      by_value[point.value] = point.time
    end
    assert.are.equal(0, by_value[0.1])
    assert.are.equal(5, by_value[0.2])
  end)

  -- CountEnvelopePoints/GetEnvelopePoint exposes no persistent per-point ID,
  -- only a position-sorted enumeration index that can be invalidated by any
  -- edit -- including one this same loop just made. Mirrors
  -- apply.tempo_moves' equivalent test for the same reason (research
  -- /reaper-scripting.md §4.4b).
  it("re-locates by position rather than a stale index, even under re-sorting", function()
    local points = {
      { time = 12, value = 0.1, shape = 0, tension = 0, selected = false, label = "A" },
      { time = 20, value = 0.2, shape = 0, tension = 0, selected = false, label = "B" },
    }
    local function sorted()
      local copy = {}
      for _, point in ipairs(points) do
        copy[#copy + 1] = point
      end
      table.sort(copy, function(a, b) return a.time < b.time end)
      return copy
    end
    local env = {}
    local fake_api = fake_reaper.new({
      GetTrack = function(_, idx) return ({ [1] = { envelopes = { Volume = env } } })[idx] end,
      GetTrackEnvelopeByName = function(track) return track.envelopes.Volume end,
      CountEnvelopePoints = function() return #points end,
      GetEnvelopePoint = function(_, idx)
        local point = sorted()[idx + 1]
        if not point then
          return false
        end
        return true, point.time, point.value, point.shape, point.tension, point.selected
      end,
      SetEnvelopePointEx = function(_, _, idx, time, value)
        local point = sorted()[idx + 1]
        point.time, point.value = time, value
      end,
    })

    apply.envelope_moves(fake_api, {
      envelope_move(1, "Volume", 12, 25, 0.9, 0, 0, false), -- A: 12 -> 25, now sorts after B
      envelope_move(1, "Volume", 20, 5, 0.8, 0, 0, false),  -- B: 20 -> 5
    })

    local by_label = {}
    for _, point in ipairs(points) do
      by_label[point.label] = point.time
    end
    assert.are.equal(25, by_label.A)
    assert.are.equal(5, by_label.B)
  end)

  it("does nothing for an empty list", function()
    local fake_api = envelope_api({})
    apply.envelope_moves(fake_api, {})
    assert.are.same({}, fake_api.call_names())
  end)

  it("raises a clear error when the envelope cannot be found", function()
    local fake_api = envelope_api({ [1] = { envelopes = {} } })

    local ok, err = pcall(apply.envelope_moves, fake_api, { envelope_move(1, "Volume", 12, 2) })

    assert.is_false(ok)
    assert.is_truthy(err:find("could not find envelope", 1, true))
  end)

  it("raises a clear error when the point cannot be found", function()
    local fake_api = envelope_api({ [1] = { envelopes = { Volume = { points = {} } } } })

    local ok, err = pcall(apply.envelope_moves, fake_api, { envelope_move(1, "Volume", 12, 2) })

    assert.is_false(ok)
    assert.is_truthy(err:find("could not find the envelope point to move", 1, true))
  end)
end)

describe("apply.envelope_drops", function()
  it("deletes the point it names", function()
    local env = { points = { { time = 12, value = 0.5 }, { time = 20, value = 0.6 } } }
    local fake_api = envelope_api({ [1] = { envelopes = { Volume = env } } })

    apply.envelope_drops(fake_api, { { track_index = 1, envelope_name = "Volume", position = 12 } })

    assert.are.equal(1, #env.points)
    assert.are.equal(20, env.points[1].time)
  end)

  it("does nothing for an empty list", function()
    local fake_api = envelope_api({})
    apply.envelope_drops(fake_api, {})
    assert.are.same({}, fake_api.call_names())
  end)

  it("raises a clear error when the point cannot be found, rather than deleting the wrong one", function()
    local env = { points = {} }
    local fake_api = envelope_api({ [1] = { envelopes = { Volume = env } } })

    local ok, err = pcall(apply.envelope_drops, fake_api,
      { { track_index = 1, envelope_name = "Volume", position = 12 } })

    assert.is_false(ok)
    assert.is_truthy(err:find("could not find the envelope point to discard", 1, true))
  end)
end)

describe("apply.splits", function()
  it("cuts the item that spans the position", function()
    local tracks = { [1] = { items = { { position = 10, length = 9 } } } }
    local fake_api = api_with_splitting(tracks)

    apply.splits(fake_api, { { track_index = 1, position = 16 } })

    assert.are.equal(1, #fake_api.calls_to("SplitMediaItem"))
    assert.are.equal(16, fake_api.calls_to("SplitMediaItem")[1].args[2])
    assert.are.same(
      { { position = 10, length = 6 }, { position = 16, length = 3 } }, tracks[1].items)
  end)

  -- Touching is not straddling, the same rule the planner cuts by. The
  -- neighbours here are exactly the shape a previous cut leaves behind.
  it("cuts only the spanning item, not its touching neighbours", function()
    local spanning = { position = 12, length = 8 }
    local tracks = { [1] = { items = {
      { position = 10, length = 6 }, -- ends exactly at 16
      spanning,                      -- 12..20, genuinely spans 16
      { position = 16, length = 4 }, -- starts exactly at 16
    } } }
    local fake_api = api_with_splitting(tracks)

    apply.splits(fake_api, { { track_index = 1, position = 16 } })

    assert.are.equal(1, #fake_api.calls_to("SplitMediaItem"))
    assert.are.equal(spanning, fake_api.calls_to("SplitMediaItem")[1].args[1])
  end)

  -- Items may overlap on one track, so a single cut can land inside more
  -- than one of them. The handles are collected before the first cut,
  -- because each cut reindexes the track's item list.
  it("cuts every overlapping item that spans the position", function()
    local tracks = { [1] = { items = {
      { position = 10, length = 9 },
      { position = 12, length = 8 },
    } } }
    local fake_api = api_with_splitting(tracks)

    apply.splits(fake_api, { { track_index = 1, position = 16 } })

    assert.are.equal(2, #fake_api.calls_to("SplitMediaItem"))
    assert.are.equal(4, #tracks[1].items)
  end)

  it("cuts a chain of positions on one item, left to right", function()
    local tracks = { [1] = { items = { { position = 8, length = 12 } } } }
    local fake_api = api_with_splitting(tracks)

    apply.splits(fake_api, {
      { track_index = 1, position = 10 },
      { track_index = 1, position = 16 },
    })

    assert.are.same({
      { position = 8, length = 2 }, { position = 10, length = 6 }, { position = 16, length = 4 },
    }, tracks[1].items)
  end)

  it("reports a cut position no item spans, rather than silently doing nothing", function()
    local tracks = { [1] = { items = { { position = 10, length = 2 } } } }
    local fake_api = api_with_splitting(tracks)

    local ok, err = pcall(apply.splits, fake_api, { { track_index = 1, position = 16 } })

    assert.is_false(ok)
    assert.is_truthy(err:find("nothing to cut", 1, true))
    assert.is_truthy(err:find("track 2", 1, true)) -- 1-based, as REAPER's UI shows it
  end)

  -- research/reaper-scripting.md §4.3a: sources disagree on what
  -- SplitMediaItem returns, so the applier confirms the cut by re-locating
  -- the right-hand piece instead of trusting the handle. A split that
  -- reports success but does not produce a piece must still be caught.
  it("reports a cut that did not take, whatever SplitMediaItem returned", function()
    local tracks = { [1] = { items = { { position = 10, length = 9 } } } }
    local fake_api = api_with_splitting(tracks, function() return "a truthy handle" end)

    local ok, err = pcall(apply.splits, fake_api, { { track_index = 1, position = 16 } })

    assert.is_false(ok)
    assert.is_truthy(err:find("did not take", 1, true))
  end)

  it("does nothing when the plan has no cuts", function()
    local fake_api = api_with_splitting({})
    apply.splits(fake_api, {})
    assert.are.same({}, fake_api.call_names())
  end)

  -- ADR-0002, issue #15: the two edges a cut creates get this suite's own
  -- CUT_FADE rather than whatever REAPER's split preference happens to be on
  -- the machine running it. Before this, `repack_bars`' cut pieces came back
  -- carrying `FADEIN 1 0.01`, REAPER's default, so the same plan produced
  -- different audio on a differently-configured machine.
  describe("cut fades", function()
    it("fades the new inner edges, and only those", function()
      local tracks = { [1] = { items = { { position = 10, length = 9 } } } }
      local fake_api = api_with_splitting(tracks)

      apply.splits(fake_api, { { track_index = 1, position = 16 } })

      local left, right = tracks[1].items[1], tracks[1].items[2]
      assert.are.same({
        { left, "D_FADEOUTLEN", regions.CUT_FADE },
        { right, "D_FADEINLEN", regions.CUT_FADE },
      }, item_writes(fake_api))
    end)

    -- The left piece's fade-in and the right piece's fade-out are the
    -- original item's outer fades, which ADR-0002 requires be preserved. The
    -- proof is that nothing writes them: the spec above asserts the complete
    -- list of writes, and it is two entries long.
    it("leaves a neighbour that merely touches the cut position alone", function()
      local spanning = { position = 12, length = 8 }
      local ends_there = { position = 10, length = 6 }
      local starts_there = { position = 16, length = 4 }
      local tracks = { [1] = { items = { ends_there, spanning, starts_there } } }
      local fake_api = api_with_splitting(tracks)

      apply.splits(fake_api, { { track_index = 1, position = 16 } })

      for _, write in ipairs(item_writes(fake_api)) do
        assert.are_not.equal(ends_there, write[1])
        assert.are_not.equal(starts_there, write[1])
      end
      assert.are.equal(2, #item_writes(fake_api))
    end)

    it("fades both edges of every overlapping item the cut lands in", function()
      local tracks = { [1] = { items = {
        { position = 10, length = 9 },
        { position = 12, length = 8 },
      } } }
      local fake_api = api_with_splitting(tracks)

      apply.splits(fake_api, { { track_index = 1, position = 16 } })

      local writes = item_writes(fake_api)
      assert.are.equal(4, #writes)
      local faded = {}
      for _, write in ipairs(writes) do
        faded[write[1]] = (faded[write[1]] or 0) + 1
        assert.are.equal(regions.CUT_FADE, write[3])
      end
      for _, item in ipairs(tracks[1].items) do
        assert.are.equal(1, faded[item], "every one of the four pieces gets exactly one edge faded")
      end
    end)

    -- A middle piece is the right-hand half of one cut and the left-hand half
    -- of the next, so it earns both edges -- and the second cut must not undo
    -- the fade the first one wrote.
    it("fades both edges of the middle piece of a chain of cuts", function()
      local tracks = { [1] = { items = { { position = 8, length = 12 } } } }
      local fake_api = api_with_splitting(tracks)

      apply.splits(fake_api, {
        { track_index = 1, position = 10 },
        { track_index = 1, position = 16 },
      })

      local first, middle, last = tracks[1].items[1], tracks[1].items[2], tracks[1].items[3]
      assert.are.same({
        { first, "D_FADEOUTLEN", regions.CUT_FADE },
        { middle, "D_FADEINLEN", regions.CUT_FADE },
        { middle, "D_FADEOUTLEN", regions.CUT_FADE },
        { last, "D_FADEINLEN", regions.CUT_FADE },
      }, item_writes(fake_api))
    end)

    -- The pieces are re-located by position *and* length, the same way
    -- apply.drops locates a delete and for the same reason: writing a fade
    -- onto the wrong item is not recoverable from the plan.
    it("reports a piece it cannot re-locate, rather than fading the wrong item", function()
      local tracks = { [1] = { items = { { position = 10, length = 9 } } } }
      -- Cuts at the right place but leaves the left piece a different length
      -- than the cut position implies, so it cannot be found by geometry.
      local fake_api = api_with_splitting(tracks, function(item, position)
        local right = { position = position, length = (item.position + item.length) - position }
        item.length = (position - item.position) - 1
        table.insert(tracks[1].items, 2, right)
        return right
      end)

      local ok, err = pcall(apply.splits, fake_api, { { track_index = 1, position = 16 } })

      assert.is_false(ok)
      assert.is_truthy(err:find("could not find the cut piece", 1, true))
    end)
  end)
end)

describe("apply.drops", function()
  local function api_with_deleting(tracks)
    return item_api(tracks, {
      DeleteTrackMediaItem = function(track, item)
        for index, candidate in ipairs(track.items) do
          if candidate == item then
            table.remove(track.items, index)
            return true
          end
        end
        return false
      end,
    })
  end

  it("deletes the piece it names", function()
    local keep = { position = 10, length = 6 }
    local tracks = { [1] = { items = { keep, { position = 16, length = 3 } } } }
    local fake_api = api_with_deleting(tracks)

    apply.drops(fake_api, { { track_index = 1, position = 16, length = 3 } })

    assert.are.same({ keep }, tracks[1].items)
  end)

  -- Overlapping items can share a start position. A move picking the wrong
  -- one is recoverable; a delete is not, so drops match on length too.
  it("tells apart two items that share a start position", function()
    local short_one = { position = 16, length = 3 }
    local long_one = { position = 16, length = 40 }
    local tracks = { [1] = { items = { long_one, short_one } } }
    local fake_api = api_with_deleting(tracks)

    apply.drops(fake_api, { { track_index = 1, position = 16, length = 3 } })

    assert.are.same({ long_one }, tracks[1].items)
  end)

  it("reports a piece it cannot find, rather than deleting the wrong one", function()
    local tracks = { [1] = { items = { { position = 16, length = 40 } } } }
    local fake_api = api_with_deleting(tracks)

    local ok, err = pcall(apply.drops, fake_api, { { track_index = 1, position = 16, length = 3 } })

    assert.is_false(ok)
    assert.is_truthy(err:find("could not find the item to discard", 1, true))
    assert.is_truthy(err:find("track 2", 1, true)) -- 1-based, as REAPER's UI shows it
    assert.are.same({}, fake_api.calls_to("DeleteTrackMediaItem"))
  end)

  it("does nothing when the plan drops nothing", function()
    local fake_api = api_with_deleting({})
    apply.drops(fake_api, {})
    assert.are.same({}, fake_api.call_names())
  end)
end)

describe("apply.plan", function()
  it("cuts first, then applies places, tempo moves, marker moves and item moves", function()
    local tracks = { [1] = { items = { { position = 10, length = 9 } } } }
    local tempo_points = { { position = 10, bpm = 120, timesig_num = 4, timesig_denom = 4 } }
    -- Every override the plan needs in one api, so the call order across all
    -- five categories is recorded in a single sequence.
    local fake_api = item_api(tracks, {
      SetProjectMarker4 = true,
      SplitMediaItem = function(item, position)
        local right = { position = position, length = (item.position + item.length) - position }
        item.length = position - item.position
        table.insert(tracks[1].items, 2, right)
        return right
      end,
      DeleteTrackMediaItem = function(track, item)
        for index, candidate in ipairs(track.items) do
          if candidate == item then
            table.remove(track.items, index)
            return true
          end
        end
        return false
      end,
      CountTempoTimeSigMarkers = function() return #tempo_points end,
      GetTempoTimeSigMarker = function(_, idx)
        local point = tempo_points[idx + 1]
        if not point then
          return false
        end
        return true, point.position, -1, -1, point.bpm, point.timesig_num, point.timesig_denom, false
      end,
      -- Actually moves the marker rather than just returning true: apply.tempo_moves
      -- now verifies that every planned destination holds a marker afterwards,
      -- which a stub that lies about the write cannot satisfy.
      SetTempoTimeSigMarker = function(_, idx, timepos)
        tempo_points[idx + 1].position = timepos
        return true
      end,
    })

    apply.plan(fake_api, {
      splits = { { track_index = 1, position = 16 } },
      drops = { { track_index = 1, position = 16, length = 3 } },
      envelope_drops = {},
      places = { place("Intro", 1, 0, 5) },
      tempo_moves = { tempo_move(10, 0, 120, 4, 4, false) },
      envelope_moves = {},
      marker_moves = { marker_move("cue", 9, 2) },
      item_moves = { item_move(1, 10, 0) },
    })

    local mutating = {}
    for _, call in ipairs(fake_api.calls) do
      if call.name == "SplitMediaItem" or call.name == "DeleteTrackMediaItem"
        or call.name == "SetProjectMarker4" or call.name == "SetTempoTimeSigMarker"
        -- The other SetMediaItemInfo_Value writes are fade lengths -- the cut
        -- fades in apply.splits and the auto-fade clears in apply.item_moves,
        -- both second passes over items this sequence already accounts for.
        -- Only the position writes carry ordering meaning.
        or (call.name == "SetMediaItemInfo_Value" and call.args[2] == "D_POSITION") then
        mutating[#mutating + 1] = call.name
      end
    end
    -- Cuts first (drops and item_moves both name the pieces they create),
    -- then drops (nothing is moved only to be deleted), then places, then the
    -- tempo transplant (so beat-based items reposition against the tempo
    -- map's final state, not one still partway through being rewritten),
    -- then the remaining moves.
    assert.are.same({
      "SplitMediaItem", "DeleteTrackMediaItem",
      "SetProjectMarker4", "SetTempoTimeSigMarker", "SetProjectMarker4", "SetMediaItemInfo_Value",
    }, mutating)
    assert.is_true(fake_api.calls_to("SetProjectMarker4")[1].args[3]) -- isrgn true: the region move
    assert.is_false(fake_api.calls_to("SetProjectMarker4")[2].args[3]) -- isrgn false: the marker move
    for _, call in ipairs(fake_api.calls_to("SetMediaItemInfo_Value")) do
      if call.args[2] == "D_POSITION" then
        assert.are.equal(0, call.args[3])
      end
    end
  end)

  -- envelope_drops runs with the other Dropped Material category (before
  -- anything is placed or moved); envelope_moves runs beside the tempo
  -- transplant, the other automation category (lib/apply.lua's apply.plan
  -- comment).
  it("drops envelope points with the other drops, and moves them with the tempo transplant", function()
    local env = { points = { { time = 10, value = 0.5, shape = 0, tension = 0, selected = false } } }
    local drop_env = { points = { { time = 30, value = 0.1, shape = 0, tension = 0, selected = false } } }
    local fake_api = fake_reaper.new({
      GetTrack = function(_, idx) return ({ [1] = { envelopes = { Volume = env, Pan = drop_env } } })[idx] end,
      GetTrackEnvelopeByName = function(track, name) return track.envelopes[name] end,
      CountEnvelopePoints = function(envelope) return #envelope.points end,
      GetEnvelopePoint = function(envelope, idx)
        local point = envelope.points[idx + 1]
        if not point then
          return false
        end
        return true, point.time, point.value, point.shape, point.tension, point.selected
      end,
      SetEnvelopePointEx = function(envelope, _, idx, time, value, shape, tension, selected)
        local point = envelope.points[idx + 1]
        point.time, point.value, point.shape, point.tension, point.selected =
          time, value, shape, tension, selected
      end,
      DeleteEnvelopePointEx = function(envelope, _, idx)
        table.remove(envelope.points, idx + 1)
      end,
    })

    apply.plan(fake_api, {
      splits = {}, drops = {},
      envelope_drops = { { track_index = 1, envelope_name = "Pan", position = 30 } },
      places = {},
      tempo_moves = {},
      envelope_moves = { envelope_move(1, "Volume", 10, 0, 0.5, 0, 0, false) },
      marker_moves = {}, item_moves = {},
    })

    local mutating = {}
    for _, call in ipairs(fake_api.calls) do
      if call.name == "DeleteEnvelopePointEx" or call.name == "SetEnvelopePointEx" then
        mutating[#mutating + 1] = call.name
      end
    end
    assert.are.same({ "DeleteEnvelopePointEx", "SetEnvelopePointEx" }, mutating)
    assert.are.equal(0, env.points[1].time)
  end)

  it("does nothing for a plan with nothing in any applied category", function()
    local fake_api = api()
    apply.plan(fake_api, {
      splits = {}, drops = {}, envelope_drops = {}, places = {}, tempo_moves = {},
      envelope_moves = {}, marker_moves = {}, item_moves = {},
    })
    assert.are.same({}, fake_api.call_names())
  end)
end)

describe("apply.anchors", function()
  -- A tempo map that inserts on ptidx == -1, which is what the primary
  -- reference documents that value to mean (research §4.4a). tempo_api above
  -- cannot be reused: it indexes `points[idx + 1]`, so -1 would write past the
  -- start of the list.
  local function anchor_api(points)
    return fake_reaper.new({
      CountTempoTimeSigMarkers = function() return #points end,
      GetTempoTimeSigMarker = function(_, idx)
        local point = points[idx + 1]
        if not point then
          return false
        end
        return true, point.position, -1, -1, point.bpm, point.timesig_num,
          point.timesig_denom, point.lineartempo or false
      end,
      SetTempoTimeSigMarker = function(_, idx, timepos, _, _, bpm, num, denom, linear)
        local written = { position = timepos, bpm = bpm, timesig_num = num,
          timesig_denom = denom, lineartempo = linear }
        if idx == -1 then
          points[#points + 1] = written
        else
          points[idx + 1] = written
        end
        return true
      end,
    })
  end

  local function anchor(time, bpm, num, denom, linear)
    return { time = time, region_name = "R", bpm = bpm, timesig_num = num,
      timesig_denom = denom, lineartempo = linear }
  end

  it("inserts a marker where the project has none, with ptidx -1", function()
    local points = {}
    local fake_api = anchor_api(points)

    apply.anchors(fake_api, { anchor(12, 120, 4, 4, false) })

    local calls = fake_api.calls_to("SetTempoTimeSigMarker")
    assert.are.equal(1, #calls)
    assert.are.equal(-1, calls[1].args[2])
    assert.are.equal(12, points[1].position)
    assert.are.equal(120, points[1].bpm)
  end)

  -- Idempotence, and ADR-0004's reason for planning an anchor at *every* region
  -- start with no skipping: a second Repack must rewrite the same markers, not
  -- stack a new one on each run.
  it("overwrites an existing marker at the same position instead of adding one", function()
    local points = { { position = 12, bpm = 90, timesig_num = 3, timesig_denom = 4 } }
    local fake_api = anchor_api(points)

    apply.anchors(fake_api, { anchor(12, 120, 4, 4, false) })

    assert.are.equal(0, fake_api.calls_to("SetTempoTimeSigMarker")[1].args[2])
    assert.are.equal(1, #points)
    assert.are.equal(120, points[1].bpm)
    assert.are.equal(4, points[1].timesig_num)
  end)

  it("matches an existing marker within BOUNDARY_TOLERANCE, not exactly", function()
    local points = { { position = 12 + 1e-5, bpm = 90 } }
    local fake_api = anchor_api(points)

    apply.anchors(fake_api, { anchor(12, 120, 4, 4, false) })

    assert.are.equal(0, fake_api.calls_to("SetTempoTimeSigMarker")[1].args[2])
    assert.are.equal(1, #points)
  end)

  it("passes -1 for measurepos and beatpos, letting REAPER derive them", function()
    local fake_api = anchor_api({})

    apply.anchors(fake_api, { anchor(12, 120, 4, 4, false) })

    local args = fake_api.calls_to("SetTempoTimeSigMarker")[1].args
    assert.are.equal(-1, args[4])
    assert.are.equal(-1, args[5])
  end)

  it("carries the ramp flag the plan decided", function()
    local fake_api = anchor_api({})

    apply.anchors(fake_api, { anchor(12, 120, 4, 4, true) })

    assert.is_true(fake_api.calls_to("SetTempoTimeSigMarker")[1].args[9])
  end)

  -- A refused insert leaves the tempo map as it was, and phase 2 would then
  -- plan Padding against a bar grid that does not exist. The documented boolean
  -- return is the only way to notice.
  it("raises when REAPER refuses the write", function()
    local fake_api = fake_reaper.new({
      CountTempoTimeSigMarkers = function() return 0 end,
      SetTempoTimeSigMarker = function() return false end,
    })

    local ok, err = pcall(apply.anchors, fake_api, { anchor(12, 120, 4, 4, false) })

    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("refused", 1, true))
  end)

  it("writes every anchor in the list", function()
    local points = {}
    local fake_api = anchor_api(points)

    apply.anchors(fake_api, {
      anchor(0, 120, 4, 4, false),
      anchor(12, 90, 3, 4, false),
      anchor(30, 140, 7, 8, false),
    })

    assert.are.equal(3, #fake_api.calls_to("SetTempoTimeSigMarker"))
    assert.are.equal(3, #points)
  end)
end)

-- The bug a second real run found: anchors were inserted unconditionally, so
-- re-running the same Repack added a duplicate point at every region bound
-- instead of rewriting the one already there. Because the last point at a time
-- wins, `0, 1` became `0, 1, 0` and the value in effect from that bound silently
-- flipped. These specs are what should have caught it.
describe("apply.envelope_anchors idempotence", function()
  local function anchor_api(envelope_map)
    return envelope_api(envelope_map, {
      InsertEnvelopePointEx = function(envelope, _, time, value, shape, tension, selected)
        envelope.points[#envelope.points + 1] =
          { time = time, value = value, shape = shape, tension = tension, selected = selected }
        return true
      end,
      Envelope_SortPointsEx = function(envelope)
        table.sort(envelope.points, function(a, b) return a.time < b.time end)
        envelope.sorted = (envelope.sorted or 0) + 1
      end,
    })
  end

  local function anchor(to, value)
    return { track_index = 3, envelope_name = "Volume", to = to, value = value, shape = 1 }
  end

  local function times_and_values(env)
    local out = {}
    for _, point in ipairs(env.points) do
      out[#out + 1] = ("%g=%g"):format(point.time, point.value)
    end
    return out
  end

  it("replaces a point already sitting at the anchor's position", function()
    local env = { points = { { time = 6, value = 0.9, shape = 1, tension = 0, selected = false } } }
    local fake_api = anchor_api({ [3] = { envelopes = { Volume = env } } })

    apply.envelope_anchors(fake_api, { anchor(6, 0.4) })

    assert.are.same({ "6=0.4" }, times_and_values(env))
  end)

  it("leaves the same result when run twice", function()
    local env = { points = {} }
    local fake_api = anchor_api({ [3] = { envelopes = { Volume = env } } })
    local anchors = { anchor(0, 0.3), anchor(6, 0.4) }

    apply.envelope_anchors(fake_api, anchors)
    local after_first = times_and_values(env)
    apply.envelope_anchors(fake_api, anchors)

    assert.are.same(after_first, times_and_values(env))
  end)

  -- Adjacent placed regions share a bound, so one region's end anchor and the
  -- next one's start anchor legitimately land on the same time. That two-point
  -- step is how REAPER expresses an instant change and is exactly what a region
  -- change wants -- deleting per anchor rather than per time would collapse it.
  it("keeps a deliberate step pair at a shared bound", function()
    local env = { points = {} }
    local fake_api = anchor_api({ [3] = { envelopes = { Volume = env } } })

    apply.envelope_anchors(fake_api, { anchor(8, 0), anchor(8, 1) })

    assert.are.same({ "8=0", "8=1" }, times_and_values(env))
  end)

  it("keeps that step pair identical across a second run, in the same order", function()
    local env = { points = {} }
    local fake_api = anchor_api({ [3] = { envelopes = { Volume = env } } })
    local anchors = { anchor(8, 0), anchor(8, 1) }

    apply.envelope_anchors(fake_api, anchors)
    apply.envelope_anchors(fake_api, anchors)

    -- Three points here, with a trailing 0, is the real bug: it flips the value
    -- in effect from 8.0 onward from 1 to 0.
    assert.are.same({ "8=0", "8=1" }, times_and_values(env))
  end)

  it("does not disturb points at other times", function()
    local env = { points = {
      { time = 1, value = 0.1, shape = 1, tension = 0, selected = false },
      { time = 9, value = 0.9, shape = 1, tension = 0, selected = false },
    } }
    local fake_api = anchor_api({ [3] = { envelopes = { Volume = env } } })

    apply.envelope_anchors(fake_api, { anchor(6, 0.4) })

    assert.are.same({ "1=0.1", "6=0.4", "9=0.9" }, times_and_values(env))
  end)
end)

-- Two tempo markers cannot share a position: REAPER collapses them. So a move
-- onto a position another marker still occupies destroys one, silently -- four
-- markers went into a real Reordered run and three came out. The fake below
-- models that merge, so a colliding write order fails these specs instead of
-- quietly passing.
describe("apply.tempo_moves collision ordering", function()
  local function merging_tempo_api(points)
    return fake_reaper.new({
      CountTempoTimeSigMarkers = function() return #points end,
      GetTempoTimeSigMarker = function(_, idx)
        local point = points[idx + 1]
        if not point then
          return false
        end
        return true, point.position, -1, -1, point.bpm, point.timesig_num,
          point.timesig_denom, point.lineartempo or false
      end,
      SetTempoTimeSigMarker = function(_, idx, timepos, _, _, bpm, num, denom, linear)
        local point = points[idx + 1]
        if not point then
          return false
        end
        point.position, point.bpm, point.timesig_num, point.timesig_denom, point.lineartempo =
          timepos, bpm, num, denom, linear
        -- The merge REAPER performs, and the whole reason for the ordering.
        for i = #points, 1, -1 do
          if points[i] ~= point and math.abs(points[i].position - point.position) < 1e-9 then
            table.remove(points, i)
          end
        end
        -- REAPER will not leave the timeline origin without a tempo marker: move
        -- the one at 0.0 away and a fresh marker appears there carrying the
        -- project tempo. Modelled because it is what a real run deadlocked on --
        -- a move *to* 0.0 blocked by a marker that never moves.
        local origin = false
        for _, other in ipairs(points) do
          if math.abs(other.position) < 1e-9 then
            origin = true
          end
        end
        if not origin then
          points[#points + 1] = { position = 0, bpm = 120, timesig_num = 4, timesig_denom = 4 }
        end
        -- ptidx is position-sorted, so it is re-derived after every write.
        table.sort(points, function(a, b) return a.position < b.position end)
        return true
      end,
    })
  end

  local function marker(position, bpm, num, denom)
    return { position = position, bpm = bpm, timesig_num = num or 4, timesig_denom = denom or 4 }
  end

  local function move(from, to, bpm, num, denom)
    return { from = from, to = to, bpm = bpm, timesig_num = num or 4, timesig_denom = denom or 4,
      lineartempo = false }
  end

  local function layout(points)
    local out = {}
    for _, point in ipairs(points) do
      out[#out + 1] = ("%g=%g %d/%d"):format(point.position, point.bpm,
        point.timesig_num, point.timesig_denom)
    end
    return out
  end

  -- The exact case from the real run: reordering an already-packed project, where
  -- every destination is a position some other region's marker already holds.
  it("keeps every marker when a destination is still occupied", function()
    local points = { marker(0, 120), marker(8, 120), marker(18, 90), marker(26, 90, 3, 4) }
    local fake_api = merging_tempo_api(points)

    apply.tempo_moves(fake_api, {
      move(0, 8, 120),        -- Alpha, onto Bravo's position
      move(8, 22, 120),       -- Bravo
      move(18, 0, 90),        -- Charlie
      move(26, 16, 90, 3, 4), -- Delta
    })

    assert.are.equal(4, #points)
    assert.are.same({ "0=90 4/4", "8=120 4/4", "16=90 3/4", "22=120 4/4" }, layout(points))
  end)

  it("breaks a cycle of two markers swapping positions", function()
    local points = { marker(0, 100), marker(8, 140) }
    local fake_api = merging_tempo_api(points)

    apply.tempo_moves(fake_api, { move(0, 8, 100), move(8, 0, 140) })

    assert.are.equal(2, #points)
    assert.are.same({ "0=140 4/4", "8=100 4/4" }, layout(points))
  end)

  it("still moves markers whose destinations were free all along", function()
    local points = { marker(10, 120), marker(20, 90) }
    local fake_api = merging_tempo_api(points)

    apply.tempo_moves(fake_api, { move(10, 0, 120), move(20, 5, 90) })

    assert.are.same({ "0=120 4/4", "5=90 4/4" }, layout(points))
  end)

  -- Two different checks guard two different losses, so both are exercised.
  --
  -- This one: the planned marker lands correctly but an *unplanned* one is taken
  -- with it. A per-destination check cannot see that -- every marker the plan
  -- named is exactly where it was asked to go -- so only the count reveals it.
  it("raises when a write absorbs an unplanned marker", function()
    local points = { marker(0, 120), marker(8, 90) }
    local fake_api = fake_reaper.new({
      CountTempoTimeSigMarkers = function() return #points end,
      GetTempoTimeSigMarker = function(_, idx)
        local point = points[idx + 1]
        if not point then
          return false
        end
        return true, point.position, -1, -1, point.bpm, 4, 4, false
      end,
      SetTempoTimeSigMarker = function(_, idx, timepos)
        points[idx + 1].position = timepos
        -- Swallows the marker at 8.0, which this run never asked about.
        for i = #points, 1, -1 do
          if math.abs(points[i].position - 8) < 1e-9 then
            table.remove(points, i)
          end
        end
        return true
      end,
    })

    local ok, err = pcall(apply.tempo_moves, fake_api, { move(0, 30, 120) })

    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("lost 1 marker", 1, true))
  end)

  -- And this one: the planned destination itself ends up empty, because another
  -- marker at the same position absorbed it.
  it("raises when a planned destination ends up without a marker", function()
    local points = { marker(0, 120) }
    local fake_api = fake_reaper.new({
      CountTempoTimeSigMarkers = function() return #points end,
      GetTempoTimeSigMarker = function(_, idx)
        local point = points[idx + 1]
        if not point then
          return false
        end
        return true, point.position, -1, -1, point.bpm, 4, 4, false
      end,
      -- Claims success and moves nothing, the shape a silent merge takes.
      SetTempoTimeSigMarker = function() return true end,
    })

    local ok, err = pcall(apply.tempo_moves, fake_api, { move(0, 30, 120) })

    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("is not there after the move", 1, true))
  end)
end)

describe("apply.split_parks", function()
  it("routes each parked kind into the shape its own applier takes", function()
    local sorted = apply.split_parks({
      { kind = "region", name = "Outtake", number = 4, from = 100, to = 900, length = 30, delta = 800 },
      { kind = "marker", name = "cue", number = 7, from = 110, to = 910, delta = 800 },
      { kind = "envelope", track_index = 1, envelope_name = "Volume", from = 120, to = 920,
        value = 0.5, shape = 1, tension = 0, selected = false, delta = 800 },
      { kind = "item", track_index = 1, from = 130, to = 930, length = 5, delta = 800 },
    })

    assert.are.same({ { name = "Outtake", number = 4, to_start = 900, length = 30 } }, sorted.regions)
    assert.are.same({ { name = "cue", number = 7, to = 910 } }, sorted.markers)
    assert.are.same({ { track_index = 1, envelope_name = "Volume", from = 120, to = 920,
      value = 0.5, shape = 1, tension = 0, selected = false } }, sorted.envelopes)
    assert.are.same({ { track_index = 1, from = 130, to = 930 } }, sorted.items)
  end)

  -- The whole point of routing on `kind`: a category nobody handles must not
  -- fall through to nothing, which is issue #12's failure shape exactly.
  it("refuses a parked kind it cannot move, rather than dropping it silently", function()
    local ok, err = pcall(apply.split_parks, { { kind = "video", from = 1, to = 2 } })
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("video", 1, true))
  end)

  it("treats a plan with no parks as nothing to route", function()
    local sorted = apply.split_parks(nil)
    assert.are.same({ regions = {}, markers = {}, envelopes = {}, items = {} }, sorted)
  end)
end)

describe("apply.plan parking", function()
  -- Parked items sit furthest out on the timeline, so they are downstream of
  -- every tempo edit a run makes: if their handles were resolved after the
  -- transplant, a beat-based one would already have been dragged off the
  -- position the plan recorded. This is the same failure apply.locate_items
  -- exists for, in the place most exposed to it.
  it("locates parked items before the first tempo write", function()
    local tracks = { [1] = { items = { { position = 500, length = 5 } } } }
    local tempo_points = { { position = 10, bpm = 120, timesig_num = 4, timesig_denom = 4 } }
    local fake_api = item_api(tracks, {
      SetProjectMarker4 = true,
      CountTempoTimeSigMarkers = function() return #tempo_points end,
      GetTempoTimeSigMarker = function(_, idx)
        local point = tempo_points[idx + 1]
        if not point then
          return false
        end
        return true, point.position, -1, -1, point.bpm, point.timesig_num, point.timesig_denom, false
      end,
      -- Actually moves it: apply.tempo_moves verifies every planned destination
      -- holds a marker afterwards, which a stub that only returns true fails.
      SetTempoTimeSigMarker = function(_, idx, timepos)
        tempo_points[idx + 1].position = timepos
        return true
      end,
    })

    apply.plan(fake_api, {
      splits = {}, drops = {}, envelope_drops = {}, places = {}, envelope_moves = {},
      envelope_anchors = {}, marker_moves = {}, item_moves = {},
      -- Deliberately not moved by the fake, so a lookup made after the write
      -- would still succeed; the assertion is on ordering, not on failure.
      tempo_moves = { tempo_move(10, 0, 120, 4, 4, false) },
      parks = { { kind = "item", track_index = 1, from = 500, to = 1300, delta = 800 } },
    })

    local order = {}
    for _, call in ipairs(fake_api.calls) do
      if call.name == "GetTrackMediaItem" or call.name == "SetTempoTimeSigMarker" then
        order[#order + 1] = call.name
      end
    end
    assert.are.equal("GetTrackMediaItem", order[1])
    assert.is_truthy(order[#order] == "SetTempoTimeSigMarker" or #order == 1)
    assert.are.equal(1300, fake_api.calls_to("SetMediaItemInfo_Value")[1].args[3])
  end)

  it("writes a parked region's both bounds, translated by the shared offset", function()
    local fake_api = fake_reaper.new({ SetProjectMarker4 = true })

    apply.plan(fake_api, {
      splits = {}, drops = {}, envelope_drops = {}, places = {}, tempo_moves = {},
      envelope_moves = {}, envelope_anchors = {}, marker_moves = {}, item_moves = {},
      parks = { { kind = "region", name = "Outtake", number = 4,
        from = 100, to = 900, length = 30, delta = 800 } },
    })

    local call = fake_api.calls_to("SetProjectMarker4")[1]
    assert.are.equal(4, call.args[2])
    assert.is_true(call.args[3])
    assert.are.equal(900, call.args[4])
    assert.are.equal(930, call.args[5])
    assert.are.equal("Outtake", call.args[6])
  end)

  it("moves a parked marker as a marker, not as a region", function()
    local fake_api = fake_reaper.new({ SetProjectMarker4 = true })

    apply.plan(fake_api, {
      splits = {}, drops = {}, envelope_drops = {}, places = {}, tempo_moves = {},
      envelope_moves = {}, envelope_anchors = {}, marker_moves = {}, item_moves = {},
      parks = { { kind = "marker", name = "cue", number = 7, from = 110, to = 910, delta = 800 } },
    })

    local call = fake_api.calls_to("SetProjectMarker4")[1]
    assert.is_false(call.args[3])
    assert.are.equal(910, call.args[4])
  end)

  -- Value, shape and tension survive parking for the same reason they survive
  -- a transplant: parking moves a point, it does not redraw the curve.
  it("moves a parked envelope point without redrawing it", function()
    local env = { points = { { time = 120, value = 0.5, shape = 1, tension = 0, selected = false } } }
    local fake_api = fake_reaper.new({
      GetTrack = function(_, idx) return ({ [1] = { envelopes = { Volume = env } } })[idx] end,
      GetTrackEnvelopeByName = function(track, name) return track.envelopes[name] end,
      CountEnvelopePoints = function(envelope) return #envelope.points end,
      GetEnvelopePoint = function(envelope, idx)
        local point = envelope.points[idx + 1]
        if not point then
          return false
        end
        return true, point.time, point.value, point.shape, point.tension, point.selected
      end,
      SetEnvelopePointEx = function(envelope, _, idx, time, value, shape, tension, selected)
        local point = envelope.points[idx + 1]
        point.time, point.value, point.shape, point.tension, point.selected =
          time, value, shape, tension, selected
      end,
    })

    apply.plan(fake_api, {
      splits = {}, drops = {}, envelope_drops = {}, places = {}, tempo_moves = {},
      envelope_moves = {}, envelope_anchors = {}, marker_moves = {}, item_moves = {},
      parks = { { kind = "envelope", track_index = 1, envelope_name = "Volume",
        from = 120, to = 920, value = 0.5, shape = 1, tension = 0, selected = false, delta = 800 } },
    })

    assert.are.same({ { time = 920, value = 0.5, shape = 1, tension = 0, selected = false } }, env.points)
  end)
end)
