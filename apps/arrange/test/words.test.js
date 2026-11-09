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

test("every finding in a Check and a Verify has words", () => {
  let count = 0;
  Object.keys(replies).filter((n) => /^(check|verify)_/.test(n)).forEach((name) => {
    (replies[name].findings || []).forEach((entry) => {
      const text = words.finding(entry);
      clean(text, name + "/" + entry.code);
      assert.notStrictEqual(text, entry.code, name + " has no wording for " + entry.code);
      count++;
    });
  });
  assert.ok(count > 10);
});

test("every blind spot has words", () => {
  ["padding_grid", "anchor_drift", "padding_overlap", "headroom_count"].forEach((code) => {
    assert.notStrictEqual(words.blindSpot(code), code);
  });
  assert.strictEqual(replies.check_proceed.blind_spots.length, 3);
});

test("a Check says whether it would refuse", () => {
  assert.match(words.checkVerdict(replies.check_refuse), /WOULD REFUSE/);
  assert.match(words.checkVerdict(replies.check_proceed), /would proceed, with \d+ permanent/);
  assert.strictEqual(replies.check_proceed.token, "aaaaaa");
  assert.strictEqual(replies.check_refuse.token, undefined);
});

test("Padding is called exact only when it is", () => {
  assert.match(words.paddingNote(true), /EXACT/);
  assert.match(words.paddingNote(false), /ESTIMATES/);
});

test("a Verify says pass or fail", () => {
  assert.match(words.verifyVerdict(replies.verify_pass), /^PASS/);
  assert.match(words.verifyVerdict(replies.verify_fail), /^FAIL: .* \d+ problem/);
});

test("a finished Apply is summarised, whatever it did", () => {
  ["apply_ok", "apply_subset", "apply_headroom", "apply_noop"].forEach((name) => {
    const out = words.applySummary(replies[name]);
    assert.ok(out.length >= 1, name);
    out.forEach((p) => clean(p, name));
  });
  assert.match(words.applySummary(replies.apply_noop)[0], /already matches the timeline/);
});

test("an Apply with a Headroom says what was moved, and that it is relative", () => {
  const text = words.applySummary(replies.apply_headroom).join("\n");
  assert.match(text, /HEADROOM/);
  assert.match(text, /relative, not absolute/);
});

test("discarded material is called out and sent to the run log", () => {
  const text = words.applySummary(replies.apply_ok).join("\n");
  assert.match(text, /DISCARDED/);
  assert.match(text, /run log/);
});

test("the Headroom question is asked before anything is written, and explains why", () => {
  const text = words.headroomQuestion(replies.apply_confirm.confirm.headroom);
  clean(text, "question");
  assert.match(text, /Bravo: \+4\.000s/);
  assert.match(text, /RELATIVE/);
});

test("an Apply that refused after its Tempo Anchors says they are one undo step", () => {
  assert.match(words.error(replies.apply_refused.error), /1 Tempo Anchor\(s\) were written[\s\S]*Undo/);
});

test("a stale token says which way", () => {
  assert.match(words.error({ code: "token_stale", reason: "other_project" }), /different project/);
  assert.match(words.error(replies.token_stale.error), /changed in REAPER/);
});

test("Capture explains what to do next", () => {
  const text = words.captureSummary(replies.capture_ok);
  clean(text, "capture");
  assert.match(text, /Bars\.arrangements\.lua/);
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
  assert.match(words.failure("no_reply"), /run log/);
  assert.match(words.failure("unreachable"), /did not take the request/);
  assert.match(words.failure("request_too_long"), /too long/);
});

test("the edit replies the page is built on are recorded, and each refusal is worded", () => {
  ["edit_name_taken", "edit_sidecar_changed", "edit_other_project", "edit_invalid"].forEach((name) => {
    assert.strictEqual(replies[name].status, "refused", name);
    clean(words.error(replies[name].error), name);
  });
  assert.match(words.error(replies.edit_sidecar_changed.error), /redo the edit/);
  assert.match(words.error({ code: "sidecar_invalid", error: "boom" }), /Fix the file in a text editor/);
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
