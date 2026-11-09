-- Small REAPER projects, as lib/project.lua snapshots, shared by the core
-- specs and the dialog transcripts.
--
-- `BARS` is spec/fixtures/repack_bars transcribed (see
-- spec/repack_bars_fixture_spec.lua), with its bar grid in `bars_tempo`;
-- `PACKED` is a project a Repack has already laid down, so every Tempo Anchor
-- is present. The `*_ARRANGEMENTS` strings are their sidecars, and `RPP_TIME`
-- / `RPP_BEATS` stand in for the .RPP text Apply and Check read.

local harness = require("spec.support.script_harness")

local function merge(base, changes)
  local out = {}
  for key, value in pairs(base) do
    out[key] = value
  end
  for key, value in pairs(changes or {}) do
    out[key] = value
  end
  return out
end

local function item(position, length, track_index, track_name, safe)
  return { position = position, length = length, track_index = track_index,
    track_name = track_name, timebase_safe = safe ~= false }
end

local function point(position, value)
  return { position = position, track_index = 0, track_name = "Gtr", envelope_name = "Mute",
    value = value, shape = 1, tension = 0, selected = false }
end

local function tempo_marker(position, bpm, num, denom)
  return { position = position, bpm = bpm, timesig_num = num, timesig_denom = denom,
    lineartempo = false }
end

local BARS_PATH = "/proj/Bars.rpp"
local BARS_SIDECAR = "/proj/Bars.arrangements.lua"

local BARS = {
  project_path = BARS_PATH,
  region_reader = "GetRegionOrMarker",
  regions = {
    { name = "Alpha", number = 1, start_time = 0, end_time = 8 },
    { name = "Bravo", number = 2, start_time = 12, end_time = 21 },
    { name = "Charlie", number = 3, start_time = 32, end_time = 40 },
    { name = "Delta", number = 4, start_time = 48, end_time = 53 },
  },
  markers = {
    { name = "Alpha", number = 5, position = 0 },
    { name = "verse", number = 6, position = 34 },
  },
  items = {
    item(2, 2, 0, "Gtr"),
    item(11, 3, 0, "Gtr"),
    item(30, 12, 1, "Keys"),
    item(9, 1, 2, "Perc"),
    item(49, 2, 2, "Perc"),
  },
  tempo_markers = {
    tempo_marker(0, 120, 4, 4),
    tempo_marker(32, 90, 4, 4),
    tempo_marker(48, 90, 3, 4),
  },
  envelope_points = { point(1, 1), point(3, 0), point(9.5, 1), point(33, 0) },
}

