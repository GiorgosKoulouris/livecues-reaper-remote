const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const core = require("../www/lcrr/snapshots/js/core.js");
const words = require("../www/lcrr/snapshots/js/words.js");

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

test("every refusal the bridge can send has words, not just its code", () => {
  let count = 0;
  Object.keys(replies).forEach((name) => {
    const r = replies[name];
    if (r.status !== "refused") return;
    const text = words.error(r.error);
    clean(text, name);
    assert.ok(!text.startsWith("Something went wrong"), name + " has no wording for " + r.error.code);
    count++;
  });
  assert.ok(count >= 3);
});

test("the client's own failures have words", () => {
  ["request_too_long", "unreachable", "no_reply"].forEach((code) => {
    assert.ok(!words.error({ code }).startsWith("Something went wrong"), code);
  });
});

test("the state reply is pushed through to the project name", () => {
  assert.strictEqual(words.projectName(core.readState(replies.state).project), "Sunday");
  assert.strictEqual(words.projectName(core.readState(replies.state_unsaved).project), "(unsaved project)");
});

test("every connection phase has a chip, and only the failing ones a banner", () => {
  ["connecting", "ready", "offline", "bridge-down"].forEach((p) => clean(words.chip(p), p));
  assert.strictEqual(words.banner("ready"), "");
  assert.strictEqual(words.banner("connecting"), "");
  clean(words.banner("offline"), "offline");
  clean(words.banner("bridge-down"), "bridge-down");
});

test("every refusal a save or a list can meet is worded, matching the recorded replies", () => {
  ["snapshot_save_empty_name", "snapshot_save_bad_name", "snapshot_save_name_too_long", "snapshot_save_duplicate_name", "snapshots_unreadable"].forEach((name) => {
    assert.strictEqual(replies[name].status, "refused", name);
    const text = words.error(replies[name].error);
    clean(text, name);
    assert.ok(!text.startsWith("Something went wrong"), name);
    assert.strictEqual(words.error({ code: replies[name].error.code }), text);
  });
  ["empty_name", "bad_name", "name_too_long", "duplicate_name"].forEach((code) => {
    assert.ok(!words.error({ code }).startsWith("Something went wrong"), code);
  });
});

test("a recorded list is pushed through to its row text", () => {
  const list = core.readList(replies.snapshots);
  assert.strictEqual(words.counts(list[0], "Nov 10 12:00"), "2 tracks, 3 sends · Nov 10 12:00");
  assert.strictEqual(words.counts({ tracks: 1, sends: 1 }, ""), "1 track, 1 send");
  clean(words.ui("empty"), "empty");
  clean(words.ui("name"), "name");
  clean(words.ui("save"), "save");
});
