-- The real tempo oracle (ADR-0006, issue #4).
--
-- REAPER cannot run here, so what is checkable is the *translation*: that the
-- oracle reads each TimeMap return tuple in the documented order
-- (research/reaper-scripting.md §4.5) and finds the right measure regardless of
-- whether REAPER indexes measures from 0 or from 1 -- the one thing §4.5 could
-- not settle from a primary source.
--
-- The fake below is a real tempo map, not a stub: bars of 2.0s up to 32.0, then
-- 8/3s (90 bpm 4/4), then 2.0s again (90 bpm 3/4) from 48.0. That is exactly
-- spec/fixtures/repack_bars/before.rpp's grid, so these numbers and the
-- fixture's can be compared by eye.

local tempo_oracle = require("lib.tempo_oracle")

-- Bar lines of the repack_bars grid, in order, as a plain list. Built by
-- accumulating, so the spec's own arithmetic stays trivial.
local function bar_lines()
  local lines, t = {}, 0
  while t < 32 do
    lines[#lines + 1] = t
    t = t + 2
  end
  while t < 48 - 1e-9 do
    lines[#lines + 1] = t
    t = t + 8 / 3
  end
  t = 48
  while t <= 80 do
    lines[#lines + 1] = t
    t = t + 2
  end
  return lines
end

local LINES = bar_lines()

-- @param base the measure index REAPER is pretended to use for the first
--   measure -- 0 or 1. Neither primary source says which it is, so both are
--   tested and the oracle must cope with either.
local function fake_api(base)
  local calls = { TimeMap_GetMeasureInfo = 0 }

  return {
    calls = calls,

    -- Return value is the time in seconds of the measure start (§4.5).
    TimeMap_GetMeasureInfo = function(_, measure)
      calls.TimeMap_GetMeasureInfo = calls.TimeMap_GetMeasureInfo + 1
      local index = measure - base + 1
      local line = LINES[index]
      if not line then
        -- REAPER extrapolates past the last tempo marker; 3/4 at 90 continues.
        line = LINES[#LINES] + 2 * (index - #LINES)
      end
      return line
    end,

    -- retval = beats since the measure, then measures, cml, fullbeats, cdenom.
    -- Only `measures` is read by the oracle.
    TimeMap2_timeToBeats = function(_, tpos)
      local measure = base
      for index, line in ipairs(LINES) do
        if line <= tpos + 1e-9 then
          measure = base + index - 1
        end
      end
      return 0, measure, 4, 0, 4
    end,

    -- num, denom, tempo -- no retval, it is void in C (§4.5).
    TimeMap_GetTimeSigAtTime = function(_, time)
      if time >= 48 then
        return 3, 4, 90
      elseif time >= 32 then
        return 4, 4, 90
      end
      return 4, 4, 120
    end,
  }
end

describe("tempo_oracle.next_bar_at_or_after", function()
  -- The measure-index base is the one thing §4.5 could not settle. An
  -- off-by-one is silent and costs a whole bar of Padding, so both bases are
  -- required to give identical answers.
  for _, base in ipairs({ 0, 1 }) do
    describe(("with REAPER indexing measures from %d"):format(base), function()
      local oracle

      before_each(function()
        oracle = tempo_oracle.new(fake_api(base), 0)
      end)

      it("returns a time that is already on a bar line unchanged", function()
        assert.are.equal(6, oracle.next_bar_at_or_after(6))
        assert.are.equal(32, oracle.next_bar_at_or_after(32))
        assert.are.equal(48, oracle.next_bar_at_or_after(48))
      end)

      it("rounds up to the next bar line mid-bar", function()
        assert.are.equal(6, oracle.next_bar_at_or_after(5.5))
        assert.are.equal(22, oracle.next_bar_at_or_after(21))
      end)

      it("uses the tempo in effect, not a fixed bar length", function()
        -- 90 bpm 4/4 from 32.0: bars at 34.667, 37.333, 40.0.
        assert.is_true(math.abs(oracle.next_bar_at_or_after(33) - 32 - 8 / 3) < 1e-9)
        -- Compared at a tolerance because the *fake* accumulates 8/3 and lands
        -- on 39.999999999999993, not because the oracle rounds: it returns
        -- whatever REAPER hands back.
        assert.is_true(math.abs(oracle.next_bar_at_or_after(40) - 40) < 1e-9)
        -- 90 bpm 3/4 from 48.0: bars every 2.0s again.
        assert.are.equal(54, oracle.next_bar_at_or_after(53))
      end)

      it("treats a time a hair short of a bar line as already on it", function()
        -- The live project's region ends miss by up to ~1e-5s. Rounding those
        -- up bought a whole bar of silence (lib/regions.lua's pad_regions).
        assert.are.equal(6, oracle.next_bar_at_or_after(6 - 1.04e-5))
      end)

      it("treats a time a hair past a bar line as already on it", function()
        assert.are.equal(6, oracle.next_bar_at_or_after(6 + 1.04e-5))
      end)

      it("handles the timeline origin", function()
        assert.are.equal(0, oracle.next_bar_at_or_after(0))
      end)
    end)
  end

  it("does not walk the measure index indefinitely when the map makes no sense", function()
    -- A hostile API: every measure claims to start at the same time, so the
    -- bracket can never close. Hanging inside a REAPER action would freeze the
    -- DAW with no message, so this must raise instead.
    local api = {
      TimeMap_GetMeasureInfo = function() return 100 end,
      TimeMap2_timeToBeats = function() return 0, 0, 4, 0, 4 end,
    }
    local oracle = tempo_oracle.new(api, 0)

    local ok, err = pcall(oracle.next_bar_at_or_after, 5)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("could not bracket", 1, true))
  end)

  it("finds the measure even when timeToBeats' guess is far off", function()
    -- Guards the bracket search itself: if the two calls disagreed by more than
    -- a base offset, the search still has to land on the measure that actually
    -- contains the time.
    local api = fake_api(0)
    api.TimeMap2_timeToBeats = function() return 0, 0, 4, 0, 4 end

    local oracle = tempo_oracle.new(api, 0)
    assert.are.equal(6, oracle.next_bar_at_or_after(5.5))
  end)
end)

describe("tempo_oracle.bar_at_or_before", function()
  -- Both bases again: this reads the same measure bracket, so an off-by-one
  -- here resolves a Headroom to the wrong bar as silently as it would mis-Pad.
  for _, base in ipairs({ 0, 1 }) do
    describe(("with REAPER indexing measures from %d"):format(base), function()
      local oracle

      before_each(function()
        oracle = tempo_oracle.new(fake_api(base), 0)
      end)

      it("returns a time that is already on a bar line unchanged", function()
        assert.are.equal(6, oracle.bar_at_or_before(6))
        assert.are.equal(32, oracle.bar_at_or_before(32))
        assert.are.equal(48, oracle.bar_at_or_before(48))
      end)

      it("rounds down to the start of the measure a time sits in", function()
        assert.are.equal(4, oracle.bar_at_or_before(5.5))
        assert.are.equal(20, oracle.bar_at_or_before(21))
        assert.are.equal(48, oracle.bar_at_or_before(49.9))
      end)

      it("brackets the other side of next_bar_at_or_after", function()
        assert.are.equal(4, oracle.bar_at_or_before(5.5))
        assert.are.equal(6, oracle.next_bar_at_or_after(5.5))
      end)

      it("treats a time a few microseconds short of a bar line as on it", function()
        assert.are.equal(6, oracle.bar_at_or_before(6 - 1.04e-5))
      end)
    end)
  end
end)

describe("tempo_oracle.bar_after", function()
  for _, base in ipairs({ 0, 1 }) do
    describe(("with REAPER indexing measures from %d"):format(base), function()
      local oracle

      before_each(function()
        oracle = tempo_oracle.new(fake_api(base), 0)
      end)

      -- The whole reason it exists: next_bar_at_or_after cannot step off a bar
      -- line, and the one-bar floor under a shrink starts from a region start
      -- that is always on one.
      it("steps to the next line when the time is already on one", function()
        assert.are.equal(8, oracle.bar_after(6))
        assert.are.equal(0, oracle.next_bar_at_or_after(0))
        assert.are.equal(2, oracle.bar_after(0))
      end)

      it("returns the end of the measure a time sits inside", function()
        assert.are.equal(6, oracle.bar_after(5.5))
        assert.are.equal(22, oracle.bar_after(21))
      end)

      it("follows the grid across a tempo change", function()
        assert.is_true(math.abs(oracle.bar_after(32) - (32 + 8 / 3)) < 1e-9)
        assert.are.equal(50, oracle.bar_after(48))
      end)
    end)
  end
end)

describe("tempo_oracle.tempo_at", function()
  it("returns bpm first, then the time signature", function()
    local oracle = tempo_oracle.new(fake_api(0), 0)

    -- REAPER returns num, denom, tempo; plan_anchors wants bpm, num, denom.
    -- Getting this backwards would write anchors whose time signature is a
    -- tempo, so the order is asserted explicitly.
    local bpm, num, denom = oracle.tempo_at(10)
    assert.are.equal(120, bpm)
    assert.are.equal(4, num)
    assert.are.equal(4, denom)
  end)

  it("reports the tempo and signature in effect, not the project default", function()
    local oracle = tempo_oracle.new(fake_api(0), 0)

    local bpm, num, denom = oracle.tempo_at(50)
    assert.are.equal(90, bpm)
    assert.are.equal(3, num)
    assert.are.equal(4, denom)
  end)
end)