-- After phase 1: the one anchor the fixture lacks (Bravo's start) is present.
local BARS_ANCHORED = merge(BARS, {
  tempo_markers = {
    tempo_marker(0, 120, 4, 4),
    tempo_marker(12, 120, 4, 4),
    tempo_marker(32, 90, 4, 4),
    tempo_marker(48, 90, 3, 4),
  },
})

-- After phase 1, with the Gtr item at 11 dragged by the tempo edit.
local BARS_DRIFTED = merge(BARS_ANCHORED, {
  items = {
    item(2, 2, 0, "Gtr"),
    item(11.5, 3, 0, "Gtr"),
    item(30, 12, 1, "Keys"),
    item(9, 1, 2, "Perc"),
    item(49, 2, 2, "Perc"),
  },
})

local BARS_UNSAFE = merge(BARS, {
  items = {
    item(2, 2, 0, "Gtr"),
    item(11, 3, 0, "Gtr"),
    item(30, 12, 1, "Keys"),
    item(9, 1, 2, "Perc"),
    item(49, 2, 2, "Perc", false),
  },
})

local function bars_tempo()
  local lines, t = {}, 0
  while t < 32 - 1e-9 do
    lines[#lines + 1] = t
    t = t + 2
  end
  t = 32
  while t < 48 - 1e-9 do
    lines[#lines + 1] = t
    t = t + 8 / 3
  end
  t = 48
  while t <= 200 do
    lines[#lines + 1] = t
    t = t + 2
  end
  return harness.grid_oracle(lines, function(time)
    if time >= 48 - 1e-9 then
      return 90, 3, 4
    elseif time >= 32 - 1e-9 then
      return 90, 4, 4
    end
    return 120, 4, 4
  end)
end

local BARS_ARRANGEMENTS = [[
return {
  ["Identity"] = { "Alpha", "Bravo", "Charlie", "Delta" },
  ["Reordered"] = { "Charlie", "Alpha", "Delta", "Bravo" },
  ["Subset"] = { "Alpha", "Bravo", "Delta" },
  ["Headroom"] = { "Alpha", { "Bravo", headroom = 4 }, "Delta" },
  ["Shrink"] = { "Alpha", { "Bravo", headroom = -20 }, "Delta" },
  ["Ghost"] = { "Alpha", "Zulu" },
}
]]

local RPP_TIME = "<REAPER_PROJECT 0.1\n  TEMPOENVLOCKMODE 0\n>\n"
local RPP_BEATS = "<REAPER_PROJECT 0.1\n  TEMPOENVLOCKMODE 1\n>\n"

local function bars_files(changes)
  return merge({ [BARS_PATH] = RPP_TIME, [BARS_SIDECAR] = BARS_ARRANGEMENTS }, changes)
end

local PACKED_PATH = "/proj/Packed.rpp"
local PACKED_SIDECAR = "/proj/Packed.arrangements.lua"

local PACKED = {
  project_path = PACKED_PATH,
  region_reader = "EnumProjectMarkers3",
  regions = {
    { name = "A", number = 1, start_time = 0, end_time = 8 },
    { name = "B", number = 2, start_time = 8, end_time = 16 },
  },
  markers = {},
  items = { item(2, 2, 0, "Gtr") },
  tempo_markers = { tempo_marker(0, 120, 4, 4), tempo_marker(8, 120, 4, 4) },
  envelope_points = {},
}

local PACKED_ARRANGEMENTS = [[
return {
  ["Packed"] = { "A", "B" },
  ["Swapped"] = { "B", "A" },
  ["Shrink"] = { "A", { "B", headroom = -8 } },
  ["Tiny"] = { "A", { "B", headroom = 0.5 } },
  ["Ghost"] = { "A", "Z" },
}
]]

local function packed_files(changes)
  return merge({ [PACKED_PATH] = RPP_TIME, [PACKED_SIDECAR] = PACKED_ARRANGEMENTS }, changes)
end

local EMPTY = {
  project_path = "/proj/Empty.rpp",
  region_reader = "GetRegionOrMarker",
  regions = {}, markers = {}, items = {}, tempo_markers = {}, envelope_points = {},
}

local DUPES = merge(PACKED, {
  regions = {
    { name = "A", number = 1, start_time = 0, end_time = 8 },
    { name = "A", number = 2, start_time = 8, end_time = 16 },
    { name = "", number = 3, start_time = 16, end_time = 24 },
  },
})

local UNSAVED_BARS = merge(BARS, { project_path = "" })

return {
  merge = merge,
  BARS = BARS,
  BARS_ANCHORED = BARS_ANCHORED,
  BARS_DRIFTED = BARS_DRIFTED,
  BARS_UNSAFE = BARS_UNSAFE,
  BARS_PATH = BARS_PATH,
  BARS_SIDECAR = BARS_SIDECAR,
  BARS_ARRANGEMENTS = BARS_ARRANGEMENTS,
  bars_tempo = bars_tempo,
  bars_files = bars_files,
  PACKED = PACKED,
  PACKED_PATH = PACKED_PATH,
  PACKED_SIDECAR = PACKED_SIDECAR,
  PACKED_ARRANGEMENTS = PACKED_ARRANGEMENTS,
  packed_files = packed_files,
  EMPTY = EMPTY,
  DUPES = DUPES,
  UNSAVED_BARS = UNSAVED_BARS,
  RPP_TIME = RPP_TIME,
  RPP_BEATS = RPP_BEATS,
}
