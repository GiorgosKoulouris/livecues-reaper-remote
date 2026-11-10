const test = require("node:test");
const assert = require("node:assert");
const listen = require("../www/lcrr/iemmix/js/listen.js");

// Tracks as parseTrackReply gives them: only the fields Listen reads.
const t = (number, name, sendcnt, recvcnt, hwoutcnt) => ({ number, name, muted: false, sendcnt: sendcnt || 0, recvcnt: recvcnt || 0, hwoutcnt: hwoutcnt || 0, color: 0 });
const mix = (number, name, sendcnt) => t(number, "IEM_" + name, sendcnt, 1, 1);
const tracks = [t(1, "Vox", 2), mix(2, "Anna", 1), mix(3, "Ben", 1), t(4, "IEM-Cue", 0, 2)];
const sendLine = (tr, y, vol, dest) => ["SEND", tr, y, 0, vol, 0, dest].join("\t");
const model = () => { const m = listen.createListenModel(); m.update(tracks); return m; };

test("finds the cue track by exact name", () => {
  assert.strictEqual(listen.findCue(tracks), 4);
  assert.strictEqual(listen.findCue([t(1, "iem-cue"), t(2, "IEM-Cue2"), t(3, "IEM-Cue ")]), null);
  assert.strictEqual(listen.findCue([t(1, "IEM-Cue"), t(2, "IEM-Cue")]), 1);
});

test("reads every send of an unknown mix from 1 to sendcnt, and only the known send of a known one", () => {
  const two = [mix(2, "Anna", 2), t(3, "IEM-Cue")];
  assert.deepStrictEqual(listen.buildRequests(two, {}, 900), ["GET/TRACK/2/SEND/1;GET/TRACK/2/SEND/2"]);
  assert.deepStrictEqual(listen.buildRequests(two, { 2: { y: 2, vol: 0 } }, 900), ["GET/TRACK/2/SEND/2"]);
  assert.deepStrictEqual(listen.buildRequests([mix(2, "Anna", 2)], {}, 900), []); // no cue track
  assert.ok(listen.buildRequests(tracks, {}, 20).length > 1); // split under the limit
});

test("a mix with two hardware outputs has its ordinary sends after them: y runs from hwoutcnt to hwoutcnt + sendcnt - 1", () => {
  const twoOut = [t(2, "IEM_Anna", 1, 1, 2), t(3, "IEM-Cue")];
  assert.deepStrictEqual(listen.buildRequests(twoOut, {}, 900), ["GET/TRACK/2/SEND/2"]);
  const more = [t(2, "IEM_Anna", 2, 1, 2), t(3, "IEM-Cue")];
  assert.deepStrictEqual(listen.buildRequests(more, {}, 900), ["GET/TRACK/2/SEND/2;GET/TRACK/2/SEND/3"]);
  // the cue send found at the second y is kept and read alone
  const m = listen.createListenModel();
  m.update(twoOut);
  m.apply(twoOut, m.key(), sendLine(2, 2, 1, 3), m.mark());
  assert.deepStrictEqual(m.found()[2], { y: 2, vol: 1 });
  assert.deepStrictEqual(listen.buildRequests(twoOut, m.found(), 900), ["GET/TRACK/2/SEND/2"]);
});

test("the layout key changes with a mix's hardware output count, so a remembered y is dropped", () => {
  const one = [t(2, "IEM_Anna", 1, 1, 1), t(3, "IEM-Cue")], two = [t(2, "IEM_Anna", 1, 1, 2), t(3, "IEM-Cue")];
  assert.notStrictEqual(listen.layoutKey(one), listen.layoutKey(two));
  const m = listen.createListenModel();
  m.update(one);
  m.apply(one, m.key(), sendLine(2, 1, 1, 3), m.mark());
  assert.strictEqual(m.update(two), true);
  assert.deepStrictEqual(m.found(), {});
});

test("finds the cue send by its destination, whichever y it has", () => {
  const m = model(), k = m.key();
  assert.ok(m.apply(tracks, k, [sendLine(2, 1, 0.5, 1), sendLine(3, 1, 0, 4)].join("\n"), m.mark()));
  assert.deepStrictEqual(m.found(), { 3: { y: 1, vol: 0 } });
  m.apply(tracks, k, sendLine(2, 2, 1, 4), m.mark());
  assert.deepStrictEqual(m.found()[2], { y: 2, vol: 1 });
});

test("a reply under another layout, or begun before a write, is dropped; a missing line changes nothing", () => {
  const m = model();
  assert.strictEqual(m.apply(tracks, "other", sendLine(2, 1, 1, 4), m.mark()), false);
  const mark = m.mark();
  m.wrote();
  assert.strictEqual(m.apply(tracks, m.key(), sendLine(2, 1, 1, 4), mark), false);
  m.apply(tracks, m.key(), sendLine(2, 1, 1, 4), m.mark());
  m.apply(tracks, m.key(), sendLine(2, 1, 1, -1), m.mark());
  assert.deepStrictEqual(m.found()[2], { y: 1, vol: 1 });
  m.apply(tracks, m.key(), sendLine(2, 1, 1, 0), m.mark()); // now another destination: forgotten
  assert.strictEqual(m.found()[2], undefined);
});

