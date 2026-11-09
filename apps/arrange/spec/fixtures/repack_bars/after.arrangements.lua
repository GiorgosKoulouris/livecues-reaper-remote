-- REAPER Arrangements for the repack_bars fixture.
-- Each entry is an ordered list of Region Names.
return {
  -- Timeline order. Applying this reorders nothing, so it isolates the parts of
  -- a Repack that happen regardless of order: gap closing, Padding, Tempo
  -- Anchors, cuts and drops. **Run this one first** against real REAPER -- if it
  -- misbehaves, the cause cannot be the ordering.
  ["Identity"] = {
    "Alpha",
    "Bravo",
    "Charlie",
    "Delta",
  },

  -- A real reorder, chosen so that no region keeps its position and the
  -- cumulative-sum argument of ADR-0006 is actually exercised: each region's
  -- bar grid has to come out right after a differently-tempoed region is
  -- placed in front of it.
  ["Reordered"] = {
    "Charlie",
    "Alpha",
    "Delta",
    "Bravo",
  },

  -- A subset: Charlie is omitted, so it becomes Parked Material along with
  -- everything that belongs to it (issue #7). Deliberately in timeline order
  -- otherwise, so a diff against `Identity` isolates parking from reordering.
  --
  -- Charlie was the region to omit because it is the only one carrying all
  -- four parked kinds at once: the region itself, the "verse" marker at 34,
  -- the Mute point at 33, the Keys item spanning 30..42, and the tempo marker
  -- at 32 that becomes homeless when the gap around it closes.
  ["Subset"] = {
    "Alpha",
    "Bravo",
    "Delta",
  },

  -- `Subset` with a Headroom on Bravo, and nothing else different.
  --
  -- `after.rpp` is the saved result of the `Subset` run, so applying this to it
  -- is genuinely "the next run" rather than a fresh one -- which is what makes
  -- it the case worth doing by hand. Bravo ends at 22 here after the first
  -- application and at 26 after the second, and that second move is the whole
  -- point: **Headroom is relative, so applying it twice moves twice.** The
  -- planner-side prediction is in spec/repack_bars_fixture_spec.lua; only a
  -- real run can confirm REAPER agrees.
  ["Headroom"] = {
    "Alpha",
    { "Bravo", headroom = 4 },
    "Delta",
  },
}
