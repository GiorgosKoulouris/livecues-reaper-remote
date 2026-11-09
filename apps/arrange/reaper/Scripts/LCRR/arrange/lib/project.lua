-- Reading project state into a plain-table snapshot.
--
-- This is the read half of the applier: the only place regions, markers and
-- items are pulled out of REAPER. Everything downstream -- validation,
-- planning, logging -- works on the table this returns, which is what lets
-- those be pure and spec-covered (ADR-0001).
--
-- The `api` table is injected rather than reached for globally, so specs drive
-- it with a fake.

local project = {}

-- REAPER is single-threaded and a runaway loop here would hang the DAW with no
-- way out, so enumeration is bounded. Far above any plausible project.
project.MAX_MARKERS = 100000

-- Which of the two region/marker readers a snapshot was taken with (issue
-- #11). Carried on the snapshot and logged, because the choice is made from
-- what the running REAPER offers rather than from anything in this repo: a
-- run that quietly fell back is a run whose `hidden` and `lane` are absent,
-- and that must be visible in the record rather than inferred from it.
project.READER_MODERN = "GetRegionOrMarker"
project.READER_LEGACY = "EnumProjectMarkers3"

-- The master track has no index in REAPER's track enumeration, but envelope
-- points read off it still need to say where they came from. -1 is the value
-- REAPER itself uses for "the master track" in several APIs, and it is
-- distinguishable from every real 0-based index.
project.MASTER_TRACK_INDEX = -1

--- The current project's .RPP path, or "" when it has never been saved.
function project.path(api)
  -- EnumProjects(-1, "") addresses the active project and returns its filename.
  -- An unsaved project yields "", which is exactly the precondition failure
  -- lib/validate.lua already reports, so the degenerate case needs no special
  -- handling here.
  local _, path = api.EnumProjects(-1, "")
  return path or ""
end

local function by_position(a, b)
  return (a.start_time or a.position) < (b.start_time or b.position)
end

-- Track timebase modes safe to reposition an item under directly, confirmed
-- by real-REAPER test (research/reaper-scripting.md §4.1c): mode `1` (beats:
-- position, length, rate) stretches an item's content when its position is
-- set directly; modes `0` (time) and `2` (beats, position only) do not. `-1`
-- (project default) is treated as unsafe too, since what it resolves to is
-- not yet confirmed.
local SAFE_TRACK_TIMEBASE = { [0] = true, [2] = true }

-- Per-item timebase overrides have no confirmed GetMediaItemInfo_Value key
-- (§4.3), so this is the only way to see one: read the item's own chunk for
-- a BEAT line. ReaTeam documents "-1" there as "use track timebase", so only
-- a literal "1" overrides an otherwise-safe track to unsafe.
local function item_beat_override(api, item)
  local ok, chunk = api.GetItemStateChunk(item, "", false)
  if not ok then
    return nil
  end
  local value = chunk:match("\n%s*BEAT (%-?%d+)")
  return value and tonumber(value) or nil
end

--- Is it safe to reposition this item directly, without stretching its content?
-- @param api table the `reaper` table
-- @param item userdata a MediaItem
-- @param track_mode number the item's track's C_BEATATTACHMODE
-- @return boolean
local function item_timebase_is_safe(api, item, track_mode)
  if not SAFE_TRACK_TIMEBASE[track_mode] then
    return false
  end
  return item_beat_override(api, item) ~= 1
end

--- Every tempo/time-signature marker in the project, ordered by position.
--
-- Read both so a run can refuse when it would strand a marker this suite
-- cannot yet carry (issue #12) and so it *can* carry the ones it does move
-- (issue #4's transplant, `lib/regions.lua`'s `tempo_moves`, `lib/apply.lua`'s
-- `apply.tempo_moves`).
--
-- `GetTempoTimeSigMarker`'s returns are, in order: retval, timepos, measurepos,
-- beatpos, bpm, timesig_num, timesig_denom, lineartempo
-- (research/reaper-scripting.md §4.4). All of them are kept now: the live
-- project has tempo ramps and partial-measure time-signature points, and a
-- transplant that drops `lineartempo` would rewrite the curve rather than move
-- it. `measurepos`/`beatpos` are carried too, though the write side does not
-- trust them across a move -- see apply.lua's comment on why it hands REAPER
-- `-1` for both instead of recomputing them here.
local function tempo_markers(api)
  local markers = {}
  for idx = 0, api.CountTempoTimeSigMarkers(0) - 1 do
    local ok, timepos, measurepos, beatpos, bpm, timesig_num, timesig_denom, lineartempo =
      api.GetTempoTimeSigMarker(0, idx)
    if ok then
      markers[#markers + 1] = {
        position = timepos,
        measurepos = measurepos,
        beatpos = beatpos,
        bpm = bpm,
        timesig_num = timesig_num,
        timesig_denom = timesig_denom,
        lineartempo = lineartempo,
      }
    end
  end
  table.sort(markers, by_position)
  return markers
end

-- `GetEnvelopeName`'s calling convention is not confirmed from the primary
-- reference (§4.4): community usage passes a buffer and reads the name back as
-- the second return, but a plain-string return is the other plausible shape.
-- The name is advisory -- it only makes a refusal message findable, exactly as
-- `track_name` does -- so both shapes are accepted rather than guessed at.
local function envelope_name(api, envelope)
  local first, second = api.GetEnvelopeName(envelope, "")
  if type(first) == "string" then
    return first
  end
  return type(second) == "string" and second or ""
end

-- REAPER exposes the project tempo map as an envelope on the master track --
-- **confirmed against REAPER 7.78/win64**, where every tempo marker in
-- `repack_basic` also arrived here, 1:1 (1 and 1 for "Sundown", 4 and 4 for
-- "What I Deserve"). It is the same data in a second view, so reading it as an
-- envelope would double-count every tempo point: harmless in a refusal, but
-- actively wrong once #4's transplant and #8's carry both write, where it
-- would move each point twice.
--
-- Skipped by name, which is the only handle REAPER offers. If a version or
-- locale ever calls it something else the points simply read as an ordinary
-- envelope again -- noisier, still refused, never silently carried twice.
local TEMPO_MAP_ENVELOPE = "Tempo map"

-- Append every automation point on one track's envelopes to `out`.
--
-- Track envelopes here means all of them, including FX parameter and bypass
-- envelopes -- the live run turned up "Bypass / ReaEQ" and
-- "Transpose / Parallax X / Utilities" alongside the usual "Volume"/"Mute".
-- All are absolute, so all are stranded by a Repack.
--
-- Take envelopes are deliberately not read: they are stored relative to their
-- take, so they travel with the item the applier already moves. Only track
-- envelopes are absolute, and only those get stranded by a Repack.
local function collect_envelope_points(api, track, track_index, track_name, out)
  for env_index = 0, api.CountTrackEnvelopes(track) - 1 do
    local envelope = api.GetTrackEnvelope(track, env_index)
    local name = envelope_name(api, envelope)
    -- The tempo map is counted already, as a tempo marker.
    local is_tempo_map = track_index == project.MASTER_TRACK_INDEX
      and name == TEMPO_MAP_ENVELOPE

    if not is_tempo_map then
      for point_index = 0, api.CountEnvelopePoints(envelope) - 1 do
        -- GetEnvelopePoint -> retval, time, value, shape, tension, selected.
        -- Everything but time is read now too (issue #8's carry): a
        -- transplant has to write the point back with its value, shape and
        -- tension unchanged, only its time moved.
        local ok, time, value, shape, tension, selected = api.GetEnvelopePoint(envelope, point_index)
        if ok then
          out[#out + 1] = {
            track_index = track_index,
            track_name = track_name,
            envelope_name = name,
            position = time,
            value = value,
            shape = shape,
            tension = tension,
            selected = selected,
          }
        end
      end
    end
  end
end

-- The handle-based region/marker family, verbatim in research §4.1d, and the
-- reason issue #11 exists: REAPER's own reference calls the enumerator this
-- suite has always used discouraged, and points here.
--
-- All four are checked before any of them is called. They are vanilla API, not
-- an extension, so on the version this suite targets (7.78) they are simply
-- present -- but they have never executed against REAPER from here, and
-- `EnumProjectMarkers3` has, on the live 19-region project. So this is a
-- preference rather than a replacement, guarded the way ADR-0001 guards an
-- extension: a build without them reads the old way instead of dying on
-- `attempt to call a nil value`.
local MODERN_READER_CALLS = {
  "GetNumRegionsOrMarkers",
  "GetRegionOrMarker",
  "GetRegionOrMarkerInfo_Value",
  "GetSetRegionOrMarkerInfo_String",
}

local function has_modern_reader(api)
  for _, name in ipairs(MODERN_READER_CALLS) do
    if type(api[name]) ~= "function" then
      return false
    end
  end
  return true
end

-- Read one region/marker off its handle.
--
-- `B_ISREGION` and `B_HIDDEN` come back through a `number`-returning call, so
-- they are 0/1 rather than booleans; they are converted here so the snapshot's
-- shape is the same one the legacy reader has always produced.
--
-- A marker reports `D_ENDPOS` equal to `D_STARTPOS` (§4.1d). That is not an
-- end time and does not become one: markers are points here, and giving one an
-- `end_time` would make it structurally indistinguishable from a zero-length
-- region to everything downstream.
local function read_handle(api, handle)
  local function value(parameter)
    return api.GetRegionOrMarkerInfo_Value(0, handle, parameter)
  end

  -- Everything comes back through a `number`-returning call, so under Lua 5.4
  -- a Region Number reads as the float `3.0` where `EnumProjectMarkers3`'s
  -- `integer` return gives `3`. That difference does not stay inside the
  -- snapshot: `validate.format_problems` renders the number with `tostring`,
  -- so a refusal would name "Region Numbers 3.0, 7.0", and `apply.places`
  -- hands the same value to `SetProjectMarker4` as a marker ID.
  local function integer(parameter)
    return math.tointeger(value(parameter)) or value(parameter)
  end
  local ok, name = api.GetSetRegionOrMarkerInfo_String(0, handle, "P_NAME", "", false)

  local entry = {
    name = (ok and name) or "",
    number = integer("I_NUMBER"),
    -- `B_HIDDEN` and `I_LANENUMBER` have no equivalent in EnumProjectMarkers3,
    -- and are the practical argument for preferring this family: a hidden
    -- region was indistinguishable from a visible one to this suite, and
    -- marker lanes invisible to it entirely. Read now, acted on by nothing
    -- yet -- a Repack still packs a hidden region like any other.
    hidden = value("B_HIDDEN") ~= 0,
    lane = integer("I_LANENUMBER"),
  }

  if value("B_ISREGION") ~= 0 then
    entry.start_time = value("D_STARTPOS")
    entry.end_time = value("D_ENDPOS")
    return entry, true
  end

  entry.position = value("D_STARTPOS")
  return entry, false
end

-- Read via the modern family. Returns nil when the read cannot be trusted,
-- which sends `snapshot` to the legacy reader.
--
-- "Get a single region or marker by internal index" says the index is stable
-- and addressable, not that `0 .. count-1` addresses every entry -- §4.1d is
-- explicit that this is unverified. If it does not, the read comes up short,
-- and a snapshot missing regions is the one failure that must never pass
-- quietly: it would plan a Repack over part of the timeline and report
-- success. So a short read is not salvaged, it is discarded.
local function read_modern(api)
  local count = math.min(api.GetNumRegionsOrMarkers(0), project.MAX_MARKERS)
  local regions, markers = {}, {}

  for index = 0, count - 1 do
    local handle = api.GetRegionOrMarker(0, index, "")
    if not handle then
      return nil
    end

    local entry, is_region = read_handle(api, handle)
    if is_region then
      regions[#regions + 1] = entry
    else
      markers[#markers + 1] = entry
    end
  end

  return regions, markers
end

-- Read via `EnumProjectMarkers3`: the discouraged call, and the proven one.
--
-- Bounded rather than looped to exhaustion because REAPER is single-threaded
-- and a runaway loop here would hang the DAW with no way out.
local function read_legacy(api)
  local regions, markers = {}, {}

  for idx = 0, project.MAX_MARKERS - 1 do
    local retval, isrgn, pos, rgnend, name, number = api.EnumProjectMarkers3(0, idx)
    if retval == 0 then
      break
    end

    if isrgn then
      regions[#regions + 1] = {
        name = name,
        number = number,
        start_time = pos,
        end_time = rgnend,
      }
    else
      markers[#markers + 1] = { name = name, number = number, position = pos }
    end
  end

  return regions, markers
end

--- Snapshot every region, marker and item in the project.
--
-- Regions and markers share one enumeration and one ID space in REAPER; `isrgn`
-- is what tells them apart, and both can sit at the same position with the same
-- name (every song in the live project does exactly that).
--
-- Read through the modern handle-based family where the build has it and
-- through `EnumProjectMarkers3` otherwise, which `region_reader` on the
-- returned table records (issue #11). Only the modern reader can see `hidden`
-- and `lane`, so those two fields are absent from a fallback snapshot rather
-- than guessed at.
--
-- Either way the whole enumeration is read before anything is returned, and
-- the result is sorted by position: neither call documents its iteration order
-- -- "by internal index" is not "in position order" (research §4.1d) -- so
-- nothing here depends on it.
--
-- Each item carries `timebase_safe`: whether repositioning it directly is
-- known not to stretch its content (research/reaper-scripting.md §4.1c/§4.3),
-- and `track_name`, so a refusal can name the track rather than only its
-- index.
-- Tempo markers and track envelope points are read too, and both now feed a
-- transplant rather than only a refusal: tempo markers issue #4's, envelope
-- points issue #8's. Envelope points carry their full shape (value, shape,
-- tension, selected), not just position, because the transplant has to write
-- the point back unchanged except for time.
--
-- @param api table the `reaper` table
-- @return table { project_path, region_reader, regions, markers, items,
--   tempo_markers, envelope_points }
function project.snapshot(api)
  local reader = project.READER_MODERN
  local regions, markers

  if has_modern_reader(api) then
    regions, markers = read_modern(api)
  end
  if not regions then
    reader = project.READER_LEGACY
    regions, markers = read_legacy(api)
  end

  table.sort(regions, by_position)
  table.sort(markers, by_position)

  local items, envelope_points = {}, {}
  for track_index = 0, api.CountTracks(0) - 1 do
    local track = api.GetTrack(0, track_index)
    local track_mode = api.GetMediaTrackInfo_Value(track, "C_BEATATTACHMODE")
    -- Carried purely so a refusal can name the track the user has to go and
    -- look at. `track_index` is 0-based, as REAPER's own track enumeration is,
    -- while its UI numbers tracks from 1 -- a message quoting the raw index
    -- sends the reader one track off. Nothing keys off the name: it is not
    -- required to be unique, and identity stays `track_index` (regions.lua).
    local _, track_name = api.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

    for item_index = 0, api.CountTrackMediaItems(track) - 1 do
      local item = api.GetTrackMediaItem(track, item_index)
      items[#items + 1] = {
        track_index = track_index,
        track_name = track_name,
        position = api.GetMediaItemInfo_Value(item, "D_POSITION"),
        length = api.GetMediaItemInfo_Value(item, "D_LENGTH"),
        timebase_safe = item_timebase_is_safe(api, item, track_mode),
      }
    end

    collect_envelope_points(api, track, track_index, track_name, envelope_points)
  end

  -- The master track carries automation like any other, and a Repack strands
  -- it just as silently. It also carries the tempo map as an envelope, which
  -- collect_envelope_points skips -- see TEMPO_MAP_ENVELOPE.
  local master = api.GetMasterTrack(0)
  if master then
    collect_envelope_points(api, master, project.MASTER_TRACK_INDEX, "Master", envelope_points)
  end

  table.sort(items, by_position)
  table.sort(envelope_points, by_position)

  return {
    project_path = project.path(api),
    region_reader = reader,
    regions = regions,
    markers = markers,
    items = items,
    tempo_markers = tempo_markers(api),
    envelope_points = envelope_points,
  }
end

--- Region Names in timeline order -- the Arrangement a Repack would reproduce
--- if the project were left exactly as it is.
function project.region_names(snapshot)
  local names = {}
  for _, region in ipairs(snapshot.regions) do
    names[#names + 1] = region.name
  end
  return names
end

return project
