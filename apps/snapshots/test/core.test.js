const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const core = require("../www/lcrr/snapshots/js/core.js");

const replies = {};
fs.readFileSync(path.join(__dirname, "fixtures/bridge-replies.txt"), "utf8").split("\n").filter(Boolean).forEach((line) => {
  const tab = line.indexOf("\t");
  replies[line.slice(0, tab)] = JSON.parse(line.slice(tab + 1));
});

test("the connection phase follows the guard and the heartbeat", () => {
  assert.strictEqual(core.connectionPhase(true, true, "running"), "offline");
  assert.strictEqual(core.connectionPhase(false, false, "unknown"), "connecting");
  assert.strictEqual(core.connectionPhase(false, true, "stopped"), "bridge-down");
  assert.strictEqual(core.connectionPhase(false, true, "unknown"), "connecting");
  assert.strictEqual(core.connectionPhase(false, true, "running"), "ready");
});

test("controls exist only while the bridge is running", () => {
  ["connecting", "offline", "bridge-down"].forEach((p) => assert.strictEqual(core.canUse(p), false, p));
  assert.strictEqual(core.canUse("ready"), true);
});

test("the recorded state replies are ones the page can draw; refusals are not", () => {
  assert.ok(core.readState(replies.state));
  assert.ok(core.readState(replies.state_unsaved));
  ["unknown_command", "request_truncated", "bad_request"].forEach((n) => assert.strictEqual(core.readState(replies[n]), null, n));
  assert.strictEqual(core.readState(null), null);
});

test("the recorded snapshots replies are lists the page can draw, in save order; refusals are not", () => {
  assert.deepStrictEqual(core.readList(replies.snapshots_empty), []);
  const list = core.readList(replies.snapshots);
  assert.deepStrictEqual(list.map((s) => s.name), ["Verse", "Chorus"]);
  assert.strictEqual(list[0].tracks, 2);
  assert.strictEqual(list[0].sends, 3);
  assert.strictEqual(list[0].solo, true);
  assert.strictEqual(list[0].masterMuted, true);
  assert.strictEqual(core.readList(replies.snapshots_unreadable), null);
  assert.strictEqual(core.readList(replies.snapshot_save), null);
  assert.strictEqual(core.readList(null), null);
});

test("an identical list is the same; a changed one is not", () => {
  assert.ok(core.sameList(core.readList(replies.snapshots), core.readList(replies.snapshots)));
  const a = core.readList(replies.snapshots), b = core.readList(replies.snapshots);
  b[1].name = "Bridge";
  assert.ok(!core.sameList(a, b));
});

test("a name is checked the way the bridge will check it", () => {
  assert.deepStrictEqual(core.checkName("  Verse 2 ", []), { name: "Verse 2" });
  assert.deepStrictEqual(core.checkName("   ", []), { code: "empty_name" });
  assert.deepStrictEqual(core.checkName(undefined, []), { code: "empty_name" });
  assert.deepStrictEqual(core.checkName("a\nb", []), { code: "bad_name" });
  assert.deepStrictEqual(core.checkName("é".repeat(40), []), { name: "é".repeat(40) });
  assert.deepStrictEqual(core.checkName("é".repeat(41), []), { code: "name_too_long" });
  assert.deepStrictEqual(core.checkName("x", [], () => false), { code: "name_too_long" });
  assert.deepStrictEqual(core.checkName("Verse", ["Verse"]), { code: "duplicate_name" });
  assert.deepStrictEqual(core.checkName("verse", ["Verse"]), { name: "verse" });
});
