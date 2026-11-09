-- The planner's prediction for `repack_bars` under the `Reordered` and
-- `Subset` Arrangements.
--
-- ADR-0005's third artefact, and the one that looks redundant beside `after.rpp`
-- and is not: `after.rpp` records what REAPER did, this records what the planner
-- said it would do, and the pair is the proof. A spec
-- (`spec/repack_bars_fixture_spec.lua`) asserts the planner reproduces this
-- exactly; a human compares it against `after.rpp` once a real run exists.
--
-- Every number here was derived by hand from the fixture's grid -- see
-- README.md, which tabulates the bar lines. Nothing was copied out of a plan the
-- planner produced, which is the whole point: a prediction copied from the
-- thing it predicts proves nothing.
--
--   Bar lines: every 2.0s to 32.0 (120 bpm 4/4), then every 8/3s (90 bpm 4/4),
--   then every 2.0s from 48.0 (90 bpm 3/4).
--
--   Bounds after Padding: Alpha 0..8, Bravo 12..22, Charlie 32..40, Delta 48..54.
--   Packed in Reordered order (Charlie, Alpha, Delta, Bravo), lengths 8, 8, 6, 10:
--   cursor 0 -> 8 -> 16 -> 22 -> 32.
--
-- Note every destination lands on a bar line of the *new* timeline, which is
-- ADR-0006's cumulative-sum argument holding: Charlie's 3 bars of 90 bpm fill
-- 0..8, so Alpha starts on a bar line at 8.0 without anyone computing one.

