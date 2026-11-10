const test = require("node:test");
const assert = require("node:assert");
const core = require("../www/lcrr/snapshots/js/core.js");
const hk = require("../www/lcrr/snapshots/js/hold-key.js");
const words = require("../www/lcrr/snapshots/js/words.js");
const hold = require("../../../shared/www/lcrr/shared/js/hold.js");

// A fake button and document, and a fake clock for the shared hold.
function setup(onComplete) {
  let now = 0, timers = [], paints = 0;
  const handlers = {};
  const classes = new Set();
  const btn = {
    disabled: false,
    classList: { add: (c) => classes.add(c), remove: (c) => classes.delete(c) },
    style: { setProperty() {} },
    addEventListener: (n, f) => { handlers[n] = f; }
  };
  const doc = { addEventListener() {}, removeEventListener() {} };
  const gate = core.createGate(() => { paints++; });
  hk.holdKey(btn, {
    gate, doc, onComplete,
    createHold: (o) => hold.createHold(Object.assign({
      setTimer: (cb, ms) => { const t = { at: now + ms, cb }; timers.push(t); return t; },
      clearTimer: (t) => { timers = timers.filter((x) => x !== t); }
    }, o))
  });
  return {
    handlers, gate, classes, paints: () => paints,
    advance: (ms) => { now += ms; timers.filter((t) => t.at <= now).forEach((t) => { timers = timers.filter((x) => x !== t); t.cb(); }); }
  };
}

test("one hold time for every key", () => {
  assert.strictEqual(hk.HOLD_MS, 1000);
});

test("a list refresh is deferred while a Restore hold is down and applied when it ends", () => {
  let restored = 0;
  const r = setup(() => restored++);
  r.handlers.pointerdown({ button: 0 });
  assert.ok(r.gate.active());
  assert.ok(r.classes.has("holding"));
  r.gate.request();
  r.advance(500);
  assert.strictEqual(r.paints(), 0);
  r.advance(500);
  assert.strictEqual(restored, 1);
  assert.strictEqual(r.paints(), 1);
  assert.ok(!r.gate.active());
});

test("a released hold sends nothing and still applies the deferred refresh", () => {
  let restored = 0;
  const r = setup(() => restored++);
  r.handlers.pointerdown({ button: 0 });
  r.gate.request();
  r.advance(400);
  r.handlers.pointerup();
  r.advance(5000);
  assert.strictEqual(restored, 0);
  assert.strictEqual(r.paints(), 1);
});

test("the Restore key has a hold label like its neighbours", () => {
  assert.ok(words.holdLabel("restore", "Verse").startsWith("Restore Verse"));
});
