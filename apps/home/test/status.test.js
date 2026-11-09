const test = require("node:test");
const assert = require("node:assert");
const { chip } = require("../www/lcrr/home/js/status.js");

test("a live poll shows connected", () => {
  assert.deepStrictEqual(chip(true, false, true), { state: "online", text: "REAPER connected" });
});

test("before any reply, a missed poll keeps showing connecting", () => {
  assert.strictEqual(chip(false, false, false).state, "connecting");
});

test("one missed poll after being connected changes nothing (null = keep the current chip)", () => {
  assert.strictEqual(chip(false, false, true), null);
});

test("the guard's offline verdict shows unreachable, whether or not REAPER was ever seen", () => {
  assert.strictEqual(chip(false, true, true).state, "offline");
  assert.strictEqual(chip(false, true, false).state, "offline");
});