return {
  -- Phase 1. Values are the tempo/signature in effect at each region start.
  -- Three of the four coincide with an existing tempo marker carrying the same
  -- values, so only Bravo's is a change -- which is why `changing` is 1 and the
  -- run still takes the two-phase path.
  anchors = {
    { time = 0, region_name = "Alpha", bpm = 120, timesig_num = 4, timesig_denom = 4,
      lineartempo = false, redundant = true },
    { time = 12, region_name = "Bravo", bpm = 120, timesig_num = 4, timesig_denom = 4,
      lineartempo = false, redundant = false },
    { time = 32, region_name = "Charlie", bpm = 90, timesig_num = 4, timesig_denom = 4,
      lineartempo = false, redundant = true },
    { time = 48, region_name = "Delta", bpm = 90, timesig_num = 3, timesig_denom = 4,
      lineartempo = false, redundant = true },
  },
  anchors_changing = 1,

  -- Phase 2. Bravo is 4.5 bars at 120 (2.0s bars), Delta 2.5 bars at 90 3/4
  -- (2.0s bars); the other two are whole numbers of bars and are absent.
  pads = {
    { name = "Bravo", from_end = 21, to_end = 22, added = 1 },
    { name = "Delta", from_end = 53, to_end = 54, added = 1 },
  },

  -- In Arrangement order, which is the order plan_pack emits them.
  places = {
    { name = "Charlie", from_start = 32, to_start = 0, delta = -32, length = 8 },
    { name = "Alpha", from_start = 0, to_start = 8, delta = 8, length = 8 },
    { name = "Delta", from_start = 48, to_start = 16, delta = -32, length = 6 },
    { name = "Bravo", from_start = 12, to_start = 22, delta = 10, length = 10 },
  },

  -- One cut at Bravo's start (the Gtr item crossing it) and two at Charlie's
  -- bounds (the Keys item covering the whole region -- ADR-0002 grants no
  -- exemption for that).
  splits = {
    { track_index = 0, position = 12 },
    { track_index = 1, position = 32 },
    { track_index = 1, position = 40 },
  },

  -- Material touching no region: the two tails the cuts leave, the tail before
  -- Charlie, and the Loose Item that was already lying in a gap.
  drops = {
    { track_index = 0, position = 11, length = 1 },
    { track_index = 1, position = 30, length = 2 },
    { track_index = 1, position = 40, length = 2 },
    { track_index = 2, position = 9, length = 1 },
  },

  item_moves = {
    { track_index = 0, from = 2, to = 10, delta = 8 },
    { track_index = 0, from = 12, to = 22, delta = 10 },
    { track_index = 1, from = 32, to = 0, delta = -32 },
    { track_index = 2, from = 49, to = 17, delta = -32 },
  },

  -- "Alpha" sits at its region's start, "verse" 2.0s inside Charlie. Both travel
  -- with their region; the second is here because marker carrying must not be
  -- coupled to region starts.
  marker_moves = {
    { name = "Alpha", from = 0, to = 8, delta = 8 },
    { name = "verse", from = 34, to = 2, delta = -32 },
  },

  -- Each region's tempo slice travels with it. None is homeless, so none parks.
  tempo_moves = {
    { from = 0, to = 8, delta = 8, region_name = "Alpha" },
    { from = 32, to = 0, delta = -32, region_name = "Charlie" },
    { from = 48, to = 16, delta = -32, region_name = "Delta" },
  },

  envelope_moves = {
    { track_index = 0, envelope_name = "Mute", from = 1, to = 9, delta = 8 },
    { track_index = 0, envelope_name = "Mute", from = 3, to = 11, delta = 8 },
    { track_index = 0, envelope_name = "Mute", from = 33, to = 1, delta = -32 },
  },

  -- The point at 9.5 is in the gap between Alpha and Bravo, so it touches no
  -- region and is discarded (Dropped Material, not parked -- ADR-0006's #8
  -- amendment).
  envelope_drops = {
    { track_index = 0, envelope_name = "Mute", position = 9.5 },
  },

  -- Two per placed region, both bounds, square, carrying the last *authored*
  -- value at that bound. Alpha's start has no point at or before it, so its
  -- value comes from the automation oracle (the envelope's own default).
  -- Positions are final, after the region's delta.
  --
  -- Note 8.0 appears twice -- Alpha's end anchor and, at 8.0 in the new
  -- timeline, nothing else; but Charlie's end (40 - 32 = 8) lands there too.
  -- Two anchors on one time is a step, which is what a region change wants, not
  -- a duplicate.
  envelope_anchors = {
    { region_name = "Charlie", edge = "start", to = 0, value = 1 },
    { region_name = "Charlie", edge = "end", to = 8, value = 0 },
    { region_name = "Alpha", edge = "start", to = 8, value = "oracle" },
    { region_name = "Alpha", edge = "end", to = 16, value = 0 },
    { region_name = "Delta", edge = "start", to = 16, value = 0 },
    { region_name = "Delta", edge = "end", to = 22, value = 0 },
    { region_name = "Bravo", edge = "start", to = 22, value = 1 },
    { region_name = "Bravo", edge = "end", to = 32, value = 1 },
  },

  -- Nothing is omitted from the Arrangement and no marker is homeless, so the
  -- run has no Parked Material and validate.plan_is_region_move_only passes.
  parks = {},

  packed_end = 32,

  -- ==========================================================================
  -- The `Subset` Arrangement: Alpha, Bravo, Delta -- Charlie omitted (issue #7)
  -- ==========================================================================
  --
  -- Derived by hand from the same grid, as above. What makes this worth having
  -- alongside `Reordered` is that omitting Charlie changes the *classification*
  -- of five things rather than just their destinations:
  --
  --   * the Keys item spanning 30..42 is no longer cut, because cuts happen at
  --     the bounds of *moving* regions and Charlie is not one. It parks whole.
  --   * the "verse" marker at 34 parks instead of travelling.
  --   * the Mute point at 33 parks instead of travelling.
  --   * the tempo marker at 32 becomes homeless and parks (ADR-0006's #4
  --     amendment), so it appears in `tempo_moves` with `kind = "park"` rather
  --     than in `parks` -- it is the one parked category written this run.
  --   * Alpha does not move at all (delta 0), so it is absent from `places`,
  --     `item_moves`, `marker_moves` and `tempo_moves` alike.
  --
  --   Bounds after Padding: Alpha 0..8, Bravo 12..22, Delta 48..54. Charlie is
  --   not padded -- Padding keeps the Packed Block bar-aligned, and Charlie is
  --   not in it.
  --   Packed in Subset order, lengths 8, 10, 6: cursor 0 -> 8 -> 18 -> 24.
  subset = {
    -- Identical to `anchors` above, and that is the point: phase 1 anchors
    -- every region in the project, Charlie included, even though no
    -- Arrangement places it. Phase 2 then parks that anchor along with the
    -- region, so a parked region keeps its own tempo rather than inheriting
    -- the Packed Block's (lib/apply.lua's split_parks).
    anchors_changing = 1,

    pads = {
      { name = "Bravo", from_end = 21, to_end = 22, added = 1 },
      { name = "Delta", from_end = 53, to_end = 54, added = 1 },
    },

    -- Alpha is absent: it starts at the origin already and is a whole number
    -- of bars, so neither bound changes.
    places = {
      { name = "Bravo", from_start = 12, to_start = 8, delta = -4, length = 10 },
      { name = "Delta", from_start = 48, to_start = 18, delta = -30, length = 6 },
    },

    -- Only Bravo's start is straddled. Charlie's bounds are not cut at, which
    -- is the difference from `Reordered` that matters most here.
    splits = {
      { track_index = 0, position = 12 },
    },

    -- The tail the cut leaves in the 8..12 gap, and the Loose Item already
    -- lying in it. The two Charlie tails of `Reordered` are absent because no
    -- cut created them.
    drops = {
      { track_index = 0, position = 11, length = 1 },
      { track_index = 2, position = 9, length = 1 },
    },

    item_moves = {
      { track_index = 0, from = 12, to = 8, delta = -4 },
      { track_index = 2, from = 49, to = 19, delta = -30 },
    },

    -- "Alpha" is inside a region that does not move; "verse" parks. So nothing
    -- is carried, which is not the same as nothing happening to either.
    marker_moves = {},

    -- Delta's slice travels; the marker at 32 is homeless and parks by
    -- park_delta (294), landing at 326. The marker at 0 is inside Alpha, which
    -- does not move.
    --
    -- **Bravo has no entry**, which is worth stating because it looks like a
    -- gap: the fixture's tempo map has markers at 0, 32 and 48 only, and the
    -- one at Bravo's start is written by *phase 1*. This prediction is against
    -- the pre-anchor snapshot, exactly as the `Reordered` block above is, so
    -- Bravo has no slice to transplant here. In a real run phase 2 re-reads the
    -- project and does move it.
    tempo_moves = {
      { from = 48, to = 18, delta = -30, region_name = "Delta" },
      { from = 32, to = 326, delta = 294, kind = "park" },
    },

    -- The points at 1 and 3 are inside Alpha, which does not move; the point
    -- at 33 parks. So nothing is carried.
    envelope_moves = {},

    envelope_drops = {
      { track_index = 0, envelope_name = "Mute", position = 9.5 },
    },

    -- Two per placed region, at final positions. Bravo's value comes from the
    -- point at 9.5 -- which this same run *drops* -- and Delta's from the
    -- point at 33, which this same run *parks*. Both are ADR-0006's claim that
    -- anchors are evaluated before anything moves, so neither the drop nor the
    -- park is lossy.
    envelope_anchors = {
      { region_name = "Alpha", edge = "start", to = 0, value = "oracle" },
      { region_name = "Alpha", edge = "end", to = 8, value = 0 },
      { region_name = "Bravo", edge = "start", to = 8, value = 1 },
      { region_name = "Bravo", edge = "end", to = 18, value = 1 },
      { region_name = "Delta", edge = "start", to = 18, value = 0 },
      { region_name = "Delta", edge = "end", to = 24, value = 0 },
    },

    -- packed_end 24 + PARK_GAP 300 = 324; the earliest parked thing is the
    -- Keys item at 30, so the shared offset is 324 - 30 = 294. Everything below
    -- moves by exactly that, which is what keeps the internal timing intact:
    -- the marker stays 2.0s inside the region, the point 1.0s inside it.
    park_delta = 294,
    parks = {
      { kind = "region", name = "Charlie", from = 32, to = 326, length = 8 },
      { kind = "envelope", envelope_name = "Mute", from = 33, to = 327 },
      { kind = "marker", name = "verse", from = 34, to = 328 },
      { kind = "item", track_index = 1, from = 30, to = 324 },
    },

    packed_end = 24,
  },
}
