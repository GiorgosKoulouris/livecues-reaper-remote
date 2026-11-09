const test = require("node:test");
const assert = require("node:assert");
const core = require("../www/lcrr/podium/js/core.js");

test("formatTime renders m:ss.mmm", () => {
  assert.strictEqual(core.formatTime(0), "0:00.000");
  assert.strictEqual(core.formatTime(12.5), "0:12.500");
  assert.strictEqual(core.formatTime(754.3216), "12:34.322");
  assert.strictEqual(core.formatTime(59.9996), "1:00.000");
  assert.strictEqual(core.formatTime(-3), "0:00.000");
});

const R = (id, start, end) => ({ name: "r" + id, id, start, end, color: 0 });

test("activeRegionId picks the region containing the position while playing", () => {
  const rs = [R(1, 0, 10), R(2, 10, 20)];
  assert.strictEqual(core.activeRegionId(rs, 5, 1), 1);
  assert.strictEqual(core.activeRegionId(rs, 10, 1), 2); // start inclusive, end exclusive
  assert.strictEqual(core.activeRegionId(rs, 19.99, 5), 2); // recording counts
});

test("activeRegionId is null when stopped, outside any region, or past the end", () => {
  const rs = [R(1, 5, 10)];
  assert.strictEqual(core.activeRegionId(rs, 7, 0), null);
  assert.strictEqual(core.activeRegionId(rs, 2, 1), null);
  assert.strictEqual(core.activeRegionId(rs, 10, 1), null);
  assert.strictEqual(core.activeRegionId([], 1, 1), null);
});

test("activeRegionId prefers the latest-starting region when regions overlap", () => {
  const rs = [R(1, 0, 100), R(2, 20, 30)];
  assert.strictEqual(core.activeRegionId(rs, 25, 1), 2);
  assert.strictEqual(core.activeRegionId(rs, 50, 1), 1);
});

test("formatClock renders m:ss, floored, and h:mm:ss from one hour", () => {
  assert.strictEqual(core.formatClock(0), "0:00");
  assert.strictEqual(core.formatClock(59.999), "0:59");
  assert.strictEqual(core.formatClock(754.3), "12:34");
  assert.strictEqual(core.formatClock(3600), "1:00:00");
  assert.strictEqual(core.formatClock(-5), "0:00");
});

test("transportSlot shows Stop only while playing or recording, never while paused or stopped", () => {
  assert.strictEqual(core.transportSlot(0), "play");
  assert.strictEqual(core.transportSlot(1), "stop");
  assert.strictEqual(core.transportSlot(5), "stop");
  assert.strictEqual(core.transportSlot(2), "play");
  assert.strictEqual(core.transportSlot(6), "play");
});
