const test = require("node:test");
const assert = require("node:assert");
const { createPoller } = require("../www/lcrr/shared/js/poll.js");

// Fake manual timer: collects the scheduled callback so tests step it explicitly.
function fakeTimers() {
  const t = { cb: null, delay: null };
  t.setTimer = (cb, ms) => { t.cb = cb; t.delay = ms; return 1; };
  t.clearTimer = () => { t.cb = null; };
  return t;
}
const tick = () => new Promise((r) => setImmediate(r));

test("polls the base transport command and notifies subscribers", async () => {
  const timers = fakeTimers();
  const urls = [];
  const p = createPoller({ fetchText: async (u) => { urls.push(u); return "TRANSPORT\t0\t1\t0\ta\tb"; },
    intervalMs: 500, setTimer: timers.setTimer, clearTimer: timers.clearTimer });
  const events = [];
  p.subscribe((e) => events.push(e));
  p.start();
  await tick();
  assert.deepStrictEqual(urls, ["/_/TRANSPORT"]);
  assert.deepStrictEqual(events, [{ ok: true, text: "TRANSPORT\t0\t1\t0\ta\tb" }]);
  assert.strictEqual(timers.delay, 500);
});

test("extra commands are added to the same request, once each", async () => {
  const timers = fakeTimers();
  const urls = [];
  const p = createPoller({ fetchText: async (u) => { urls.push(u); return ""; },
    setTimer: timers.setTimer, clearTimer: timers.clearTimer });
  p.addCommand("REGION_LIST"); p.addCommand("REGION_LIST");
  p.start();
  await tick();
  assert.deepStrictEqual(urls, ["/_/TRANSPORT;REGION_LIST"]);
});

test("a failed fetch reports an error and polling continues", async () => {
  const timers = fakeTimers();
  const p = createPoller({ fetchText: async () => { throw new Error("down"); },
    setTimer: timers.setTimer, clearTimer: timers.clearTimer });
  const events = [];
  p.subscribe((e) => events.push(e));
  p.start();
  await tick();
  assert.strictEqual(events[0].ok, false);
  assert.match(events[0].error.message, /down/);
  assert.ok(timers.cb, "next poll scheduled");
});

test("pollNow triggers an immediate poll and stop halts scheduling", async () => {
  const timers = fakeTimers();
  let n = 0;
  const p = createPoller({ fetchText: async () => { n++; return ""; },
    setTimer: timers.setTimer, clearTimer: timers.clearTimer });
  p.start(); await tick();
  p.pollNow(); await tick();
  assert.strictEqual(n, 2);
  p.stop();
  assert.strictEqual(timers.cb, null);
});

test("unsubscribe stops notifications", async () => {
  const timers = fakeTimers();
  const p = createPoller({ fetchText: async () => "", setTimer: timers.setTimer, clearTimer: timers.clearTimer });
  let n = 0;
  const off = p.subscribe(() => n++);
  off();
  p.start(); await tick();
  assert.strictEqual(n, 0);
});

const { withTimeout } = require("../www/lcrr/shared/js/poll.js");

test("withTimeout rejects a request that never settles, and passes through ones that do", async () => {
  let fire;
  const setTimer = (cb) => { fire = cb; return 1; };
  const clearTimer = () => { fire = null; };
  const hung = withTimeout(new Promise(() => {}), 3000, setTimer, clearTimer);
  fire();
  await assert.rejects(hung, /timeout/);

  assert.strictEqual(await withTimeout(Promise.resolve("ok"), 3000, setTimer, clearTimer), "ok");
  assert.strictEqual(fire, null, "timer cleared after settling");
  await assert.rejects(withTimeout(Promise.reject(new Error("boom")), 3000, setTimer, clearTimer), /boom/);
});

test("a throwing listener does not stop other listeners or the next poll", async () => {
  const timers = [];
  const p = createPoller({ fetchText: () => Promise.resolve("TRANSPORT\t0\t0"), setTimer: (cb) => { timers.push(cb); return timers.length; }, clearTimer() {} });
  let seen = 0;
  const origError = console.error; console.error = () => {};
  p.subscribe(() => { throw new Error("boom"); });
  p.subscribe(() => { seen++; });
  p.start();
  await new Promise((r) => setImmediate(r));
  console.error = origError;
  assert.strictEqual(seen, 1);
  assert.strictEqual(timers.length, 1, "next poll still scheduled");
});
