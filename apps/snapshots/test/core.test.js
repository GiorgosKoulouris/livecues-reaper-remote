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
