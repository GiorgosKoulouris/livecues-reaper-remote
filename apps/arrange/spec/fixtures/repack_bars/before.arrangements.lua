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

  -- `Subset` with a Headroom on Bravo, and nothing else different -- so a diff
  -- against `Subset`'s result isolates the end adjustment from everything else
  -- a Repack does.
  --
  -- Bravo is the region to put it on: it is the only placed region that is
  -- Padded (21 -> 22 on the original grid), so this also exercises the rule
  -- that a Headroom is measured from the *padded* end rather than the raw one.
  -- +4 is two bars at every tempo this fixture uses, which keeps the expected
  -- arithmetic checkable by hand.
  --
  -- **This is the one arrangement here that is not idempotent.** Applying it
  -- twice moves Bravo's end twice, by design -- so a real run of it should be
  -- done deliberately, and the second run's diff is the evidence, not a
  -- regression.
  ["Headroom"] = {
    "Alpha",
    { "Bravo", headroom = 4 },
    "Delta",
  },
}
