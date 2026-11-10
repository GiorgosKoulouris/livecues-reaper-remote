const test = require("node:test");
const assert = require("node:assert");
const wheel = require("../www/lcrr/iemmix/js/wheel.js");
const fc = require("../../../shared/www/lcrr/shared/js/fader-core.js");

const db = (v) => 20 * Math.log10(v);
const lin = (d) => Math.pow(10, d / 20);
const UP = -100, DOWN = 100; // deltaY: wheel up (negative) is louder
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, a + " vs " + b);

test("one notch moves 0.5 dB, up and down", () => {
  const up = wheel.decide({ locked: false, deltaY: UP, vol: lin(-10) });
  assert.strictEqual(up.act, true);
  near(db(up.value), -9.5);
  const down = wheel.decide({ locked: false, deltaY: DOWN, vol: lin(-10) });
  assert.strictEqual(down.act, true);
  near(db(down.value), -10.5);
});

test("an upward step never goes above the +6 dB cap", () => {
  const r = wheel.decide({ locked: false, deltaY: UP, vol: lin(5.8) });
  assert.strictEqual(r.value, fc.CAP);
  near(db(wheel.decide({ locked: false, deltaY: UP, vol: lin(5.5) }).value), 6);
  assert.strictEqual(wheel.decide({ locked: false, deltaY: UP, vol: fc.CAP }).value, null);
});

test("a level above the cap is left alone upward, but steps down", () => {
  const vol = lin(8);
  const up = wheel.decide({ locked: false, deltaY: UP, vol: vol });
  assert.strictEqual(up.act, true);
  assert.strictEqual(up.value, null);
  near(db(wheel.decide({ locked: false, deltaY: DOWN, vol: vol }).value), 7.5);
});

test("from silence an upward step goes to the lowest audible step; down does nothing", () => {
  const up = wheel.decide({ locked: false, deltaY: UP, vol: 0 });
  assert.strictEqual(up.act, true);
  assert.strictEqual(up.value, lin(-60));
  assert.strictEqual(wheel.MIN_DB, -60);
  assert.strictEqual(wheel.decide({ locked: false, deltaY: DOWN, vol: 0 }).value, null);
});

test("a level between silence and the lowest step steps up to the lowest step", () => {
  assert.strictEqual(wheel.decide({ locked: false, deltaY: UP, vol: lin(-80) }).value, lin(-60));
});

test("a downward step past the lowest audible step reaches silence exactly", () => {
  assert.strictEqual(wheel.decide({ locked: false, deltaY: DOWN, vol: lin(-60) }).value, 0);
  assert.strictEqual(wheel.decide({ locked: false, deltaY: DOWN, vol: lin(-60.2) }).value, 0);
  near(db(wheel.decide({ locked: false, deltaY: DOWN, vol: lin(-59) }).value), -59.5);
});

test("the lowest audible step is the grid step just above where the readout leaves -inf", () => {
  // The result must be a real, positive, writable level that the fader's law places on the track.
  assert.ok(lin(wheel.MIN_DB) > 0);
  assert.ok(fc.faderPos(lin(wheel.MIN_DB)) > 0);
});

test("locked: the wheel does not act, so the page scrolls", () => {
  const r = wheel.decide({ locked: true, deltaY: UP, vol: lin(-10) });
  assert.deepStrictEqual(r, { act: false, value: null });
});

test("no vertical movement or unknown level: the wheel does not act", () => {
  assert.strictEqual(wheel.decide({ locked: false, deltaY: 0, vol: lin(-10) }).act, false);
  assert.strictEqual(wheel.decide({ locked: false, deltaY: UP, vol: null }).act, false);
});

// ---- notches: deltaMode, big events, small events ----
const IDLE = fc.WHEEL_IDLE_MS;
const near0 = (a, b) => assert.ok(Math.abs(a - b) < 1e-6, a + " vs " + b);
// Feeds events in order at the given times; returns every result.
function run(vol, events) {
  let state;
  return events.map((e) => {
    const r = wheel.decide(Object.assign({ locked: false, vol, state, now: 0 }, e));
    state = r.state;
    return r;
  });
}

test("deltaMode: 100 pixels, 3 lines or 1 page are each one notch", () => {
  near(db(wheel.decide({ locked: false, deltaY: -100, deltaMode: 0, vol: 1 }).value), 0.5);
  near(db(wheel.decide({ locked: false, deltaY: -3, deltaMode: 1, vol: 1 }).value), 0.5);
  near(db(wheel.decide({ locked: false, deltaY: -1, deltaMode: 2, vol: 1 }).value), 0.5);
});

test("a single event of a notch or more gives one step per whole notch", () => {
  near(db(wheel.decide({ locked: false, deltaY: 250, vol: 1 }).value), -1);
  near(db(wheel.decide({ locked: false, deltaY: -6, deltaMode: 1, vol: 1 }).value), 1);
});

test("a wheel that sends 120 per notch gives no stray steps: the remainder is cleared", () => {
  const r = run(1, [{ deltaY: 120 }, { deltaY: 120 }, { deltaY: 80 }]);
  near(db(r[0].value), -0.5);
  near(db(r[1].value), -0.5); // worked out from the same vol here: one step each
  assert.strictEqual(r[2].value, null);
  assert.strictEqual(r[2].act, true);
});

