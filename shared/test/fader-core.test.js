const test = require("node:test");
const assert = require("node:assert");
const core = require("../www/lcrr/shared/js/fader-core.js");

const CAP = Math.pow(10, 6 / 20);

test("fader law: value = pos^4 * CAP, with its inverse and the 0 dB mark near 84%", () => {
  assert.strictEqual(core.CAP, CAP);
  assert.strictEqual(core.faderValue(0), 0);
  assert.strictEqual(core.faderValue(1), CAP);
  assert.ok(Math.abs(core.faderValue(0.5) - CAP / 16) < 1e-12);
  assert.ok(Math.abs(core.faderPos(1) - 0.8414) < 1e-3);
  assert.strictEqual(core.faderPos(0), 0);
  assert.strictEqual(core.faderPos(CAP), 1);
  assert.strictEqual(core.faderPos(CAP * 3), 1);
  assert.strictEqual(core.faderPos(-1), 0);
  [0.1, 0.37, 0.84, 0.99].forEach((p) => assert.ok(Math.abs(core.faderPos(core.faderValue(p)) - p) < 1e-9));
  assert.strictEqual(core.faderValue(2), CAP);
  assert.strictEqual(core.faderValue(-1), 0);
});

test("setVolCommand builds the level write and the end-of-move request", () => {
  assert.strictEqual(core.setVolCommand(3, -2, 0.5, false), "SET/TRACK/3/SEND/-2/VOL/0.5");
  assert.strictEqual(core.setVolCommand(3, 0, 0.5, true), "SET/TRACK/3/SEND/0/VOL/0.5e");
  assert.ok(!/e-/.test(core.setVolCommand(1, -1, 1e-9, false)));
});

// Fake host for the drag controller: clock, timers and a send that stays pending until released.
function host(opts) {
  opts = opts || {};
  const h = { t: 1000, sent: [], timers: [], allow: true, auto: false };
  h.pending = [];
  h.drag = core.createFaderDrag({
    now: () => h.t,
    setTimer: (fn, ms) => { const x = { fn, at: h.t + ms, on: true }; h.timers.push(x); return x; },
    clearTimer: (x) => { x.on = false; },
    send: (cmd) => { h.sent.push(cmd); if (h.auto) return { then: (ok) => ok() }; return new Promise((res) => h.pending.push(res)); },
    check: () => h.allow,
    gateMs: 50, slopPx: opts.slop || 0, travelPx: 100
  });
  h.advance = (ms) => { h.t += ms; h.timers.filter((x) => x.on && x.at <= h.t).forEach((x) => { x.on = false; x.fn(); }); };
  h.land = async () => { const r = h.pending.shift(); r(); await Promise.resolve(); await Promise.resolve(); };
  return h;
}
const T = { track: 2, y: -1, source: 5 };
const vol = (v) => core.setVolCommand(2, -1, v, false);
const vole = (v) => core.setVolCommand(2, -1, v, true);

test("drag: press and release with no movement, or jitter under the slop, sends nothing", () => {
  const h = host({ slop: 3 });
  h.drag.begin(T, 1);
  h.drag.end();
  h.drag.begin(T, 1);
  h.drag.move(2);
  h.drag.end();
  assert.deepStrictEqual(h.sent, []);
  h.drag.begin(T, 0.5);
  const r = h.drag.move(13); // 3 px slop, then 10 px = 0.1 of the travel: no jump at the start
  assert.ok(Math.abs(r.pos - (core.faderPos(0.5) + 0.1)) < 1e-9);
});

test("drag: relative, the first write follows the law from the starting level without a jump", () => {
  const h = host();
  h.drag.begin(T, core.faderValue(0.5));
  const r = h.drag.move(10); // +10 px of 100 px travel = +0.1
  assert.ok(Math.abs(r.pos - 0.6) < 1e-9);
  assert.strictEqual(h.sent.length, 1);
  assert.strictEqual(h.sent[0], vol(core.faderValue(r.pos)));
});

