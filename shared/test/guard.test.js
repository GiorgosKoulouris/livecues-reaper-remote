const test = require("node:test");
const assert = require("node:assert");
const { createConnection, createCooldown } = require("../www/lcrr/shared/js/guard.js");

function clock() { const c = { t: 1000 }; c.now = () => c.t; return c; }

test("one failed poll is not offline; two consecutive are", () => {
  const c = createConnection({ now: clock().now });
  c.update(true); c.update(false);
  assert.strictEqual(c.isOffline(), false);
  c.update(false);
  assert.strictEqual(c.isOffline(), true);
});

test("a success between failures resets the count", () => {
  const c = createConnection({ now: clock().now });
  c.update(false); c.update(true); c.update(false);
  assert.strictEqual(c.isOffline(), false);
});

test("canCue is false after a single failed poll, before offline is declared", () => {
  const c = createConnection({ now: clock().now });
  c.update(true);
  assert.strictEqual(c.canCue(), true);
  c.update(false);
  assert.strictEqual(c.canCue(), false);
});

test("first successful poll enables cue immediately (no settle without an outage)", () => {
  const c = createConnection({ now: clock().now });
  c.update(true);
  assert.strictEqual(c.canCue(), true);
});

test("after an outage cue stays locked for settleMs after reconnect", () => {
  const k = clock();
  const c = createConnection({ now: k.now, settleMs: 1500 });
  c.update(true); c.update(false); c.update(false);
  c.update(true);
  assert.strictEqual(c.isOffline(), false);
  assert.strictEqual(c.canCue(), false);
  k.t += 1499; assert.strictEqual(c.canCue(), false);
  k.t += 1;    assert.strictEqual(c.canCue(), true);
});

test("a single dropped poll that recovers does not trigger the settle lock", () => {
  const c = createConnection({ now: clock().now });
  c.update(true); c.update(false); c.update(true);
  assert.strictEqual(c.canCue(), true);
});

test("cooldown ignores repeats inside the window and allows again after it", () => {
  const k = clock();
  const cd = createCooldown(1500, k.now);
  assert.strictEqual(cd.tryFire(), true);
  k.t += 1000; assert.strictEqual(cd.tryFire(), false);
  assert.strictEqual(cd.active(), true);
  k.t += 500;  assert.strictEqual(cd.tryFire(), true);
});
