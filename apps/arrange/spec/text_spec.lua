-- The wording the dialog front ends show, from structured results.
--
-- spec/dialog_spec.lua pins every sentence byte for byte. This spec keeps the
-- few properties of the wording that are decisions rather than phrasing --
-- chiefly that Headroom announces itself as relative, which is the whole of
-- ADR-0007's guard -- so they read as requirements rather than as a diff.

local check_text = require("lib.text.check")
local verify_text = require("lib.text.verify")
local apply_text = require("lib.text.apply")

describe("lib/text/apply.lua headroom_prompt", function()
  local requests = {
    { name = "Chorus", seconds = 4 },
    { name = "Intro", seconds = -2 },
  }

  it("lists each region and what it will gain or lose, in the order given", function()
    local message = apply_text.headroom_prompt(requests)

    assert.is_truthy(message:find("Intro: -2.0 s", 1, true))
    assert.is_truthy(message:find("Chorus: +4.0 s", 1, true))
    assert.is_true(message:find("Chorus", 1, true) < message:find("Intro", 1, true))
  end)

  -- The one non-idempotent operation in the suite has to announce itself: this
  -- prompt is the whole of the compensating guard.
  it("says that Headroom is relative", function()
    local message = apply_text.headroom_prompt(requests)
    assert.is_truthy(message:find("Each Apply moves these region ends again.", 1, true))
  end)

  it("shows 8 names, then how many more and where to see them", function()
    local many = {}
    for index = 1, 10 do
      many[index] = { name = "R" .. index, seconds = 1 }
    end
    local message = apply_text.headroom_prompt(many)
    assert.is_truthy(message:find("R8", 1, true))
    assert.is_falsy(message:find("R9", 1, true))
    assert.is_truthy(message:find("and 2 more (see the Arrange page's Edit tab)", 1, true))
  end)

  it("offers all three answers", function()
    local message = apply_text.headroom_prompt(requests)
    assert.is_truthy(message:find("Yes", 1, true))
    assert.is_truthy(message:find("No", 1, true))
    assert.is_truthy(message:find("Cancel", 1, true))
  end)
end)

describe("lib/text/apply.lua error", function()
  it("says a refusal after phase 1 left changes that Ctrl+Z removes", function()
    local message = apply_text.error({ code = "plan_refused", reason = "region_overlap", region = "A",
      next_region = "B", anchors_written = 3 })
    assert.is_truthy(message:find('^"A" ends after "B" starts%.'))
    assert.is_truthy(message:find("Press Ctrl+Z in REAPER to remove the changes made so far.", 1, true))
    assert.is_falsy(message:find("Tempo Anchor", 1, true))
  end)

  it("says nothing about undo when nothing was written", function()
    local message = apply_text.error({ code = "plan_refused", reason = "region_overlap", region = "A",
      next_region = "B" })
    assert.is_falsy(message:find("Ctrl+Z", 1, true))
  end)

  it("words a moved-items refusal with track numbers from 1 and times to one decimal", function()
    local message = apply_text.error({ code = "anchors_moved_items", anchors_written = 2,
      moved = { { track_index = 0, from = 11, to = 11.5 } } })
    assert.is_truthy(message:find("track 1 at 11.0 s", 1, true))
    -- Said once, not repeated by the generic suffix.
    local _, count = message:gsub("Ctrl%+Z", "")
    assert.are.equal(1, count)
  end)

  it("caps a long list at 8 names and says how many more", function()
    local missing = {}
    for index = 1, 11 do
      missing[index] = "R" .. index
    end
    local message = apply_text.error({ code = "arrangement_missing_regions", name = "X", missing = missing })
    assert.is_truthy(message:find("R8", 1, true))
    assert.is_falsy(message:find("R9", 1, true))
    assert.is_truthy(message:find("and 3 more (see the run log)", 1, true))
  end)

  it("words the unexpected failure plainly, with Undo", function()
    local message = apply_text.failure()
    assert.is_truthy(message:find("Apply stopped partway. Press Ctrl+Z", 1, true))
  end)

  it("never shows a code label, sidecar, a script path or an API name", function()
    local errors = {
      { code = "project_unsaved" }, { code = "tempo_env_beats" }, { code = "no_regions" },
      { code = "sidecar_invalid", error = "bad" }, { code = "sidecar_missing" },
      { code = "internal" }, { code = "no_reply" }, { code = "bad_request" },
      { code = "plan_refused", reason = "headroom", problems = {
        { kind = "shrink_too_far", name = "B", requested = -20, most = 8 }, { kind = "too_large", name = "C" } } },
      { code = "plan_refused", reason = "items_unsafe", items = { { track_index = 2, position = 12 } } },
      { code = "plan_refused", reason = "planner_bug" }, { code = "plan_out_of_scope", name = "X" },
    }
    for _, err in ipairs(errors) do
      local message = apply_text.error(err)
      assert.is_falsy(message:lower():find("sidecar", 1, true), message)
      assert.is_falsy(message:find("%.lua"), message)
      assert.is_falsy(message:find("[%w]+_[%w_]+"), message)
    end
  end)

  it("words every refusal the core can return", function()
    for _, err in ipairs({
      { code = "project_unsaved" },
      { code = "tempo_env_beats" },
      { code = "no_regions" },
      { code = "region_names", problems = {} },
      { code = "sidecar_invalid", error = "e" },
      { code = "sidecar_missing" },
      { code = "import_unreadable", path = "p" },
      { code = "import_invalid", path = "p", error = "e" },
      { code = "save_failed", error = "e" },
      { code = "no_arrangements" },
      { code = "arrangement_unknown", name = "n", available = {} },
      { code = "arrangement_missing_regions", name = "n", missing = {} },
      { code = "plan_refused", reason = "planner_bug" },
      { code = "plan_out_of_scope", name = "n", error = "e" },
      { code = "anchors_moved_items", moved = {} },
    }) do
      assert.are_not.equal(err.code, apply_text.error(err), err.code .. " has no wording")
    end
  end)
end)

