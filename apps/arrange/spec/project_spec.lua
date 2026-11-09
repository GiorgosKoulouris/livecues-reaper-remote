local project = require("lib.project")

-- The fake offers *both* region/marker readers over the same entries, so a
-- spec can exercise either (issue #11). By default `project.snapshot` takes the
-- modern handle-based family; `without_modern_reader` strips it to leave the
-- legacy enumerator, which is what a REAPER build lacking the family presents.
--
-- Modern (research/reaper-scripting.md §4.1d): GetRegionOrMarker returns an
-- opaque handle -- here the entry table itself -- that the Info_Value and
-- Info_String calls then read, a value at a time.
--
-- Legacy: EnumProjectMarkers3(proj, idx) -> retval, isrgn, pos, rgnend, name,
-- number, with retval 0 when there is nothing at that index. Entries are handed
-- back in an order this suite deliberately does not depend on either way
-- (CLAUDE.md, "Traps").
local function api_with(entries, project_path)
  return {
    EnumProjects = function() return 0, project_path or [[D:\P\Song.RPP]] end,
    EnumProjectMarkers3 = function(_, idx)
      local entry = entries[idx + 1]
      if not entry then
        return 0
      end
      return idx + 1, entry.isrgn, entry.pos, entry.rgnend or 0, entry.name, entry.number
    end,
    GetNumRegionsOrMarkers = function() return #entries end,
    GetRegionOrMarker = function(_, index) return entries[index + 1] end,
    -- Declared `number reaper.GetRegionOrMarkerInfo_Value(...)`, so under Lua
    -- 5.4 every one of these comes back a float -- including the ones that are
    -- conceptually integers. The fake reproduces that (`+ 0.0`) rather than
    -- handing back tidy Lua integers the real call would not.
    GetRegionOrMarkerInfo_Value = function(_, entry, parameter)
      if parameter == "D_STARTPOS" then
        return entry.pos
      elseif parameter == "D_ENDPOS" then
        -- REAPER reports D_ENDPOS == D_STARTPOS for a marker.
        return entry.isrgn and (entry.rgnend or 0) or entry.pos
      elseif parameter == "I_NUMBER" then
        return entry.number + 0.0
      elseif parameter == "B_ISREGION" then
        return entry.isrgn and 1.0 or 0.0
      elseif parameter == "B_HIDDEN" then
        return entry.hidden and 1.0 or 0.0
      elseif parameter == "I_LANENUMBER" then
        return (entry.lane or 0) + 0.0
      end
      return 0.0
    end,
    GetSetRegionOrMarkerInfo_String = function(_, entry, parameter)
      return true, parameter == "P_NAME" and entry.name or ""
    end,
    -- No tracks by default -- most snapshot specs don't care about items.
    CountTracks = function() return 0 end,
    -- No tempo markers and no master-track automation by default either.
    CountTempoTimeSigMarkers = function() return 0 end,
    GetMasterTrack = function() return nil end,
  }
end

-- A REAPER build without the modern family: every other call is unchanged, so
-- what a spec using this asserts is the fallback path and nothing else.
local function without_modern_reader(api)
  api.GetNumRegionsOrMarkers = nil
  api.GetRegionOrMarker = nil
  api.GetRegionOrMarkerInfo_Value = nil
  api.GetSetRegionOrMarkerInfo_String = nil
  return api
end

-- Simulates CountTempoTimeSigMarkers/GetTempoTimeSigMarker.
-- GetTempoTimeSigMarker -> retval, timepos, measurepos, beatpos, bpm,
-- timesig_num, timesig_denom, lineartempo. measurepos/beatpos/lineartempo
-- default the way a plain single-tempo marker would report them, so specs
-- that don't care can omit them.
local function api_with_tempo(points, entries)
  local api = api_with(entries)
  api.CountTempoTimeSigMarkers = function() return #points end
  api.GetTempoTimeSigMarker = function(_, idx)
    local point = points[idx + 1]
    if not point then
      return false
    end
    return true, point.position, point.measurepos or -1, point.beatpos or -1,
      point.bpm, point.num, point.denom, point.lineartempo or false
  end
  return api
end

-- Simulates CountTracks/GetTrack/CountTrackMediaItems/GetTrackMediaItem plus
-- the per-item calls project.snapshot makes to read position/length and
-- determine timebase safety (research/reaper-scripting.md §4.1c/§4.3).
-- track_specs: { { mode = <C_BEATATTACHMODE>, items = { { position, length,
-- beat_override } , ... } }, ... }. A track/item handle is just its own spec
-- table -- the fake never needs to distinguish a "real" userdata handle.
local function api_with_tracks(track_specs, entries, project_path)
  local api = api_with(entries, project_path)
  api.CountTracks = function() return #track_specs end
  api.GetTrack = function(_, idx) return track_specs[idx + 1] end
  api.GetMediaTrackInfo_Value = function(track) return track.mode end
  api.GetSetMediaTrackInfo_String = function(track) return true, track.name or "" end
  api.CountTrackMediaItems = function(track) return #track.items end
  api.GetTrackMediaItem = function(track, idx) return track.items[idx + 1] end
  api.GetMediaItemInfo_Value = function(item, key)
    if key == "D_POSITION" then
      return item.position
    end
    return item.length
  end
  api.GetItemStateChunk = function(item)
    if item.beat_override == nil then
      return true, "<ITEM\n  POSITION 0\n>"
    end
    return true, ("<ITEM\n  BEAT %d\n>"):format(item.beat_override)
  end

  -- Track envelopes, as issue #12's refusal needs them. A track spec may carry
  -- `envelopes = { { name = "Volume", points = { <time>, ... } }, ... }`; a
  -- track without the key simply has no automation.
  -- GetEnvelopePoint -> retval, time, value, shape, tension, selected.
  api.CountTrackEnvelopes = function(track) return #(track.envelopes or {}) end
  api.GetTrackEnvelope = function(track, idx) return track.envelopes[idx + 1] end
  api.GetEnvelopeName = function(envelope) return true, envelope.name end
  api.CountEnvelopePoints = function(envelope) return #envelope.points end
  api.GetEnvelopePoint = function(envelope, idx)
    local time = envelope.points[idx + 1]
    if not time then
      return false
    end
    -- A point may be given as { time, value } to say which of two points at one
    -- time is which.
    if type(time) == "table" then
      return true, time[1], time[2], 0, 0, false
    end
    return true, time, 0.5, 0, 0, false
  end
  return api
end

describe("project.path", function()
  it("reads the current project's file path", function()
    assert.are.equal([[D:\P\Song.RPP]], project.path(api_with({})))
  end)

  it("returns an empty string for a project that was never saved", function()
    assert.are.equal("", project.path(api_with({}, "")))
  end)
end)

describe("project.snapshot", function()
  it("collects regions with their bounds and Region Numbers", function()
    local snapshot = project.snapshot(api_with({
      { isrgn = true, pos = 10, rgnend = 20, name = "Intro", number = 3 },
    }))

    assert.are.equal(1, #snapshot.regions)
    assert.are.same(
      { name = "Intro", number = 3, start_time = 10, end_time = 20, hidden = false, lane = 0 },
      snapshot.regions[1])
  end)

  it("keeps markers separate from regions", function()
    local snapshot = project.snapshot(api_with({
      { isrgn = true, pos = 10, rgnend = 20, name = "Intro", number = 3 },
      { isrgn = false, pos = 12, name = "cue", number = 4 },
    }))

    assert.are.equal(1, #snapshot.regions)
    assert.are.equal(1, #snapshot.markers)
    assert.are.equal("cue", snapshot.markers[1].name)
    assert.are.equal(12, snapshot.markers[1].position)
  end)

  -- Every song in the live project carries a marker at its region's start.
  it("keeps a marker and a region that share a position and a name apart", function()
    local snapshot = project.snapshot(api_with({
      { isrgn = false, pos = 10, name = "Maze", number = 9 },
      { isrgn = true, pos = 10, rgnend = 20, name = "Maze", number = 3 },
    }))

    assert.are.equal(1, #snapshot.regions)
    assert.are.equal(1, #snapshot.markers)
  end)

  it("returns the project path alongside", function()
    assert.are.equal([[D:\P\Song.RPP]], project.snapshot(api_with({})).project_path)
  end)

  it("handles a project with no markers or regions", function()
    local snapshot = project.snapshot(api_with({}))
    assert.are.same({}, snapshot.regions)
    assert.are.same({}, snapshot.markers)
  end)

  -- Enumeration order is unverified, so the snapshot sorts rather than trusting it.
  it("orders regions by position regardless of enumeration order", function()
    local snapshot = project.snapshot(api_with({
      { isrgn = true, pos = 50, rgnend = 60, name = "Late", number = 1 },
      { isrgn = true, pos = 10, rgnend = 20, name = "Early", number = 9 },
    }))

    assert.are.equal("Early", snapshot.regions[1].name)
    assert.are.equal("Late", snapshot.regions[2].name)
  end)

  it("orders markers by position too", function()
    local snapshot = project.snapshot(api_with({
      { isrgn = false, pos = 50, name = "b", number = 1 },
      { isrgn = false, pos = 10, name = "a", number = 2 },
    }))

    assert.are.equal("a", snapshot.markers[1].name)
  end)

  -- An unbounded while-loop against a misbehaving API would hang REAPER itself.
  it("stops at a sane bound rather than looping forever", function()
    local endless = {
      EnumProjects = function() return 0, "" end,
      EnumProjectMarkers3 = function(_, idx)
        return idx + 1, true, idx, idx + 1, "r" .. idx, idx
      end,
      CountTracks = function() return 0 end,
      CountTempoTimeSigMarkers = function() return 0 end,
      GetMasterTrack = function() return nil end,
    }

    local snapshot = project.snapshot(endless)
    assert.are.equal(project.MAX_MARKERS, #snapshot.regions)
  end)

  -- The modern reader is bounded by a count rather than by a sentinel, so the
  -- same hang is one absurd return value away.
  it("bounds the modern reader by MAX_MARKERS too", function()
    local absurd = {
      EnumProjects = function() return 0, "" end,
      GetNumRegionsOrMarkers = function() return math.maxinteger end,
      GetRegionOrMarker = function(_, index) return { index = index } end,
      GetRegionOrMarkerInfo_Value = function(_, handle, parameter)
        if parameter == "B_ISREGION" then
          return 1
        elseif parameter == "D_STARTPOS" then
          return handle.index
        elseif parameter == "D_ENDPOS" then
          return handle.index + 1
        end
        return 0
      end,
      GetSetRegionOrMarkerInfo_String = function(_, handle) return true, "r" .. handle.index end,
      CountTracks = function() return 0 end,
      CountTempoTimeSigMarkers = function() return 0 end,
      GetMasterTrack = function() return nil end,
    }

    assert.are.equal(project.MAX_MARKERS, #project.snapshot(absurd).regions)
  end)
end)

-- Issue #11. `EnumProjectMarkers3` is the call REAPER's own reference calls
-- discouraged, but it is also the only one with a real execution history
-- against the live project, so the modern family is preferred and the old one
-- kept as the fallback rather than deleted (ADR-0001's guard convention).
describe("project.snapshot region/marker reader", function()
  local function entries()
    return {
      { isrgn = true, pos = 10, rgnend = 20, name = "Intro", number = 3, hidden = true, lane = 2 },
      { isrgn = false, pos = 12, name = "cue", number = 4, lane = 1 },
    }
  end

  it("prefers the modern handle-based family when the build has it", function()
    assert.are.equal(project.READER_MODERN, project.snapshot(api_with(entries())).region_reader)
  end)

  it("reads the same regions and markers through it", function()
    local snapshot = project.snapshot(api_with(entries()))

    assert.are.equal(1, #snapshot.regions)
    assert.are.equal(1, #snapshot.markers)
    assert.are.equal("Intro", snapshot.regions[1].name)
    assert.are.equal(10, snapshot.regions[1].start_time)
    assert.are.equal(20, snapshot.regions[1].end_time)
    assert.are.equal(3, snapshot.regions[1].number)
    assert.are.equal("cue", snapshot.markers[1].name)
    assert.are.equal(12, snapshot.markers[1].position)
    assert.are.equal(4, snapshot.markers[1].number)
  end)

  -- The whole practical argument for switching: `EnumProjectMarkers3` has no
  -- equivalent of either, so a hidden region was indistinguishable from a
  -- visible one and marker lanes were invisible entirely (research §4.1d).
  it("carries the hidden flag and the lane number the old call cannot see", function()
    local snapshot = project.snapshot(api_with(entries()))

    assert.is_true(snapshot.regions[1].hidden)
    assert.are.equal(2, snapshot.regions[1].lane)
    assert.is_false(snapshot.markers[1].hidden)
    assert.are.equal(1, snapshot.markers[1].lane)
  end)

  -- `GetRegionOrMarkerInfo_Value` returns a `number`, so a Region Number
  -- arrives as the float `3.0` where the old call returned the integer `3`.
  -- `assert.are.equal(3, 3.0)` is true in Lua, so this asserts the type: a
  -- float here reaches the user as "Region Numbers 3.0" in a refusal, and
  -- REAPER as a marker ID via `SetProjectMarker4`.
  it("carries Region Numbers and lanes as integers, not floats", function()
    local snapshot = project.snapshot(api_with(entries()))

    assert.are.equal("integer", math.type(snapshot.regions[1].number))
    assert.are.equal("integer", math.type(snapshot.regions[1].lane))
    assert.are.equal("integer", math.type(snapshot.markers[1].number))
    assert.are.equal("integer", math.type(snapshot.markers[1].lane))
  end)

  -- A marker reports D_ENDPOS == D_STARTPOS, which must not become an
  -- end_time: markers are points, and nothing downstream expects one.
  it("does not give a marker an end_time", function()
    local snapshot = project.snapshot(api_with(entries()))
    assert.is_nil(snapshot.markers[1].end_time)
  end)

  it("falls back to EnumProjectMarkers3 when the family is missing", function()
    local snapshot = project.snapshot(without_modern_reader(api_with(entries())))

    assert.are.equal(project.READER_LEGACY, snapshot.region_reader)
    assert.are.equal("Intro", snapshot.regions[1].name)
    assert.are.equal("cue", snapshot.markers[1].name)
  end)

  -- The fallback is a like-for-like reader of the shape that has always been
  -- returned, not a partial one: it simply cannot see hidden or lane.
  it("omits hidden and lane on the fallback rather than inventing them", function()
    local snapshot = project.snapshot(without_modern_reader(api_with(entries())))

    assert.are.same(
      { name = "Intro", number = 3, start_time = 10, end_time = 20 },
      snapshot.regions[1])
  end)

  -- "By internal index" says the index is stable and addressable, not that
  -- 0..count-1 enumerates every entry (research §4.1d). If it does not, the
  -- modern read is short, and a short read of the project's regions is the one
  -- failure that must never pass silently -- so it is not trusted at all.
  it("falls back when the modern read comes up short of the reported count", function()
    local api = api_with(entries())
    api.GetNumRegionsOrMarkers = function() return 3 end

    local snapshot = project.snapshot(api)

    assert.are.equal(project.READER_LEGACY, snapshot.region_reader)
    assert.are.equal(1, #snapshot.regions)
    assert.are.equal(1, #snapshot.markers)
  end)

  it("reports the modern reader for a project with nothing to read", function()
    assert.are.equal(project.READER_MODERN, project.snapshot(api_with({})).region_reader)
  end)
end)

describe("project.snapshot items", function()
  local function item(position, length, beat_override)
    return { position = position, length = length, beat_override = beat_override }
  end

  it("reads an item's position, length and track index", function()
    local snapshot = project.snapshot(api_with_tracks({
      { mode = 0, name = "Snare", items = { item(10, 5) } },
    }, {}))

    assert.are.equal(1, #snapshot.items)
    assert.are.same(
      { track_index = 0, track_name = "Snare", position = 10, length = 5, timebase_safe = true },
      snapshot.items[1])
  end)

  -- REAPER neither requires nor guarantees a track name, so the snapshot
  -- carries whatever P_NAME gives back, empty string included.
  it("carries an empty track name rather than omitting the field", function()
    local snapshot = project.snapshot(api_with_tracks({ { mode = 0, items = { item(0, 1) } } }, {}))

    assert.are.equal("", snapshot.items[1].track_name)
  end)

  it("is safe on a time-based track (mode 0)", function()
    local snapshot = project.snapshot(api_with_tracks({ { mode = 0, items = { item(0, 1) } } }, {}))
    assert.is_true(snapshot.items[1].timebase_safe)
  end)

  it("is safe on a beats-position-only track (mode 2)", function()
    local snapshot = project.snapshot(api_with_tracks({ { mode = 2, items = { item(0, 1) } } }, {}))
    assert.is_true(snapshot.items[1].timebase_safe)
  end)

  -- Confirmed by real-REAPER test: mode 1 stretches a repositioned item's
  -- content (research/reaper-scripting.md §4.1c).
  it("is unsafe on a full-beat track (mode 1)", function()
    local snapshot = project.snapshot(api_with_tracks({ { mode = 1, items = { item(0, 1) } } }, {}))
    assert.is_false(snapshot.items[1].timebase_safe)
  end)

  -- -1 (project default) is treated as unsafe: what it resolves to isn't
  -- confirmed yet, and this suite refuses rather than guesses.
  it("is unsafe on a project-default track (-1)", function()
    local snapshot = project.snapshot(api_with_tracks({ { mode = -1, items = { item(0, 1) } } }, {}))
    assert.is_false(snapshot.items[1].timebase_safe)
  end)

  -- Per-item overrides have no confirmed numeric key, so this is read from
  -- the item's own chunk instead (§4.3).
  it("is unsafe when an item overrides an otherwise-safe track to full-beat", function()
    local snapshot = project.snapshot(api_with_tracks({
      { mode = 0, items = { item(0, 1, 1) } },
    }, {}))
    assert.is_false(snapshot.items[1].timebase_safe)
  end)

  it("stays safe when an item's override is -1 (use track timebase)", function()
    local snapshot = project.snapshot(api_with_tracks({
      { mode = 0, items = { item(0, 1, -1) } },
    }, {}))
    assert.is_true(snapshot.items[1].timebase_safe)
  end)

  it("stays safe when an item explicitly overrides to a safe mode", function()
    local snapshot = project.snapshot(api_with_tracks({
      { mode = 0, items = { item(0, 1, 2) } },
    }, {}))
    assert.is_true(snapshot.items[1].timebase_safe)
  end)

  it("orders items by position across tracks", function()
    local snapshot = project.snapshot(api_with_tracks({
      { mode = 0, items = { item(50, 1) } },
      { mode = 0, items = { item(10, 1) } },
    }, {}))

    assert.are.equal(10, snapshot.items[1].position)
    assert.are.equal(50, snapshot.items[2].position)
  end)

  it("is empty for a project with tracks but no items", function()
    local snapshot = project.snapshot(api_with_tracks({ { mode = 0, items = {} } }, {}))
    assert.are.same({}, snapshot.items)
  end)

  it("is empty for a project with no tracks", function()
    assert.are.same({}, project.snapshot(api_with({})).items)
  end)
end)

-- Read only so a run can refuse to strand them (issue #12): before this, the
-- key was hardcoded to {} and the guard counting plan.tempo_moves therefore
-- always passed, whatever the project actually contained.
describe("project.snapshot tempo markers", function()
  -- The transplant (issue #4) needs measurepos/beatpos/lineartempo too, not
  -- just position/bpm/timesig: the live project has tempo ramps and
  -- partial-measure time-signature points, and dropping lineartempo would
  -- rewrite the curve rather than move it.
  it("reads enough to transplant faithfully -- position, tempo, time signature, "
    .. "measure/beat position and the ramp flag", function()
    local snapshot = project.snapshot(api_with_tempo({
      { position = 12.5, bpm = 128, num = 7, denom = 8, measurepos = 3, beatpos = 1.5, lineartempo = true },
    }, {}))

    assert.are.equal(1, #snapshot.tempo_markers)
    assert.are.same(
      { position = 12.5, measurepos = 3, beatpos = 1.5, bpm = 128,
        timesig_num = 7, timesig_denom = 8, lineartempo = true },
      snapshot.tempo_markers[1])
  end)

  it("orders them by position", function()
    local snapshot = project.snapshot(api_with_tempo({
      { position = 50, bpm = 90 },
      { position = 10, bpm = 120 },
    }, {}))

    assert.are.equal(10, snapshot.tempo_markers[1].position)
    assert.are.equal(50, snapshot.tempo_markers[2].position)
  end)

  it("is empty for a project with no tempo markers", function()
    assert.are.same({}, project.snapshot(api_with({})).tempo_markers)
  end)
end)

describe("project.snapshot envelope points", function()
  it("reads a point's time with the track and envelope it belongs to", function()
    local snapshot = project.snapshot(api_with_tracks({
      { mode = 0, name = "Kick", items = {}, envelopes = { { name = "Volume", points = { 4 } } } },
    }, {}))

    assert.are.equal(1, #snapshot.envelope_points)
    assert.are.same(
      { track_index = 0, track_name = "Kick", envelope_name = "Volume", position = 4,
        value = 0.5, shape = 0, tension = 0, selected = false },
      snapshot.envelope_points[1])
  end)

  -- Issue #8's carry needs to write a point back unchanged except for time,
  -- so value, shape, tension and selected are read now too, not just time.
  it("reads a point's value, shape, tension and selection, not just its time", function()
    local api = api_with_tracks({ { mode = 0, items = {}, envelopes = { { name = "Volume", points = {} } } } }, {})
    api.CountEnvelopePoints = function() return 1 end
    api.GetEnvelopePoint = function() return true, 4, 0.83, 2, 0.4, true end

    local point = project.snapshot(api).envelope_points[1]
    assert.are.equal(0.83, point.value)
    assert.are.equal(2, point.shape)
    assert.are.equal(0.4, point.tension)
    assert.is_true(point.selected)
  end)

  it("reads every envelope on a track, and every point on each", function()
    local snapshot = project.snapshot(api_with_tracks({
      { mode = 0, items = {}, envelopes = {
        { name = "Volume", points = { 1, 2 } },
        { name = "Pan", points = { 3 } },
      } },
    }, {}))

    assert.are.equal(3, #snapshot.envelope_points)
  end)

  it("orders points by position across tracks and envelopes", function()
    local snapshot = project.snapshot(api_with_tracks({
      { mode = 0, items = {}, envelopes = { { name = "Volume", points = { 50 } } } },
      { mode = 0, items = {}, envelopes = { { name = "Volume", points = { 10 } } } },
    }, {}))

    assert.are.equal(10, snapshot.envelope_points[1].position)
    assert.are.equal(50, snapshot.envelope_points[2].position)
  end)

  -- Real automation is authored as step pairs: two points at one time, where
  -- the *last* is the value in effect afterwards (lib/regions.lua's
  -- `value_at_bound` depends on that). `table.sort` is not stable, so sorting
  -- every point by position used to shuffle such pairs: on a real project a
  -- second Apply wrote the other half of a step at five shared region bounds,
  -- flipping Mute states (.scratch/arrange/issues/02).
  it("keeps the order of points that share a time, as REAPER holds them", function()
    local tracks = {}
    for track = 1, 12 do
      local points = {}
      for step = 1, 8 do
        points[#points + 1] = { step * 10, 0 }
        points[#points + 1] = { step * 10, 1 }
      end
      tracks[track] = { mode = 0, items = {}, envelopes = { { name = "Mute", points = points } } }
    end

    local snapshot = project.snapshot(api_with_tracks(tracks, {}))

    -- Per envelope: at every time, the 0 comes before the 1.
    local seen = {}
    for _, point in ipairs(snapshot.envelope_points) do
      local key = point.track_index .. "@" .. point.position
      if seen[key] == nil then
        assert.are.equal(0, point.value, "the first point at " .. key .. " should be the 0")
      else
        assert.are.equal(1, point.value, "the second point at " .. key .. " should be the 1")
      end
      seen[key] = point.value
    end
  end)

  -- Master automation is stranded by a Repack exactly like a track's, and the
  -- master has no index in REAPER's track enumeration to report it under.
  it("reads the master track's envelopes, under MASTER_TRACK_INDEX", function()
    local api = api_with_tracks({}, {})
    api.GetMasterTrack = function()
      return { envelopes = { { name = "Volume", points = { 7 } } } }
    end

    local snapshot = project.snapshot(api)
    assert.are.same(
      { track_index = project.MASTER_TRACK_INDEX, track_name = "Master",
        envelope_name = "Volume", position = 7,
        value = 0.5, shape = 0, tension = 0, selected = false },
      snapshot.envelope_points[1])
  end)

  -- Confirmed against REAPER 7.78/win64: the master track enumerates the
  -- project tempo map as an envelope, 1:1 with the tempo markers. Reading both
  -- would double-count every tempo point -- noise in a refusal, a double move
  -- once #4 and #8 write.
  it("skips the tempo map the master track exposes as an envelope", function()
    local api = api_with_tracks({}, {})
    api.GetMasterTrack = function()
      return { envelopes = {
        { name = "Tempo map", points = { 3 } },
        { name = "Volume", points = { 7 } },
      } }
    end

    local snapshot = project.snapshot(api)
    assert.are.equal(1, #snapshot.envelope_points)
    assert.are.equal("Volume", snapshot.envelope_points[1].envelope_name)
  end)

  -- Skipping is by name, the only handle REAPER offers, and is scoped to the
  -- master: a user's own "Tempo map"-named track envelope is still real
  -- automation that a Repack would strand.
  it("does not skip a track envelope that happens to be named Tempo map", function()
    local snapshot = project.snapshot(api_with_tracks({
      { mode = 0, items = {}, envelopes = { { name = "Tempo map", points = { 3 } } } },
    }, {}))

    assert.are.equal(1, #snapshot.envelope_points)
  end)

  it("is empty for a track with no envelopes", function()
    local snapshot = project.snapshot(api_with_tracks({ { mode = 0, items = {} } }, {}))
    assert.are.same({}, snapshot.envelope_points)
  end)

  -- The calling convention is unconfirmed (research §4.4), so both plausible
  -- shapes are accepted rather than one being guessed at.
  it("accepts a GetEnvelopeName that returns the name directly", function()
    local api = api_with_tracks({
      { mode = 0, items = {}, envelopes = { { name = "Volume", points = { 4 } } } },
    }, {})
    api.GetEnvelopeName = function(envelope) return envelope.name end

    assert.are.equal("Volume", project.snapshot(api).envelope_points[1].envelope_name)
  end)
end)

describe("project.region_names", function()
  it("lists Region Names in timeline order", function()
    local snapshot = project.snapshot(api_with({
      { isrgn = true, pos = 50, rgnend = 60, name = "Second", number = 1 },
      { isrgn = true, pos = 10, rgnend = 20, name = "First", number = 9 },
    }))

    assert.are.same({ "First", "Second" }, project.region_names(snapshot))
  end)

  it("is empty when the project has no regions", function()
    assert.are.same({}, project.region_names(project.snapshot(api_with({}))))
  end)
end)

-- The reader and the planner together, on the shape that went wrong on a real
-- project (issue 02): step pairs on many envelopes, two regions sharing a bound
-- that holds one. Each unit is covered on its own (above, and regions_spec's
-- "takes the last of a step pair"); this is the seam between them, which is
-- where the order of tied points is silently lost or kept.
describe("project.snapshot feeding regions.plan_pack", function()
  local regions = require("lib.regions")
  local harness = require("spec.support.script_harness")

  it("anchors every shared bound with the last point of its step pair", function()
    local tracks = {}
    for track = 1, 12 do
      local points = {}
      for step = 1, 8 do
        points[#points + 1] = { step * 2, 0 }
        points[#points + 1] = { step * 2, 1 }
      end
      tracks[track] = { mode = 0, name = "T" .. track, items = {},
        envelopes = { { name = "Mute", points = points } } }
    end
    local api = api_with_tracks(tracks, {
      { isrgn = true, pos = 0, rgnend = 8, name = "A", number = 1 },
      { isrgn = true, pos = 8, rgnend = 16, name = "B", number = 2 },
    })
    api.TimeMap2_timeToBeats = function() return 0, 1 end

    local plan = assert(regions.plan_pack(project.snapshot(api), { "A", "B" },
      harness.even_grid(2, 200), { value_at = function() return 0.5 end }))

    -- (A's start at 0 has no point before it, so the oracle answers there.)
    local checked = 0
    for _, anchor in ipairs(plan.envelope_anchors) do
      if anchor.from > 0 then
        checked = checked + 1
        assert.are.equal(1, anchor.value, ("%s at %s (%s)"):format(
          anchor.track_name, anchor.from, anchor.edge))
      end
    end
    assert.are.equal(12 * 3, checked)
  end)
end)