test("drag: writes at most one per 50 ms, latest value wins", () => {
  const h = host(); h.auto = true;
  h.drag.begin(T, 0.1);
  h.drag.move(10);
  assert.strictEqual(h.sent.length, 1);
  h.advance(10); h.drag.move(20); h.advance(10); h.drag.move(30);
  assert.strictEqual(h.sent.length, 1);
  h.advance(40);
  assert.strictEqual(h.sent.length, 2);
  assert.ok(h.sent[1] === vol(core.faderValue(core.faderPos(0.1) + 0.3)));
});

test("drag: at most one level write in flight, the next goes out after the reply", async () => {
  const h = host();
  h.drag.begin(T, 0.1);
  h.drag.move(10);
  h.advance(60); h.drag.move(20);
  assert.strictEqual(h.sent.length, 1); // first not answered yet
  await h.land();
  assert.strictEqual(h.sent.length, 2);
});

test("release sends the pending value and the e as one joined request, in that order", () => {
  const h = host(); h.auto = true;
  h.drag.begin(T, 0.1);
  h.drag.move(10);
  h.advance(10); const r = h.drag.move(20);
  h.drag.end();
  assert.strictEqual(h.sent.length, 2);
  const v = core.faderValue(r.pos);
  assert.strictEqual(h.sent[1], vol(v) + ";" + vole(v));
});

test("release with the last value already sent sends only the e", () => {
  const h = host(); h.auto = true;
  h.drag.begin(T, 0.1);
  const r = h.drag.move(10);
  h.drag.end();
  assert.deepStrictEqual(h.sent, [vol(core.faderValue(r.pos)), vole(core.faderValue(r.pos))]);
});

test("release while a write is in flight waits for it, so the final never lands before an older value", async () => {
  const h = host();
  h.drag.begin(T, 0.1);
  const a = h.drag.move(10);
  h.advance(60); const b = h.drag.move(20);
  h.drag.end();
  assert.strictEqual(h.sent.length, 1);
  await h.land();
  assert.strictEqual(h.sent.length, 2);
  assert.strictEqual(h.sent[1], vol(core.faderValue(b.pos)) + ";" + vole(core.faderValue(b.pos)));
  assert.notStrictEqual(a.pos, b.pos);
});

test("a failed write does not block the fader", async () => {
  const sent = [];
  const d = core.createFaderDrag({ now: () => 0, setTimer: () => 0, clearTimer: () => {}, send: (c) => { sent.push(c); return Promise.reject(new Error("x")); }, check: () => true, gateMs: 0, slopPx: 0, travelPx: 100 });
  d.begin(T, 0.1); d.move(5);
  await Promise.resolve(); await Promise.resolve();
  d.move(10);
  assert.strictEqual(sent.length, 2);
});

test("above the cap: the level is untouched, upward movement writes nothing, downward drops it at once", () => {
  const h = host(); h.auto = true;
  h.drag.begin(T, 3.0);
  assert.strictEqual(h.drag.pos(), 1);
  assert.strictEqual(h.drag.move(20), null);
  assert.strictEqual(h.drag.move(60), null);
  h.drag.end();
  assert.deepStrictEqual(h.sent, []); // no e either
  h.drag.begin(T, 3.0);
  h.drag.move(40);              // up and away
  const r = h.drag.move(30);    // then 10 px down from the furthest point: drops straight away
  assert.ok(r && r.pos < 1 && Math.abs(r.pos - 0.9) < 1e-9);
  assert.strictEqual(h.sent[0], vol(core.faderValue(0.9)));
  h.sent.forEach((c) => assert.ok(parseFloat(c.split("VOL/")[1]) <= CAP));
});

test("no drag produces a value above the cap or below zero", () => {
  const h = host(); h.auto = true;
  h.drag.begin(T, 1);
  assert.strictEqual(h.drag.move(500).value, CAP);
  assert.strictEqual(h.drag.move(600), null);
  const lo = h.drag.move(-900);
  assert.strictEqual(lo.value, 0);
  assert.strictEqual(h.drag.move(-1000), null);
  assert.ok(Math.abs(h.drag.move(-920).pos - 0.8) < 1e-9); // no dead zone at the bottom either
});

