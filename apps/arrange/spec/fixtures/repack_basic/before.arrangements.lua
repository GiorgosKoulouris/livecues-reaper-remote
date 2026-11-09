-- REAPER Arrangements. Each entry is an ordered list of Region Names.
-- Edit freely; this file is read in a sandbox and validated on load.
--
-- The header below is restored by hand after every `TSB_CaptureRegionOrder`
-- run on this project, which rewrites the whole file and takes the comments
-- with it. Nothing is wrong when that happens -- but the entries it explains
-- are test input, so the explanation has to come back.
--
-- Two entries, and the distinction matters (ADR-0005). A third, `live`, is the
-- Arrangement the verified runs of 2026-08-05 applied; it lives in the sidecar
-- beside the scratch copy those runs were made on, not here.
--
-- `ORIG` is the tracked baseline. It is timeline order with two adjacent pairs
-- transposed -- Sleep Tight <-> Darkness of Blue, and NES_19 <-> NES_11 -- and
-- `spec/apply_arrangement_fixture_spec.lua` asserts against exactly that. It is
-- hand-written test input, not a capture, so a live `TSB_CaptureRegionOrder` run
-- must not overwrite it. One did: the entry went missing and the fixture spec
-- errored with "fixture sidecar has no 'ORIG' arrangement" until it was restored
-- here. Capture writes beside the project it ran on, which for a scratch run is
-- `after.arrangements.lua` -- keep it that way.
--
-- `Captured` is what a real `TSB_CaptureRegionOrder` run recorded from the live
-- project, kept because it is real data. It is plain timeline order, so applying
-- it Repacks (closes the gaps) without reordering anything.
return {
  ["Captured"] = {
    "Sleep Tight",
    "Darkness of Blue",
    "NES_15",
    "Intro",
    "Sundown",
    "What I Deserve",
    "I'm gonna tell God everything",
    "Payback",
    "Prophets",
    "Low Fall",
    "NES 16",
    "SoFarGone",
    "The pain you leave behind",
    "The distance that happens",
    "Dear Youth",
    "Maze",
    "NES_19",
    "NES_11",
    "NES_22",
  },
  ["ORIG"] = {
    "Darkness of Blue",
    "Sleep Tight",
    "NES_15",
    "Intro",
    "Sundown",
    "What I Deserve",
    "I'm gonna tell God everything",
    "Payback",
    "Prophets",
    "Low Fall",
    "NES 16",
    "SoFarGone",
    "The pain you leave behind",
    "The distance that happens",
    "Dear Youth",
    "Maze",
    "NES_11",
    "NES_19",
    "NES_22",
  },
}
