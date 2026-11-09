const test = require("node:test");
const assert = require("node:assert");
const { createHold } = require("../www/lcrr/shared/js/hold.js");

function fakeTimers() {
  const t = { cb: null, ms: null, cleared: 0 };
  t.setTimer = (cb, ms) => { t.cb = cb; t.ms = ms; return 7; };
  t.clearTimer = () => { t.cb = null; t.cleared++; };
  return t;
}

test("a quick tap (start then cancel) never completes", () => {
  const t = fakeTimers(); let done = 0;
  const h = createHold({ holdMs: 800, onComplete: () => done++, setTimer: t.setTimer, clearTimer: t.clearTimer });
  h.start(); h.cancel();
  assert.strictEqual(t.cb, null);
  assert.strictEqual(done, 0);
});

test("holding for the full duration completes exactly once", () => {
  const t = fakeTimers(); let done = 0;
  const h = createHold({ holdMs: 800, onComplete: () => done++, setTimer: t.setTimer, clearTimer: t.clearTimer });
  h.start();
  assert.strictEqual(t.ms, 800);
  t.cb();
  assert.strictEqual(done, 1);
  h.cancel(); // release after completion must not re-fire or throw
  assert.strictEqual(done, 1);
});

test("repeated start while holding (key auto-repeat) does not restart the timer", () => {
  const t = fakeTimers(); let starts = 0;
  const h = createHold({ holdMs: 800, onComplete() {}, setTimer: (cb, ms) => { starts++; return t.setTimer(cb, ms); }, clearTimer: t.clearTimer });
  h.start(); h.start(); h.start();
  assert.strictEqual(starts, 1);
});

test("onStart/onCancel callbacks drive the UI; cancel after complete is silent", () => {
  const t = fakeTimers(); const log = [];
  const h = createHold({ holdMs: 500, onStart: () => log.push("start"), onCancel: () => log.push("cancel"),
    onComplete: () => log.push("done"), setTimer: t.setTimer, clearTimer: t.clearTimer });
  h.start(); h.cancel();
  h.start(); t.cb(); h.cancel();
  assert.deepStrictEqual(log, ["start", "cancel", "start", "done"]);
});

test("can be used again after completing", () => {
  const t = fakeTimers(); let done = 0;
  const h = createHold({ holdMs: 500, onComplete: () => done++, setTimer: t.setTimer, clearTimer: t.clearTimer });
  h.start(); t.cb(); h.cancel();
  h.start(); t.cb();
  assert.strictEqual(done, 2);
});