test("cancel (mix closed, offline, row gone) ends the drag with no final write and no e", async () => {
  const h = host(); h.auto = true;
  h.drag.begin(T, 0.1);
  h.drag.move(10);
  h.advance(10); h.drag.move(20); // pending
  h.drag.cancel();
  h.advance(100);
  h.drag.end();
  assert.strictEqual(h.sent.length, 1);
  assert.strictEqual(h.drag.active(), false);
});

test("every write, the final and the e pass the stale check and are dropped otherwise", () => {
  const h = host(); h.auto = true;
  h.allow = false;
  h.drag.begin(T, 0.1);
  h.drag.move(10);
  h.drag.end();
  assert.deepStrictEqual(h.sent, []);
  h.allow = true;
  h.drag.begin(T, 0.1);
  h.drag.move(10);            // sent
  h.advance(10); h.drag.move(20); // pending
  h.allow = false;
  h.drag.end();
  assert.strictEqual(h.sent.length, 1); // final and e dropped
  h.allow = true;
  h.drag.begin(T, 0.1);       // the fader is usable again
  assert.ok(h.drag.move(10));
});

test("a drag that sent nothing because the check failed does not send an e later", () => {
  const h = host(); h.auto = true;
  h.allow = false;
  h.drag.begin(T, 0.1); h.drag.move(10);
  h.allow = true;
  h.drag.end();
  assert.deepStrictEqual(h.sent, []);
});

test("poll replies are held while dragging and until the writes have landed; older reads never apply", async () => {
  const h = host();
  const idle = h.drag.readToken();
  assert.ok(h.drag.canApply(idle));
  h.drag.begin(T, 0.1);
  assert.ok(!h.drag.canApply(idle));
  assert.ok(!h.drag.canApply(h.drag.readToken()));
  const during = h.drag.readToken();
  h.drag.move(10);
  h.drag.end();
  assert.ok(!h.drag.canApply(during));
  await h.land(); await h.land();
  assert.ok(!h.drag.canApply(during));   // began before the drag ended
  assert.ok(h.drag.canApply(h.drag.readToken()));
});

test("a read begun while the final writes were still out is not applied", async () => {
  const h = host();
  h.drag.begin(T, 0.1); h.drag.move(10); h.drag.end();
  const tok = h.drag.readToken(); // e still to go out
  await h.land(); await h.land();
  assert.ok(!h.drag.canApply(tok));
});

test("begin is refused while the previous drag's final request is still waiting", () => {
  const h = host();
  h.drag.begin(T, 0.1); h.drag.move(10); h.drag.end(); // first write in flight, e waiting
  assert.strictEqual(h.drag.begin(T, 0.1), false);
});

// ---- Mute ----
test("setMuteCommand is an explicit 0 or 1 on the send, never a level", () => {
  assert.strictEqual(core.setMuteCommand(4, -2, true), "SET/TRACK/4/SEND/-2/MUTE/1");
  assert.strictEqual(core.setMuteCommand(4, -2, false), "SET/TRACK/4/SEND/-2/MUTE/0");
});

function muteHarness(allowed) {
  const sent = [], resolvers = [];
  const w = core.createMuteWriter({
    check: () => allowed.v,
    send: (cmd) => { sent.push(cmd); return new Promise((res, rej) => resolvers.push({ res, rej })); }
  });
  return { w, sent, resolvers, target: { track: 4, y: -1, source: 2 } };
}
const tick = () => new Promise((r) => setImmediate(r));

test("mute press sends the opposite of the on-screen state, and only a mute request", () => {
  const h = muteHarness({ v: true });
  assert.strictEqual(h.w.press(h.target, false), true);
  assert.deepStrictEqual(h.sent, ["SET/TRACK/4/SEND/-1/MUTE/1"]);
  const h2 = muteHarness({ v: true });
  h2.w.press(h2.target, true);
  assert.deepStrictEqual(h2.sent, ["SET/TRACK/4/SEND/-1/MUTE/0"]);
});

test("mute press does nothing when the stale check fails", () => {
  const h = muteHarness({ v: false });
  assert.strictEqual(h.w.press(h.target, false), false);
  assert.deepStrictEqual(h.sent, []);
  assert.ok(!h.w.busy());
});