describe("lib/text/check.lua", function()
  it("says outright that Headroom is relative", function()
    local sentence = check_text.finding({ code = "headroom", headroom = {
      { name = "Verse", requested = 20, resolved = 20, bars = 2, from_end = 30, to_end = 50 },
    } })
    assert.is_truthy(sentence:lower():find("relative", 1, true))
  end)

  -- The likeliest "nothing happened" is a request under half a bar, and a
  -- region quietly missing from the report reads as a check that did not
  -- notice the edit.
  it("names a Headroom request that resolved to no change", function()
    local sentence = check_text.finding({ code = "headroom", headroom = {
      { name = "Verse", requested = 2, resolved = 0, bars = 0, from_end = 30, to_end = 30 },
    } })
    assert.is_truthy(sentence:find("Verse", 1, true))
    assert.is_truthy(sentence:find("NO CHANGE", 1, true))
  end)

  it("words every blind spot", function()
    for _, code in ipairs({ "padding_grid", "anchor_drift", "padding_overlap" }) do
      assert.are_not.equal(code, check_text.blind_spot(code))
    end
  end)
end)

describe("lib/text/verify.lua", function()
  it("words its blind spot, which is about Headroom", function()
    assert.is_truthy(verify_text.blind_spot("headroom_count"):find("Headroom", 1, true))
  end)
end)

describe("lib/text/effects.lua", function()
  local effects = require("lib.text.effects")

  it("words each lasting effect, in the spec's order, in either tense", function()
    local what = {
      parked = { "A", "B" },
      pads = { count = 3, added = 6.24 },
      headroom = {
        { name = "Bravo", resolved = -4 }, { name = "Delta", resolved = 2 }, { name = "Echo", resolved = 0 },
      },
      dropped = { items = 1, points = 2 },
      cuts = 2,
      unsafe = { { track_index = 2, position = 12 } },
    }
    assert.are.same({
      "Move 2 left-out regions after the end of the Arrangement: A, B",
      "Add silence to 3 regions so they end on a bar line (about 6.2 s in total)",
      "Change the end of 2 regions with Headroom: Bravo -4.0 s, Delta +2.0 s",
      "Headroom on Echo is too small to change anything (under half a bar).",
      "Discard 1 item and 2 automation points that are in no region",
      "Cut 2 items at region edges",
      "Apply will stop if any of these are inside a moved region: track 3 at 12.0 s. "
        .. "Set those tracks' timebase to Time to avoid this.",
    }, effects.lines(what, false, false))

    local past = effects.lines(what, true)
    assert.are.equal("Moved 2 left-out regions after the end of the Arrangement: A, B", past[1])
    assert.are.equal("Added silence to 3 regions (6.2 s)", past[2])
    assert.are.equal("Changed the end of 2 regions with Headroom: Bravo -4.0 s, Delta +2.0 s", past[3])
    assert.are.equal("Discarded 1 item and 2 automation points that were in no region", past[5])
  end)

  it("drops 'about' when Padding is exact, and says nothing when there is nothing", function()
    assert.are.equal("Add silence to 1 region so they end on a bar line (2.0 s in total)",
      effects.lines({ pads = { count = 1, added = 2 } }, false, true)[1])
    assert.are.same({}, effects.lines({}, false, true))
  end)

  it("caps a long name list at 8 and points at the run log", function()
    local names = {}
    for index = 1, 10 do
      names[index] = "R" .. index
    end
    local line = effects.lines({ parked = names }, false)[1]
    assert.is_truthy(line:find("R8", 1, true))
    assert.is_falsy(line:find("R9", 1, true))
    assert.is_truthy(line:find("and 2 more (see the run log)", 1, true))
  end)
end)

describe("lib/text/check.lua summary and verify.lua summary", function()
  it("keeps the message box to a verdict, refusals with fixes, and effects", function()
    local message = check_text.summary({ arrangement = "X", padding_exact = true, findings = {
      { severity = "permanent", code = "cut", splits = { {}, {} } },
      { severity = "informational", code = "moves", counts = {} },
    } })
    assert.are.equal('Ready to apply "X".\n\nThis will also:\n- Cut 2 items at region edges', message)
  end)

  it("says nothing more than 'ready' when there are no effects", function()
    assert.are.equal('Ready to apply "X".', check_text.summary({ arrangement = "X", findings = {} }))
  end)

  it("picks the Verify fix from what is wrong", function()
    local fail = { verdict = "fail", name = "X", findings = { { code = "gap", after = "A" } } }
    assert.is_truthy(verify_text.summary(fail):find('Apply "X" again to fix this.', 1, true))
    fail.findings[2] = { code = "region_absent", region_name = "Z" }
    local message = verify_text.summary(fail)
    assert.is_truthy(message:find("Restore the missing regions in REAPER", 1, true))
    assert.is_falsy(message:find("again to fix this", 1, true))
  end)

  it("caps Verify's list at 8 problems", function()
    local findings = {}
    for index = 1, 10 do
      findings[index] = { code = "gap", after = "R" .. index }
    end
    local message = verify_text.summary({ verdict = "fail", name = "X", findings = findings })
    assert.is_truthy(message:find('"R8"', 1, true))
    assert.is_falsy(message:find('"R9"', 1, true))
    assert.is_truthy(message:find("and 2 more (see the run log)", 1, true))
  end)
end)