test("a layout change drops what was found", () => {
  const m = model();
  m.apply(tracks, m.key(), sendLine(2, 1, 1, 4), m.mark());
  assert.strictEqual(m.update(tracks), false);
  assert.strictEqual(m.update(tracks.concat([mix(5, "Cy", 1)])), true);
  assert.deepStrictEqual(m.found(), {});
});

test("view: on, off, several on, pending, no cue send, no cue track", () => {
  let v = listen.view(tracks, { 2: { y: 1, vol: 1 }, 3: { y: 1, vol: 0 } }, true);
  assert.deepStrictEqual(v.rows.map((r) => [r.name, r.status, r.on, r.enabled]), [["Anna", "ok", true, true], ["Ben", "ok", false, true]]);
  assert.strictEqual(v.onCount, 1);
  assert.strictEqual(v.several, false);
  assert.strictEqual(v.note, "");
  v = listen.view(tracks, { 2: { y: 1, vol: 1 }, 3: { y: 1, vol: 0.7 } }, true);
  assert.strictEqual(v.several, true);
  v = listen.view(tracks, {}, false);
  assert.deepStrictEqual(v.rows.map((r) => r.status), ["pending", "pending"]);
  assert.strictEqual(v.note, "");
  v = listen.view(tracks, { 2: { y: 1, vol: 0 } }, true);
  assert.deepStrictEqual(v.rows.map((r) => [r.status, r.enabled]), [["ok", true], ["nocue", false]]);
  assert.match(v.note, /IEM Setup/);
  v = listen.view(tracks.slice(0, 3), {}, true);
  assert.deepStrictEqual(v.rows.map((r) => [r.status, r.enabled]), [["nocuetrack", false], ["nocuetrack", false]]);
  assert.match(v.note, /IEM-Cue.*IEM Setup/);
  assert.strictEqual(listen.view([t(1, "Vox")], {}, true).note, "");
});

test("a mix with a duplicated name cannot be listened to", () => {
  const dup = tracks.concat([t(5, "IEM_Anna", 0, 1, 1)]);
  const v = listen.view(dup, { 2: { y: 1, vol: 0 }, 3: { y: 1, vol: 0 } }, true);
  assert.strictEqual(v.rows.find((r) => r.number === 2).enabled, false);
  assert.strictEqual(v.rows.find((r) => r.number === 3).enabled, true);
});

const f2 = (a, b) => ({ 2: { y: 1, vol: a }, 3: { y: 1, vol: b } });
const plan = (f, target) => listen.plan(listen.view(tracks, f, true).rows, f, target);

test("plan: on from nothing, move, off, and several on", () => {
  assert.deepStrictEqual(plan(f2(0, 0), 2), [{ track: 2, y: 1, vol: 1 }]);
  assert.deepStrictEqual(plan(f2(1, 0), 3), [{ track: 2, y: 1, vol: 0 }, { track: 3, y: 1, vol: 1 }]);
  assert.deepStrictEqual(plan(f2(1, 0), 2), [{ track: 2, y: 1, vol: 0 }]);
  assert.deepStrictEqual(plan(f2(1, 1), 2), [{ track: 3, y: 1, vol: 0 }]); // leaves the tapped one at 1
  assert.deepStrictEqual(plan(f2(0.6, 1), 2), [{ track: 3, y: 1, vol: 0 }, { track: 2, y: 1, vol: 1 }]);
  assert.deepStrictEqual(plan(f2(0.6, 0), 2), [{ track: 2, y: 1, vol: 0 }]); // on at any level: off
});

test("plan: nothing for a mix with no cue send, an unknown mix or no cue track", () => {
  assert.deepStrictEqual(plan({ 2: { y: 1, vol: 0 } }, 3), []);
  assert.deepStrictEqual(plan(f2(0, 0), 9), []);
  assert.strictEqual(listen.tapPlan(tracks.slice(0, 3), f2(0, 0), true, 2, true), null);
});

test("level commands carry no e suffix, and a tap is one request", () => {
  assert.strictEqual(listen.levelCommand({ track: 2, y: 3, vol: 1 }), "SET/TRACK/2/SEND/3/VOL/1");
  assert.strictEqual(listen.levelCommand({ track: 2, y: 3, vol: 0 }), "SET/TRACK/2/SEND/3/VOL/0");
  const p = listen.tapPlan(tracks, f2(1, 0), true, 3, true);
  assert.strictEqual(p.command, "SET/TRACK/2/SEND/1/VOL/0;SET/TRACK/3/SEND/1/VOL/1");
});

test("lock gate: no plan while the page cannot edit", () => {
  assert.strictEqual(listen.tapPlan(tracks, f2(0, 0), true, 2, false), null);
  assert.notStrictEqual(listen.tapPlan(tracks, f2(0, 0), true, 2, true), null);
});

test("settled only after a sweep with no write in between, under the same layout", () => {
  const m = model();
  assert.strictEqual(m.settled(), false);
  const mark = m.mark();
  m.wrote();
  m.endSweep(m.key(), mark);
  assert.strictEqual(m.settled(), false);
  m.endSweep(m.key(), m.mark());
  assert.strictEqual(m.settled(), true);
});
