-- The scenarios spec/dialog_spec.lua runs each entry script through.
--
-- Between them they reach every branch of every LCRR_Arrange_*.lua dialog
-- front end: each abort, each cancel, each prompt and each answer to it, the
-- sidecar import, both Apply paths (anchors already present, and phase 1 then
-- phase 2), and each way a run can refuse. Their transcripts are recorded in
-- spec/fixtures/dialogs/ and must not change unless the behaviour is meant to.
--
-- The projects are spec/support/projects.lua's.

local projects = require("spec.support.projects")

local merge = projects.merge
local BARS = projects.BARS
local BARS_ANCHORED = projects.BARS_ANCHORED
local BARS_DRIFTED = projects.BARS_DRIFTED
local BARS_UNSAFE = projects.BARS_UNSAFE
local BARS_PATH = projects.BARS_PATH
local BARS_SIDECAR = projects.BARS_SIDECAR
local BARS_ARRANGEMENTS = projects.BARS_ARRANGEMENTS
local bars_tempo = projects.bars_tempo
local bars_files = projects.bars_files
local PACKED = projects.PACKED
local PACKED_SIDECAR = projects.PACKED_SIDECAR
local PACKED_ARRANGEMENTS = projects.PACKED_ARRANGEMENTS
local packed_files = projects.packed_files
local EMPTY = projects.EMPTY
local DUPES = projects.DUPES
local UNSAVED_BARS = projects.UNSAVED_BARS
local RPP_TIME = projects.RPP_TIME
local RPP_BEATS = projects.RPP_BEATS

local sidecar = require("lib.sidecar")

-- The fixture sidecar is hand-written, so Capture asks before rewriting it. These
-- scenarios use its canonical rewrite to stay clear of that question.
local CANONICAL_BARS = sidecar.serialize(assert(sidecar.parse(BARS_ARRANGEMENTS)))
local canonical_files = { files = bars_files({ [BARS_SIDECAR] = CANONICAL_BARS }) }

local function name(text)
  return { GetUserInputs = { { true, text } } }
end

local function bars(answers, extra)
  return merge({ snapshots = { BARS }, tempo = bars_tempo(), files = bars_files(), answers = answers },
    extra)
end

local function packed(answers, extra)
  return merge({ snapshots = { PACKED }, files = packed_files(), answers = answers }, extra)
end

local function phased(answers, after, extra)
  return bars(answers, merge({ snapshots = { BARS, after or BARS_ANCHORED } }, extra))
end

local CANCEL = { GetUserInputs = { { false, "" } } }

