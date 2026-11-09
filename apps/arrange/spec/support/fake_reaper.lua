-- A recording stand-in for the `reaper` table.
--
-- `lib/` never reaches for the global `reaper` directly; the modules that touch
-- the API take it as an injected dependency (see ADR-0001 -- appliers are the
-- only reaper.* callers, and they stay small enough to fake wholesale). This
-- records every call in order so specs can assert on the sequence, which is
-- what matters for undo blocks.

local fake_reaper = {}

function fake_reaper.new(overrides)
  local calls = {}

  local api = {
    calls = calls,

    -- Return the calls made to one function, in order.
    calls_to = function(name)
      local matches = {}
      for _, call in ipairs(calls) do
        if call.name == name then
          matches[#matches + 1] = call
        end
      end
      return matches
    end,

    -- The ordered list of function names, for asserting call sequence.
    call_names = function()
      local names = {}
      for index, call in ipairs(calls) do
        names[index] = call.name
      end
      return names
    end,
  }

  local function record(name, result)
    api[name] = function(...)
      calls[#calls + 1] = { name = name, args = table.pack(...) }
      if type(result) == "function" then
        return result(...)
      end
      return result
    end
  end

  record("Undo_BeginBlock")
  record("Undo_EndBlock")
  record("ShowConsoleMsg")
  record("ShowMessageBox", 0)

  for name, result in pairs(overrides or {}) do
    record(name, result)
  end

  return api
end

-- A small stateful project behind the same recording api: a tempo map,
-- regions and markers, and tracks with envelopes -- enough for a whole
-- `apply.plan` to run against and for a snapshot to be read back from.
--
-- **Beat-timebase tracks follow the tempo map, the way REAPER's do** (research
-- 4.1c: items on `BEAT 2` tracks were measured dragging with every tempo write,
-- and envelope points do the same). A point on such a track keeps its position
-- in quarter notes; after every tempo-marker write its time is re-derived from
-- the map. A point on a time-timebase track keeps its time. Tempo is modelled
-- as square (constant between markers), with tempo markers fixed in time
-- (`TEMPOENVLOCKMODE 0`, which Apply requires).
--
--   fake_reaper.world({
--     tempo   = { { position, bpm, timesig_num, timesig_denom }, ... },
--     regions = { { name, number, start_time, end_time }, ... },
--     markers = { { name, number, position }, ... },
--     tracks  = { [track_index] = { name, beats = bool, envelopes = {
--       [envelope_name] = { { time, value, shape, tension, selected }, ... } } } },
--   })
--
-- Returns the api; its `.world` holds `tempo`, `regions`, `markers` and
-- `tracks` (each envelope as `{ points = { { time, value, shape, tension,
-- selected, qn } } }`). `world.snapshot()` reads the state back the way
-- `lib/project.lua` shapes it. Only the calls the envelope/tempo/region
-- appliers make are modelled.
function fake_reaper.world(spec)
  local world = { tempo = {}, regions = {}, markers = {}, tracks = {} }

  for _, marker in ipairs(spec.tempo or {}) do
    world.tempo[#world.tempo + 1] = {
      position = marker.position, bpm = marker.bpm,
      timesig_num = marker.timesig_num or 4, timesig_denom = marker.timesig_denom or 4,
      lineartempo = marker.lineartempo or false,
    }
  end
  for _, region in ipairs(spec.regions or {}) do
    world.regions[#world.regions + 1] = {
      name = region.name, number = region.number,
      start_time = region.start_time, end_time = region.end_time,
    }
  end
  for _, marker in ipairs(spec.markers or {}) do
    world.markers[#world.markers + 1] = { name = marker.name, number = marker.number, position = marker.position }
  end

  local function sort_tempo()
    table.sort(world.tempo, function(a, b) return a.position < b.position end)
  end
  sort_tempo()

  -- Quarter notes at `time`, and the inverse, under square tempo.
  local function qn_at(time)
    local qn, last_time, bpm = 0, 0, world.tempo[1] and world.tempo[1].bpm or 120
    for _, marker in ipairs(world.tempo) do
      if marker.position >= time then
        break
      end
      qn = qn + (marker.position - last_time) * bpm / 60
      last_time, bpm = marker.position, marker.bpm
    end
    return qn + (time - last_time) * bpm / 60
  end

  local function time_at(qn)
    local acc, last_time, bpm = 0, 0, world.tempo[1] and world.tempo[1].bpm or 120
    for _, marker in ipairs(world.tempo) do
      local span = (marker.position - last_time) * bpm / 60
      if acc + span >= qn then
        break
      end
      acc = acc + span
      last_time, bpm = marker.position, marker.bpm
    end
    return last_time + (qn - acc) * 60 / bpm
  end

  for index, track in pairs(spec.tracks or {}) do
    local built = { name = track.name or "", beats = track.beats or false, envelopes = {} }
    for name, points in pairs(track.envelopes or {}) do
      local envelope = { points = {}, track = built }
      for _, point in ipairs(points) do
        envelope.points[#envelope.points + 1] = {
          time = point.time, value = point.value, shape = point.shape or 0,
          tension = point.tension or 0, selected = point.selected or false,
          qn = qn_at(point.time),
        }
      end
      built.envelopes[name] = envelope
    end
    world.tracks[index] = built
  end

  -- A tempo write moves beat-attached points: time is derived from the map.
  local function retime_beat_points()
    for _, track in pairs(world.tracks) do
      if track.beats then
        for _, envelope in pairs(track.envelopes) do
          for _, point in ipairs(envelope.points) do
            point.time = time_at(point.qn)
          end
        end
      end
    end
  end

  -- Stable by time, so two points at one time keep their order.
  local function sort_points(envelope)
    for index, point in ipairs(envelope.points) do
      point.order = index
    end
    table.sort(envelope.points, function(a, b)
      if a.time ~= b.time then
        return a.time < b.time
      end
      return a.order < b.order
    end)
  end

  local function set_point_time(envelope, point, time)
    point.time = time
    point.qn = envelope.track.beats and qn_at(time) or point.qn
  end

  local overrides = {
    CountTempoTimeSigMarkers = function() return #world.tempo end,
    GetTempoTimeSigMarker = function(_, idx)
      local marker = world.tempo[idx + 1]
      if not marker then
        return false
      end
      return true, marker.position, -1, -1, marker.bpm, marker.timesig_num, marker.timesig_denom,
        marker.lineartempo
    end,
    SetTempoTimeSigMarker = function(_, idx, timepos, _, _, bpm, num, denom, linear)
      local marker = world.tempo[idx + 1]
      if idx < 0 then
        marker = {}
        world.tempo[#world.tempo + 1] = marker
      end
      -- Two markers cannot share a position: the one written over is absorbed
      -- (measured, research 4.4a).
      for other_index, other in ipairs(world.tempo) do
        if other ~= marker and other.position and math.abs(other.position - timepos) < 1e-9 then
          table.remove(world.tempo, other_index)
          break
        end
      end
      marker.position, marker.bpm, marker.timesig_num, marker.timesig_denom, marker.lineartempo =
        timepos, bpm, num, denom, linear or false
      sort_tempo()
      retime_beat_points()
      return true
    end,

    GetTrack = function(_, idx) return world.tracks[idx] end,
    GetMasterTrack = function() return world.tracks[-1] end,
    GetTrackEnvelopeByName = function(track, name) return track.envelopes[name] end,
    CountEnvelopePoints = function(envelope) return #envelope.points end,
    GetEnvelopePoint = function(envelope, idx)
      local point = envelope.points[idx + 1]
      if not point then
        return false
      end
      return true, point.time, point.value, point.shape, point.tension, point.selected
    end,
    SetEnvelopePointEx = function(envelope, _, idx, time, value, shape, tension, selected, no_sort)
      local point = envelope.points[idx + 1]
      set_point_time(envelope, point, time)
      point.value, point.shape, point.tension, point.selected = value, shape, tension, selected
      if not no_sort then
        sort_points(envelope)
      end
      return true
    end,
    DeleteEnvelopePointEx = function(envelope, _, idx)
      table.remove(envelope.points, idx + 1)
      return true
    end,
    InsertEnvelopePointEx = function(envelope, _, time, value, shape, tension, selected, no_sort)
      local point = { value = value, shape = shape, tension = tension, selected = selected }
      set_point_time(envelope, point, time)
      envelope.points[#envelope.points + 1] = point
      if not no_sort then
        sort_points(envelope)
      end
      return true
    end,
    Envelope_SortPointsEx = function(envelope)
      sort_points(envelope)
      return true
    end,

    SetProjectMarker4 = function(_, number, is_region, position, region_end, name)
      for _, entry in ipairs(is_region and world.regions or world.markers) do
        if entry.number == number then
          entry.name = name
          if is_region then
            entry.start_time, entry.end_time = position, region_end
          else
            entry.position = position
          end
          return true
        end
      end
      return false
    end,
  }

  local api = fake_reaper.new(overrides)
  api.world = world

  --- The world as a lib/project.lua snapshot (no items).
  function world.snapshot()
    local snapshot = { project_path = "/proj/World.rpp", regions = {}, markers = {}, items = {},
      tempo_markers = {}, envelope_points = {} }
    for _, region in ipairs(world.regions) do
      snapshot.regions[#snapshot.regions + 1] = {
        name = region.name, number = region.number,
        start_time = region.start_time, end_time = region.end_time }
    end
    table.sort(snapshot.regions, function(a, b) return a.start_time < b.start_time end)
    for _, marker in ipairs(world.markers) do
      snapshot.markers[#snapshot.markers + 1] =
        { name = marker.name, number = marker.number, position = marker.position }
    end
    for _, marker in ipairs(world.tempo) do
      snapshot.tempo_markers[#snapshot.tempo_markers + 1] = {
        position = marker.position, bpm = marker.bpm, timesig_num = marker.timesig_num,
        timesig_denom = marker.timesig_denom, lineartempo = marker.lineartempo }
    end
    local indexes = {}
    for index in pairs(world.tracks) do
      indexes[#indexes + 1] = index
    end
    table.sort(indexes)
    for _, index in ipairs(indexes) do
      local track = world.tracks[index]
      local names = {}
      for name in pairs(track.envelopes) do
        names[#names + 1] = name
      end
      table.sort(names)
      for _, name in ipairs(names) do
        -- Read order is the envelope's own order, which is what the real
        -- reader keeps for points at one time.
        for _, point in ipairs(track.envelopes[name].points) do
          snapshot.envelope_points[#snapshot.envelope_points + 1] = {
            track_index = index, track_name = track.name, envelope_name = name,
            position = point.time, value = point.value, shape = point.shape,
            tension = point.tension, selected = point.selected }
        end
      end
    end
    -- Stable, like lib/project.lua's sort_by_position.
    for index, point in ipairs(snapshot.envelope_points) do
      point.order = index
    end
    table.sort(snapshot.envelope_points, function(a, b)
      if a.position ~= b.position then
        return a.position < b.position
      end
      return a.order < b.order
    end)
    for _, point in ipairs(snapshot.envelope_points) do
      point.order = nil
    end
    return snapshot
  end

  return api
end

return fake_reaper