test("a second tap while the write is outstanding is ignored (double tap)", async () => {
  const h = muteHarness({ v: true });
  h.w.press(h.target, false);
  assert.strictEqual(h.w.press(h.target, true), false);
  assert.strictEqual(h.sent.length, 1);
  h.resolvers[0].res(""); await tick();
  assert.strictEqual(h.w.press(h.target, true), true); // allowed again once landed
  assert.strictEqual(h.sent.length, 2);
});

test("a read that began before the write landed is never applied; one that began after is", async () => {
  const h = muteHarness({ v: true });
  const before = h.w.readToken();
  assert.ok(h.w.canApply(before));
  h.w.press(h.target, false);
  assert.ok(!h.w.canApply(before));            // write outstanding
  const during = h.w.readToken();
  assert.ok(!h.w.canApply(during));
  h.resolvers[0].res(""); await tick();
  assert.ok(!h.w.canApply(before));            // began before the write
  assert.ok(!h.w.canApply(during));            // began while it was outstanding
  assert.ok(h.w.canApply(h.w.readToken()));    // began after it landed
});

test("a failed mute write also settles, so the next read shows the true state", async () => {
  const h = muteHarness({ v: true });
  h.w.press(h.target, false);
  const during = h.w.readToken();
  h.resolvers[0].rej(new Error("x")); await tick();
  assert.ok(!h.w.busy());
  assert.ok(!h.w.canApply(during));
  assert.ok(h.w.canApply(h.w.readToken()));
});

// ---- The controller with an injected command and mapping (IEM Mix's pan is one; its functions live in that app) ----
const linear = {
  command: (track, y, v, end) => "X/" + track + "/" + y + "/" + v.toFixed(2) + (end ? "e" : ""),
  toValue: (pos) => pos * 2 - 1,
  toPos: (v) => (v + 1) / 2
};
function injected(extra) {
  return core.createFaderDrag(Object.assign({ now: () => 0, setTimer: () => 0, clearTimer() {}, check: () => true, gateMs: 0, slopPx: 0, travelPx: 100 }, linear, extra));
}

test("injected functions: the value and the command are the injected ones, and one write is in flight", () => {
  const sent = [];
  const d = injected({ send: (c) => { sent.push(c); return new Promise(() => {}); } });
  assert.strictEqual(d.begin(T, 0), true);    // centre: pos 0.5
  assert.ok(Math.abs(d.pos() - 0.5) < 1e-12);
  const r = d.move(25);                       // a quarter of the travel right
  assert.ok(Math.abs(r.value - 0.5) < 1e-12);
  assert.deepStrictEqual(sent, ["X/2/-1/0.50"]);
  assert.ok(d.move(40));
  d.end();
  assert.strictEqual(sent.length, 1);         // one in flight: the rest waits
});

test("injected functions: release joins the value and the end with ;", async () => {
  const sent = [];
  const d = injected({ gateMs: 50, send: (c) => { sent.push(c); return Promise.resolve(); } });
  d.begin(T, 0);
  d.move(10);
  await Promise.resolve(); await Promise.resolve();
  d.move(-20);
  d.end();
  assert.deepStrictEqual(sent, ["X/2/-1/0.20", "X/2/-1/-0.40;X/2/-1/-0.40e"]);
});

test("injected functions: a read applies only while idle and nothing happened since it began", async () => {
  const d = injected({ send: () => Promise.resolve() });
  const early = d.readToken();
  assert.ok(d.canApply(early));
  d.begin(T, 0);
  assert.strictEqual(d.readToken(), -1);
  assert.ok(!d.canApply(early));
  d.move(10); d.end();
  await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
  assert.ok(!d.canApply(early));          // began before the drag
  assert.ok(d.canApply(d.readToken()));   // a read begun after it settled
});

test("injected functions: a failed stale check writes nothing", () => {
  const sent = [];
  const d = injected({ check: () => false, send: (c) => { sent.push(c); return new Promise(() => {}); } });
  d.begin(T, 0); d.move(10); d.end();
  assert.deepStrictEqual(sent, []);
});

