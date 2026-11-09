-- Envelope points on a beat-timebase track follow the tempo map, exactly as
-- items do (research 4.1c), so an applier that finds a point by its old time
-- *after* rewriting the tempo map does not find it (issue 10). Real run:
-- Rehearsal_Current, every track `BEAT 2`, "could not find the envelope point
-- to move on track 12, envelope "Mute", at 275.600s".
--
-- These specs run a whole plan against `fake_reaper.world`, which models that
-- drift, and then run the same Arrangement a second time (HANDOFF.md's
-- run-it-twice rule).

local apply = require("lib.apply")
local regions = require("lib.regions")
local fake_reaper = require("spec.support.fake_reaper")

-- Every position is already a bar line: no Padding, nothing but the swap.
local NO_PADDING_ORACLE = { next_bar_at_or_after = function(time) return time end }

local TRACK = 1
local function pt(time, value)
  return { time = time, value = value, shape = 1, tension = 0, selected = false }
end

-- Alpha (120 bpm) at 0..100 and Bravo (121 bpm) at 100..200, each with a step
-- pair on its first instant and a point two seconds in.
local function world(beats)
  return fake_reaper.world({
    tempo = { { position = 0, bpm = 120 }, { position = 100, bpm = 121 } },
    regions = {
      { name = "Alpha", number = 1, start_time = 0, end_time = 100 },
      { name = "Bravo", number = 2, start_time = 100, end_time = 200 },
    },
    tracks = {
      [TRACK] = { name = "BassDI", beats = beats, envelopes = {
        Mute = { pt(0, 0), pt(0, 1), pt(2, 0), pt(100, 1), pt(100, 0), pt(102, 1) },
      } },
    },
  })
end

local function times_and_values(api)
  local out = {}
  for _, point in ipairs(api.world.tracks[TRACK].envelopes.Mute.points) do
    out[#out + 1] = ("%.6f=%g"):format(point.time, point.value)
  end
  return out
end

local function repack(api, arrangement)
  local plan = regions.plan_pack(api.world.snapshot(), arrangement, NO_PADDING_ORACLE)
  apply.plan(api, plan)
  return plan
end

describe("the fake world", function()
  it("drags a beat-timebase track's points with a tempo write, and leaves a time track's alone", function()
    local beat_api, time_api = world(true), world(false)
    for _, api in ipairs({ beat_api, time_api }) do
      api.SetTempoTimeSigMarker(0, 1, 100, -1, -1, 60, 4, 4, false)
      api.SetTempoTimeSigMarker(0, 0, 0, -1, -1, 240, 4, 4, false)
    end

    -- 4 qn at 120 bpm sat at 2 s; at 240 bpm they sit at 1 s.
    assert.is_true(math.abs(beat_api.world.tracks[TRACK].envelopes.Mute.points[3].time - 1) < 1e-9)
    assert.are.equal(2, time_api.world.tracks[TRACK].envelopes.Mute.points[3].time)
  end)
end)

describe("apply.plan on beat-timebase envelopes (issue 10)", function()
  for _, beats in ipairs({ true, false }) do
    describe(beats and "on a beat-timebase track" or "on a time-timebase track", function()
      it("swaps two regions of different tempo, every point at its planned time and step pairs in order", function()
        local api = world(beats)
        repack(api, { "Bravo", "Alpha" })

        assert.are.same({
          "0.000000=1", "0.000000=0", "2.000000=1",
          "100.000000=0", "100.000000=1", "102.000000=0",
        }, times_and_values(api))
        -- Bravo's pair (1 then 0 at 100) became (1 then 0)... checked by value order above.
      end)

      it("is a no-op the second time", function()
        local api = world(beats)
        repack(api, { "Bravo", "Alpha" })
        local after_first = times_and_values(api)
        local tempo_after_first = {}
        for _, marker in ipairs(api.world.tempo) do
          tempo_after_first[#tempo_after_first + 1] = marker.position .. "@" .. marker.bpm
        end

        local second = regions.plan_pack(api.world.snapshot(), { "Bravo", "Alpha" }, NO_PADDING_ORACLE)

        assert.is_true(second.is_empty)
        apply.plan(api, second)
        assert.are.same(after_first, times_and_values(api))
        local tempo_after_second = {}
        for _, marker in ipairs(api.world.tempo) do
          tempo_after_second[#tempo_after_second + 1] = marker.position .. "@" .. marker.bpm
        end
        assert.are.same(tempo_after_first, tempo_after_second)
      end)
    end)
  end

  -- Anchors run after the points are put back and clear their own time first,
  -- so an anchor still wins over a moved point that lands on its time.
  it("lets an Automation Anchor win at its time over a moved point", function()
    local api = world(true)
    local plan = regions.plan_pack(api.world.snapshot(), { "Bravo", "Alpha" }, NO_PADDING_ORACLE)
    plan.envelope_anchors = { { track_index = TRACK, envelope_name = "Mute", to = 2, value = 0.25, shape = 0 } }

    apply.plan(api, plan)

    local at_two = {}
    for _, point in ipairs(api.world.tracks[TRACK].envelopes.Mute.points) do
      if math.abs(point.time - 2) < 1e-9 then
        at_two[#at_two + 1] = point.value
      end
    end
    assert.are.same({ 0.25 }, at_two)
  end)

  it("moves parked envelope points the same way", function()
    local api = world(true)
    -- Only Bravo is arranged: Alpha is Parked 300 s past the Packed Block.
    local plan = repack(api, { "Bravo" })

    assert.is_true(#plan.parks > 0)
    local seen = {}
    for _, point in ipairs(api.world.tracks[TRACK].envelopes.Mute.points) do
      seen[#seen + 1] = ("%.3f"):format(point.time)
    end
    -- Bravo's three points land at 0, 0, 2; Alpha's are parked as one block.
    assert.are.equal("0.000", seen[1])
    assert.are.equal("2.000", seen[3])
    assert.are.equal(6, #seen)
    local delta = plan.parks[1].delta
    assert.are.equal(("%.3f"):format(0 + delta), seen[4])
    assert.are.equal(("%.3f"):format(2 + delta), seen[6])
  end)
end)
