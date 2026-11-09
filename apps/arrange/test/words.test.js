const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const words = require("../www/lcrr/arrange/js/words.js");

// Real replies, recorded from the Lua service (apps/arrange/spec/bridge_contract_spec.lua).
const replies = {};
fs.readFileSync(path.join(__dirname, "fixtures/bridge-replies.txt"), "utf8").split("\n").filter(Boolean).forEach((line) => {
  const tab = line.indexOf("\t");
  replies[line.slice(0, tab)] = JSON.parse(line.slice(tab + 1));
});

function clean(text, label) {
  assert.strictEqual(typeof text, "string", label);
  assert.ok(text.length > 0, label + " is empty");
  assert.ok(!/undefined|NaN|\[object|null/.test(text), label + " has a hole in it: " + text);
}

test("the fixture has the replies the page is built on", () => {
  assert.ok(Object.keys(replies).length >= 25);
});

test("every refusal the bridge can send has words, not just its code", () => {
  Object.keys(replies).forEach((name) => {
    const r = replies[name];
    if (r.status !== "refused" && !(r.error)) return;
    const text = words.error(r.error);
    clean(text, name);
    assert.notStrictEqual(text, r.error.code, name + " has no wording for " + r.error.code);
  });
});

test("every refusal and Verify problem has words", () => {
  let count = 0;
  Object.keys(replies).filter((n) => /^(check|verify)_/.test(n)).forEach((name) => {
    (replies[name].findings || []).filter((e) => e.severity === "refusal" || /^verify_/.test(name)).forEach((entry) => {
      const text = words.finding(entry);
      clean(text, name + "/" + entry.code);
      assert.notStrictEqual(text, entry.code, name + " has no wording for " + entry.code);
      count++;
    });
  });
  assert.ok(count >= 3);
});

test("the reply still carries what the console and log need", () => {
  assert.strictEqual(replies.check_proceed.blind_spots.length, 3);
  assert.strictEqual(typeof replies.check_proceed.padding_exact, "boolean");
  assert.strictEqual(replies.check_proceed.token, "aaaaaa");
  assert.strictEqual(replies.check_refuse.token, undefined);
});

test("a Check that would refuse says so, with each refusal and its fix", () => {
  const out = words.checkSummary(replies.check_refuse);
  assert.strictEqual(out.headline, '"Ghost" can\'t be applied yet.');
  assert.strictEqual(out.ready, false);
  assert.match(out.problems.join("\n"), /Restore them in REAPER, or remove them from "Ghost" on the Edit tab\./);
  assert.strictEqual(out.notPlanned, "Fix these and run Check again to see what else it would do.");
  assert.deepStrictEqual(out.effects, []);
});

test("a Check that would proceed lists only the lasting effects, one line each", () => {
  const out = words.checkSummary(replies.check_headroom);
  clean(out.headline, "headline");
  assert.match(out.headline, /^Ready to apply "/);
  assert.strictEqual(out.effectsHeading, "This will also:");
  out.effects.forEach((line) => clean(line, "effect"));
  assert.ok(out.effects.some((l) => /^Add silence to \d+ regions? so they end on a bar line \(about \d+\.\d s in total\)$/.test(l)));
  assert.ok(out.effects.some((l) => /^Change the end of 1 region with Headroom: \w+ [+-]\d+\.\d s$/.test(l)));
  assert.ok(out.effects.every((l) => !/move|counts|anchor/i.test(l) || /^Move \d+ left-out/.test(l)));
});

test("a Check drops 'about' once Padding is exact", () => {
  const reply = Object.assign({}, replies.check_headroom, { padding_exact: true });
  assert.ok(words.checkSummary(reply).effects.some((l) => /\(\d+\.\d s in total\)$/.test(l)));
});

test("a Check on an unsafe timebase lists the places, with the fix", () => {
  const out = words.checkSummary(replies.check_unsafe);
  assert.strictEqual(out.ready, false);
  assert.match(out.problems.join("\n"), /track 3 at 49\.0 s/);
});

test("a Headroom too small to act is said plainly, and an Arrangement that already matches says so", () => {
  const reply = { name: "Tiny", padding_exact: true, findings: [
    { severity: "informational", code: "no_change" },
    { severity: "permanent", code: "headroom", headroom: [{ name: "Bravo", resolved: 0 }] }] };
  const out = words.checkSummary(reply);
  assert.strictEqual(out.headline, '"Tiny" already matches the timeline. Nothing to apply.');
  assert.deepStrictEqual(out.effects, ["Headroom on Bravo is too small to change anything (under half a bar)."]);
});

test("a Verify says pass or fail, lists problems and gives a fix that fits them", () => {
  assert.strictEqual(words.verifySummary(replies.verify_pass).headline, 'The timeline matches "Packed".');
  const fail = words.verifySummary(replies.verify_fail);
  assert.match(fail.headline, /^The timeline doesn't match "/);
  assert.ok(fail.lines.length > 0);
  fail.lines.forEach((l) => clean(l, "verify line"));
  assert.match(fail.fix, /^Apply ".*" again to fix this\.$/);
  const missing = words.verifySummary({ name: "X", verdict: "fail", findings: [{ code: "region_absent", region_name: "Bravo" }] });
  assert.deepStrictEqual(missing.lines, ['"Bravo" is in the Arrangement but not in the project']);
  assert.match(missing.fix, /^Restore the missing regions in REAPER, or remove them from "X" on the Edit tab, then Apply again\.$/);
});

test("Verify's problems are plain lines", () => {
  assert.strictEqual(words.finding({ code: "order_mismatch", region_name: "Bridge", after: "Verse 2" }), '"Bridge" is before "Verse 2"');
  assert.strictEqual(words.finding({ code: "gap", after: "Chorus" }), 'There is a gap after "Chorus"');
  assert.strictEqual(words.finding({ code: "overlap", region_name: "Bridge", after: "Chorus" }), '"Bridge" overlaps "Chorus"');
  assert.strictEqual(words.finding({ code: "block_start" }), "The first region doesn't start at the beginning of the timeline");
  assert.strictEqual(words.finding({ code: "off_bar_line", region_name: "Outro" }), '"Outro" isn\'t on a bar line');
  assert.strictEqual(words.finding({ code: "not_parked", region_name: "Bonus" }), '"Bonus" isn\'t in the Arrangement but is still among its regions');
});

test("a finished Apply is summarised in past tense, whatever it did", () => {
  ["apply_ok", "apply_subset", "apply_headroom", "apply_noop"].forEach((name) => {
    const out = words.applySummary(replies[name]);
    clean(out.headline, name);
    out.effects.forEach((l) => clean(l, name));
  });
  assert.match(words.applySummary(replies.apply_noop).headline, /already matches the timeline/);
  const ok = words.applySummary(replies.apply_ok);
  assert.strictEqual(ok.headline, 'Applied "Identity".');
  assert.strictEqual(ok.tail, "Undo in REAPER takes it back.");
});

test("an Apply with a Headroom says what was changed", () => {
  const out = words.applySummary(replies.apply_headroom);
  assert.ok(out.effects.some((l) => /^Changed the end of 1 region with Headroom: \w+ [+-]\d+\.\d s$/.test(l)), out.effects.join("|"));
});

test("an Apply that parked regions names them", () => {
  const out = words.applySummary(replies.apply_subset);
  assert.ok(out.effects.some((l) => /^Moved 1 left-out region after the end of the Arrangement: Charlie$/.test(l)), out.effects.join("|"));
});

test("discarded material is called out in the past tense", () => {
  const out = words.applySummary(replies.apply_ok);
  assert.ok(out.effects.some((l) => /^Discarded 4 items and 1 automation point that were in no region$/.test(l)), out.effects.join("|"));
});

test("the Headroom question is short, asked before anything is written", () => {
  const text = words.headroomQuestion(replies.apply_confirm.confirm.headroom);
  clean(text, "question");
  assert.match(text, /^Apply Headroom to 1 region\?\n\n  Bravo: \+4\.0 s\n\nEach Apply moves these region ends again\.$/);
});

test("an Apply that refused after its Tempo Anchors says how to take the changes back", () => {
  const text = words.error(replies.apply_refused.error);
  assert.match(text, /Press Ctrl\+Z in REAPER to remove the changes made so far\./);
  assert.doesNotMatch(text, /Tempo Anchor/);
});

test("a refused plan names its fix, and items are shown by track number and time", () => {
  const text = words.error(replies.apply_refused.error);
  assert.match(text, /track 3 at 49\.0 s/);
  assert.match(text, /Set those tracks' timebase to Time, then try again\./);
  assert.match(words.error({ code: "plan_refused", reason: "region_overlap", region: "A", next_region: "B" }), /"A" ends after "B" starts\. Separate them/);
  assert.match(words.error({ code: "plan_refused", reason: "headroom", problems: [{ kind: "shrink_too_far", name: "Bravo", requested: -20, most: 8 }] }),
    /^"Bravo" can't shrink by 20\.0 s\. The most it can lose without cutting into its content is 8\.0 s\. Lower its Headroom on the Edit tab, then try again\.$/);
  assert.match(words.error({ code: "plan_refused", reason: "headroom", problems: [{ kind: "too_large", name: "Bravo" }] }), /The Headroom on "Bravo" is too large\. Check the value on the Edit tab\./);
});

test("an internal failure gives the plain instruction and hides the raw error (issue 10)", () => {
  const text = words.error({ code: "internal", message: "could not find the envelope point" });
  assert.doesNotMatch(text, /envelope point/);
  assert.match(text, /^Apply stopped partway\. Press Ctrl\+Z in REAPER to undo what it did, then try again\./);
});

test("a stale token says which way", () => {
  assert.match(words.error({ code: "token_stale", reason: "other_project" }), /different project is open/);
  assert.match(words.error({ code: "token_stale", reason: "arrangement_changed", name: "Radio" }), /"Radio" was edited since this Check/);
  assert.match(words.error(replies.token_stale.error), /The project changed since this Check/);
});

test("no refusal shows a code label, sidecar, a script path or an API name", () => {
  Object.keys(replies).forEach((name) => {
    const r = replies[name];
    if (!r.error) return;
    const text = words.error(r.error);
    assert.doesNotMatch(text.toLowerCase(), /sidecar|\.lua|scripts\/|install\.ps1/, name);
    assert.doesNotMatch(text, /\b[a-z]+_[a-z_]+\b/, name);
  });
});

test("Capture explains what to do next", () => {
  const text = words.captureSummary(replies.capture_ok);
  clean(text, "capture");
  assert.match(text, /Next: duplicate it on the Edit tab/);
});

test("Capture's questions come from the recorded confirms", () => {
  assert.strictEqual(replies.capture_rewrite.confirm.code, "rewrite");
  assert.match(words.rewriteQuestion(), /rewrites the whole file/);
  assert.match(words.replaceQuestion(replies.capture_confirm.confirm.name), /"Fresh" already exists/);
});

test("track timebases are named, and an unknown one is said to be unknown", () => {
  assert.strictEqual(words.timebase(0), "time");
  assert.strictEqual(words.timebase(-1), "project default");
  assert.strictEqual(words.timebase(9), "UNKNOWN");
});

test("duplicate and unnamed regions are listed with their numbers", () => {
  const text = words.problems(replies.duplicates_problems.problems);
  assert.match(text, /"A" is used by 2 regions \(Region Numbers 1, 2\)/);
  assert.match(text, /1 region\(s\) have no name/);
});

test("a call that never got an answer says whether to trust Apply", () => {
  assert.match(words.failure("no_reply"), /Apply may still be running/);
  assert.match(words.failure("unreachable"), /Can't reach REAPER/);
  assert.match(words.failure("request_too_long"), /too long/);
});

test("the edit replies the page is built on are recorded, and each refusal is worded", () => {
  ["edit_name_taken", "edit_sidecar_changed", "edit_other_project", "edit_invalid"].forEach((name) => {
    assert.strictEqual(replies[name].status, "refused", name);
    clean(words.error(replies[name].error), name);
  });
  assert.match(words.error(replies.edit_sidecar_changed.error), /Redo the edit/);
  assert.match(words.error({ code: "sidecar_invalid", error: "boom" }), /Fix it in a text editor/);
});

test("the edit and read replies carry what the editor needs", () => {
  const read = replies.arrangements;
  assert.strictEqual(read.sidecar, "ok");
  assert.strictEqual(typeof read.revision, "string");
  assert.ok(read.arrangements.every((a) => a.name && Array.isArray(a.entries)));
  assert.ok(read.regions.length > 0);
  assert.strictEqual(replies.arrangements_missing.revision, "none");
  assert.strictEqual(replies.arrangements_invalid.sidecar, "invalid");
  assert.strictEqual(replies.arrangements_unsaved.sidecar, "unsaved");
  assert.deepStrictEqual(replies.edit_new.entries, []);
  assert.strictEqual(replies.edit_confirm.confirm.code, "rewrite");
  assert.strictEqual(replies.edit_delete.entries, undefined);
  assert.ok(replies.edit_delete.deleted_entries.length > 0);
});

test("the editor's sentences", () => {
  assert.strictEqual(words.headroomLabel(0), "No Headroom");
  assert.strictEqual(words.headroomLabel(4), "+4 s at next Apply");
  assert.strictEqual(words.headroomLabel(-2.5), "-2.5 s at next Apply");
  assert.strictEqual(words.headroomLabel(1.25), "+1.25 s at next Apply");
  assert.match(words.deleteQuestion("Show", 3), /"Show".*3 regions/);
  assert.match(words.deleteQuestion("Show", 1), /1 region\?/);
  clean(words.emptyArrangementNote("X"), "empty");
  clean(words.headroomInputInvalid(), "invalid");
  ["invalid", "unsaved", "missing"].forEach((s) => clean(words.noSidecarEditNote(s, "boom"), s));
  assert.strictEqual(words.noSidecarEditNote("ok"), "");
});

test("the recorded edit replies all have words", () => {
  Object.keys(replies).filter((n) => n.indexOf("edit_") === 0).forEach((n) => {
    const r = replies[n];
    if (r.error) clean(words.error(r.error), n);
  });
});

test("undo sentences name the Arrangement and region", () => {
  const e = { operation: "move", arrangement: "Show", region: "Intro", steps: [] };
  assert.match(words.undone(e), /^Undid the move of .*Intro.* in .*Show/);
  assert.match(words.undoLabel({ operation: "rename", arrangement: "Old" }), /renaming to .*Old/);
  assert.match(words.undoRefused(e), /no longer applies/);
});