test("a big event also clears what small events had gathered", () => {
  const r = run(1, [{ deltaY: 60 }, { deltaY: 100 }, { deltaY: 60 }]);
  assert.strictEqual(r[0].value, null);
  near(db(r[1].value), -0.5);
  assert.strictEqual(r[2].value, null); // 0.6 and nothing carried
});

test("small events gather to one step, and the page does not scroll meanwhile", () => {
  const r = run(1, [{ deltaY: -40 }, { deltaY: -40 }, { deltaY: -40 }, { deltaY: -40 }, { deltaY: -40 }]);
  assert.deepStrictEqual(r.map((x) => x.act), [true, true, true, true, true]);
  assert.strictEqual(r[0].value, null);
  assert.strictEqual(r[1].value, null);
  near(db(r[2].value), 0.5); // 120: one step, 20 kept
  assert.strictEqual(r[3].value, null); // 60
  near(db(r[4].value), 0.5); // 100
});

test("small events in lines gather too: three of one line are exactly one notch", () => {
  const r = run(1, [{ deltaY: 1, deltaMode: 1 }, { deltaY: 1, deltaMode: 1 }, { deltaY: 1, deltaMode: 1 }]);
  assert.strictEqual(r[1].value, null);
  near(db(r[2].value), -0.5);
});

test("a change of direction clears what was gathered", () => {
  const r = run(1, [{ deltaY: 60 }, { deltaY: -60 }, { deltaY: -60 }]);
  assert.strictEqual(r[1].value, null); // 0.6 the other way, not 0
  near(db(r[2].value), 0.5);
});

test("what was gathered is cleared after the wheel's idle wait, and kept just inside it", () => {
  const cleared = run(1, [{ deltaY: 60, now: 1000 }, { deltaY: 60, now: 1000 + IDLE }]);
  assert.strictEqual(cleared[1].value, null);
  const kept = run(1, [{ deltaY: 60, now: 1000 }, { deltaY: 60, now: 1000 + IDLE - 1 }]);
  near(db(kept[1].value), -0.5);
});

test("up from exactly -60 dB moves on: only a level below it lands on it", () => {
  near(db(wheel.decide({ locked: false, deltaY: UP, vol: lin(-60) }).value), -59.5);
});

test("the idle wait is the fader's own", () => {
  assert.strictEqual(fc.WHEEL_IDLE_MS, 400);
});

test("a locked page never gathers: small events scroll as normal", () => {
  assert.deepStrictEqual(wheel.decide({ locked: true, deltaY: 40, vol: 1, state: { carry: 0.9, at: 0 }, now: 1 }), { act: false, value: null });
});

test("a purely sideways event keeps what was gathered", () => {
  const r = run(1, [{ deltaY: 60 }, { deltaY: 0 }, { deltaY: 60 }]);
  assert.strictEqual(r[1].act, false);
  near(db(r[2].value), -0.5);
});

test("several notches at once keep the -60 dB rule and the cap, step by step", () => {
  near0(db(wheel.decide({ locked: false, deltaY: -200, vol: 0 }).value), -59.5);       // silence, -60, then one more
  assert.strictEqual(wheel.decide({ locked: false, deltaY: 300, vol: lin(-59.5) }).value, 0); // -60, then silence, then stops
  assert.strictEqual(wheel.decide({ locked: false, deltaY: -300, vol: lin(5.8) }).value, fc.CAP);
  assert.strictEqual(wheel.decide({ locked: false, deltaY: -300, vol: lin(8) }).value, null);
  assert.strictEqual(wheel.decide({ locked: false, deltaY: 300, vol: 0 }).value, null);
});

test("small events keep the -60 dB rule: up from silence and down to silence", () => {
  const up = run(0, [{ deltaY: -60 }, { deltaY: -60 }]);
  assert.strictEqual(up[1].value, lin(-60));
  const down = run(lin(-60), [{ deltaY: 60 }, { deltaY: 60 }]);
  assert.strictEqual(down[1].value, 0);
});

const CELL_A = { key: "a" }, CELL_B = { key: "b" };

test("wheel latch: a gesture acts on the control under the pointer when it begins", () => {
  const l = wheel.createWheelLatch();
  assert.strictEqual(l.route(1000, CELL_A), CELL_A);
});

test("wheel latch: an edit stays on the cell it began on, wherever the pointer goes, until the wheel is idle", () => {
  const l = wheel.createWheelLatch();
  l.route(1000, CELL_A);
  assert.strictEqual(l.route(1100, CELL_B), CELL_A); // the next cell under the pointer is left alone
  assert.strictEqual(l.route(1400, null), CELL_A);   // nor does leaving the cells turn it into a scroll
  assert.strictEqual(l.route(1700, CELL_B), CELL_A); // each event renews the wait
  assert.strictEqual(l.route(1700 + fc.WHEEL_IDLE_MS, CELL_B), CELL_B);
});

test("wheel latch: a movement that began as a scroll stays one until the wheel is idle", () => {
  const l = wheel.createWheelLatch();
  assert.strictEqual(l.route(1000, null), null);
  assert.strictEqual(l.route(1300, CELL_A), null);   // rows slid under the pointer
  assert.strictEqual(l.route(1600, CELL_A), null);
  assert.strictEqual(l.route(1600 + fc.WHEEL_IDLE_MS, CELL_A), CELL_A);
});

test("wheel latch: an event that could not act turns the gesture into a scroll", () => {
  const l = wheel.createWheelLatch();
  l.route(1000, CELL_A);
  l.scrolled(1000);
  assert.strictEqual(l.route(1100, CELL_A), null);
});