return {
  ["LCRR_Arrange_FindDuplicateRegionNames.lua"] = {
    no_regions = { snapshots = { EMPTY } },
    clean = bars(),
    problems = { snapshots = { DUPES } },
    unsaved_problems = { snapshots = { merge(DUPES, { project_path = "" }) } },
  },

  ["LCRR_Arrange_ShowTrackTimebase.lua"] = {
    no_tracks = { tracks = {} },
    tracks = { tracks = {
      { name = "Gtr", mode = 0.0 },
      { name = "Keys", mode = -1.0 },
      { name = "Perc", mode = 2.0 },
      { name = "Odd", mode = 5.0 },
      { name = "Gtr 2", mode = 0.0 },
      { name = "Bass", mode = 1.0 },
    } },
  },

  ["LCRR_Arrange_ShowBarLines.lua"] = {
    no_regions = { snapshots = { EMPTY } },
    bars = bars(nil, { origin_measure = 0 }),
    packed = packed(nil, { origin_measure = 1 }),
  },

  ["LCRR_Arrange_Capture.lua"] = {
    unsaved = bars(nil, { snapshots = { UNSAVED_BARS } }),
    no_regions = { snapshots = { EMPTY } },
    bad_names = packed(nil, { snapshots = { DUPES } }),
    invalid_sidecar = bars(nil, { files = bars_files({ [BARS_SIDECAR] = "return {" }) }),
    cancelled = bars(CANCEL),
    blank_name = bars(name("   ")),
    first_capture = bars(name("  Live  "), { files = { [BARS_PATH] = RPP_TIME } }),
    new_name = bars(name("Live"), canonical_files),
    replace_yes = bars({ GetUserInputs = { { true, "Identity" } }, ShowMessageBox = { 6, 6, 1 } }),
    rewrite_yes = bars({ GetUserInputs = { { true, "Live" } }, ShowMessageBox = { 6, 1 } }),
    rewrite_no = bars({ GetUserInputs = { { true, "Live" } }, ShowMessageBox = { 7 } }),
    replace_yes_rewrite_no = bars({ GetUserInputs = { { true, "Identity" } }, ShowMessageBox = { 6, 7 } }),
    canonical_no_question = bars(name("Live"), canonical_files),
    replace_no = bars({ GetUserInputs = { { true, "Identity" } }, ShowMessageBox = { 7 } }),
    save_fails = bars(name("Live"), merge(canonical_files, { unwritable = { [BARS_SIDECAR] = true } })),
  },

  ["LCRR_Arrange_Check.lua"] = {
    no_regions = { snapshots = { EMPTY } },
    no_sidecar = bars(nil, { files = { [BARS_PATH] = RPP_TIME } }),
    unsaved = bars(nil, { snapshots = { UNSAVED_BARS } }),
    invalid_sidecar = bars(nil, { files = bars_files({ [BARS_SIDECAR] = "return {" }) }),
    cancelled = bars(CANCEL),
    unknown_name = bars(name("Nope")),
    identity = bars(name(" Identity ")),
    reordered = bars(name("Reordered")),
    subset = bars(name("Subset")),
    headroom = bars(name("Headroom")),
    empty_arrangement = bars(name("Empty"), {
      files = bars_files({ [BARS_SIDECAR] = 'return { ["Empty"] = {} }' }),
    }),
    many_refusals = bars(name("Ghost"), { files = bars_files({ [BARS_PATH] = RPP_BEATS }) }),
    unsafe_timebase = bars(name("Reordered"), { snapshots = { BARS_UNSAFE } }),
    bad_names = packed(name("Packed"), { snapshots = { DUPES } }),
    packed_exact = packed(name("Packed")),
    packed_swapped = packed(name("Swapped")),
    shrink_refused = packed(name("Shrink")),
    headroom_no_change = packed(name("Tiny")),
    unreadable_rpp = packed(name("Packed"), { files = { [PACKED_SIDECAR] = PACKED_ARRANGEMENTS } }),
  },

  ["LCRR_Arrange_Verify.lua"] = {
    no_regions = { snapshots = { EMPTY } },
    invalid_sidecar = bars(nil, { files = bars_files({ [BARS_SIDECAR] = "return {" }) }),
    unsaved = bars(nil, { snapshots = { UNSAVED_BARS } }),
    no_sidecar = bars(nil, { files = { [BARS_PATH] = RPP_TIME } }),
    empty_sidecar = bars(nil, { files = bars_files({ [BARS_SIDECAR] = "return {}" }) }),
    cancelled = bars(CANCEL),
    unknown_name = bars(name("Nope")),
    pass = packed(name("Packed")),
    order = packed(name("Swapped")),
    absent = packed(name("Ghost")),
    gaps = bars(name("Identity")),
    not_parked = bars(name("Subset")),
  },

  ["LCRR_Arrange_Apply.lua"] = {
    unsaved = bars(nil, { snapshots = { UNSAVED_BARS } }),
    tempo_beats = bars(nil, { files = bars_files({ [BARS_PATH] = RPP_BEATS }) }),
    no_regions = { snapshots = { EMPTY }, files = { ["/proj/Empty.rpp"] = RPP_TIME } },
    bad_names = packed(nil, { snapshots = { DUPES } }),
    invalid_sidecar = bars(nil, { files = bars_files({ [BARS_SIDECAR] = "return {" }) }),
    import_declined = bars({ ShowMessageBox = { 7 } }, { files = { [BARS_PATH] = RPP_TIME } }),
    import_picker_cancelled = bars({ ShowMessageBox = { 6 } }, { files = { [BARS_PATH] = RPP_TIME } }),
    import_unreadable = bars({
      ShowMessageBox = { 6 },
      GetUserFileNameForRead = { { true, "/elsewhere/missing.lua" } },
    }, { files = { [BARS_PATH] = RPP_TIME } }),
    import_invalid = bars({
      ShowMessageBox = { 6 },
      GetUserFileNameForRead = { { true, "/elsewhere/bad.lua" } },
    }, { files = { [BARS_PATH] = RPP_TIME, ["/elsewhere/bad.lua"] = "return 5" } }),
    import_save_fails = bars({
      ShowMessageBox = { 6 },
      GetUserFileNameForRead = { { true, "/elsewhere/good.lua" } },
    }, {
      files = { [BARS_PATH] = RPP_TIME, ["/elsewhere/good.lua"] = BARS_ARRANGEMENTS },
      unwritable = { [BARS_SIDECAR] = true },
    }),
    import_empty = bars({
      ShowMessageBox = { 6 },
      GetUserFileNameForRead = { { true, "/elsewhere/empty.lua" } },
    }, { files = { [BARS_PATH] = RPP_TIME, ["/elsewhere/empty.lua"] = "return {}" } }),
    import_then_apply = phased({
      ShowMessageBox = { 6, 1 },
      GetUserFileNameForRead = { { true, "/elsewhere/good.lua" } },
      GetUserInputs = { { true, "Identity" } },
    }, nil, { files = { [BARS_PATH] = RPP_TIME, ["/elsewhere/good.lua"] = BARS_ARRANGEMENTS } }),
    empty_sidecar = bars(nil, { files = bars_files({ [BARS_SIDECAR] = "return {}" }) }),
    cancelled = bars(CANCEL),
    unknown_name = bars(name("Nope")),
    missing_regions = bars(name("Ghost")),
    headroom_cancel = bars({ GetUserInputs = { { true, "Headroom" } }, ShowMessageBox = { 2 } }),
    headroom_closed = bars({ GetUserInputs = { { true, "Headroom" } }, ShowMessageBox = { 0 } }),
    headroom_no = phased({ GetUserInputs = { { true, "Headroom" } }, ShowMessageBox = { 7, 1 } }),
    headroom_yes = phased({ GetUserInputs = { { true, "Headroom" } }, ShowMessageBox = { 6, 1 } }),
    reordered = phased(name("Reordered")),
    subset = phased(name("Subset")),
    drifted = phased(name("Reordered"), BARS_DRIFTED),
    phase_two_refused = phased({ GetUserInputs = { { true, "Shrink" } }, ShowMessageBox = { 6, 1 } }),
    already_matches = packed(name("Packed")),
    anchors_present_moves = packed(name("Swapped")),
    anchors_present_refused = packed({ GetUserInputs = { { true, "Shrink" } },
      ShowMessageBox = { 6, 1 } }),
    headroom_no_change = packed({ GetUserInputs = { { true, "Tiny" } }, ShowMessageBox = { 6, 1 } }),
  },
}