// ---- the wheel burst (nudge) ----
test("finishWheel: sends the e now, and says so while it is still waiting on a write", async () => {
  const h = host();
  h.drag.nudge(T, 0.5);
  assert.strictEqual(h.drag.finishWheel(), true);  // the step is in flight, so the e is still to go out
  assert.deepStrictEqual(h.sent, [vol(0.5)]);
  await h.land();
  assert.deepStrictEqual(h.sent, [vol(0.5), vole(0.5)]);
  assert.strictEqual(h.drag.finishWheel(), false);
  await h.land();
  h.advance(1000);
  assert.strictEqual(h.sent.length, 2);            // the idle wait was cleared: no second e
});

test("finishWheel: no burst, nothing to send; a stale row sends no e", async () => {
  const h = host();
  assert.strictEqual(h.drag.finishWheel(), false);
  assert.deepStrictEqual(h.sent, []);
  h.drag.nudge(T, 0.5);
  h.drag.finishWheel();
  h.allow = false;
  await h.land();
  assert.deepStrictEqual(h.sent, [vol(0.5)]);
});

test("nudge: steps are written like a drag, and one e goes out after the wheel has been idle", async () => {
  const h = host();
  assert.strictEqual(h.drag.nudge(T, 0.5), true);
  assert.deepStrictEqual(h.sent, [vol(0.5)]);
  h.advance(10); h.drag.nudge(T, 0.52);          // gated and one in flight: waits
  h.advance(10); h.drag.nudge(T, 0.54);          // latest wins
  assert.strictEqual(h.sent.length, 1);
  await h.land();
  h.advance(60);
  assert.deepStrictEqual(h.sent, [vol(0.5), vol(0.54)]);
  await h.land();
  h.advance(300);                                // not idle long enough since the last step
  assert.strictEqual(h.sent.length, 2);
  h.advance(200);                                // 400 ms idle: the e, once
  assert.deepStrictEqual(h.sent, [vol(0.5), vol(0.54), vole(0.54)]);
  await h.land();
  h.advance(1000);
  assert.strictEqual(h.sent.length, 3);
});

test("nudge: the wait counts as busy, so a read cannot move the control between steps", async () => {
  const h = host(); h.auto = true;
  const token = h.drag.readToken();
  assert.strictEqual(token, 0);
  h.drag.nudge(T, 0.5);
  assert.strictEqual(h.drag.busy(), true);
  assert.strictEqual(h.drag.readToken(), -1);
  assert.strictEqual(h.drag.canApply(token), false);
  h.advance(400);
  h.advance(0);
  assert.strictEqual(h.drag.busy(), false);
  const t2 = h.drag.readToken();
  assert.strictEqual(h.drag.canApply(t2), true);
  assert.strictEqual(h.drag.canApply(token), false);
});

test("nudge: refused during a drag (which is left alone), and a drag is refused during the burst", () => {
  const h = host(); h.auto = true;
  h.drag.begin(T, 0.5);
  assert.strictEqual(h.drag.nudge(T, 0.9), false);
  assert.strictEqual(h.drag.active(), true);
  assert.deepStrictEqual(h.sent, []);
  h.drag.end();
  h.drag.nudge(T, 0.5);
  assert.strictEqual(h.drag.begin(T, 0.5), false);
});

test("nudge: a failed stale check writes nothing; going stale or locking during the wait sends no e", () => {
  const h = host(); h.auto = true;
  h.allow = false;
  assert.strictEqual(h.drag.nudge(T, 0.5), false);
  assert.deepStrictEqual(h.sent, []);
  h.allow = true;
  h.drag.nudge(T, 0.5);
  h.allow = false;                               // the row went stale
  h.advance(400);
  assert.deepStrictEqual(h.sent, [vol(0.5)]);
  const g = host(); g.auto = true;
  g.drag.nudge(T, 0.5);
  g.drag.cancel();                               // locked
  g.advance(1000);
  assert.deepStrictEqual(g.sent, [vol(0.5)]);
  assert.strictEqual(g.drag.busy(), false);
});

test("nudge: a step that has not gone out yet is joined with the e", async () => {
  const h = host();
  h.drag.nudge(T, 0.5);
  h.advance(10); h.drag.nudge(T, 0.6);
  h.advance(400);                                // idle while the first is still in flight
  await h.land();
  assert.deepStrictEqual(h.sent, [vol(0.5), vol(0.6) + ";" + vole(0.6)]);
});
