const test = require("node:test");
const assert = require("node:assert");
const core = require("../www/lcrr/monitor/js/core.js");

// Real reply shape, from .scratch/monitor/api-check-report.txt (issue 01).
function trackLine(n, name, recv, hw, color) {
  return ["TRACK", n, name, 128, "1.000000", "0.000000", -1500, -1500, "1.000000", 3, 0, recv, hw, color || 0].join("\t");
}
function reply(ntrack, lines) { return ["NTRACK\t" + ntrack].concat(lines).join("\n") + "\n"; }
const master = trackLine(0, "MASTER", 0, 1);

test("parseTrackReply reads NTRACK and the tracks, leaving the master out", () => {
  const r = core.parseTrackReply(reply(2, [master, trackLine(1, "Source A", 0, 0), trackLine(2, "IEM_Drums", 2, 1, 0x10000ff)]));
  assert.strictEqual(r.ntrack, 2);
  assert.deepStrictEqual(r.tracks.map((t) => t.number), [1, 2]);
  assert.deepStrictEqual(r.tracks[1], { number: 2, name: "IEM_Drums", recvcnt: 2, hwoutcnt: 1, sendcnt: 0, color: 0x10000ff });
});

test("parseTrackReply returns null when the reply is not a complete track set", () => {
  assert.strictEqual(core.parseTrackReply(""), null);
  assert.strictEqual(core.parseTrackReply("TRANSPORT\t0\t0\n"), null);
  assert.strictEqual(core.parseTrackReply(reply(3, [master, trackLine(1, "a", 0, 0)])), null); // partial: keep the old list
  assert.strictEqual(core.parseTrackReply(reply(1, [master, trackLine(1, "a", 0, 0), "TRACK\tx\tbroken"])).tracks.length, 1);
});

test("parseTrackReply accepts zero tracks", () => {
  assert.deepStrictEqual(core.parseTrackReply(reply(0, [master])), { ntrack: 0, tracks: [] });
});

function mixes(tracks) { return core.listMixes(core.parseTrackReply(reply(tracks.length, [master].concat(tracks))).tracks); }

test("listMixes lists IEM_ tracks that have a receive and a hardware output, without the prefix", () => {
  const m = mixes([trackLine(1, "Kick", 0, 0), trackLine(2, "IEM_Drums", 1, 1), trackLine(3, "IEM_Bass", 3, 2)]);
  assert.deepStrictEqual(m.map((x) => [x.name, x.number, x.duplicate]), [["Drums", 2, false], ["Bass", 3, false]]);
});

test("listMixes skips wrong case, empty name, no receive and no hardware output", () => {
  assert.deepStrictEqual(mixes([
    trackLine(1, "iem_x", 1, 1), trackLine(2, "Iem_x", 1, 1), trackLine(3, " IEM_x", 1, 1), trackLine(4, "XIEM_x", 1, 1), trackLine(7, "IEM_", 1, 1),
    trackLine(5, "IEM_norecv", 0, 1), trackLine(6, "IEM_nohw", 1, 0)
  ]), []);
});

test("listMixes marks every track of a duplicated name", () => {
  const m = mixes([trackLine(1, "IEM_Gtr", 1, 1), trackLine(2, "IEM_Keys", 1, 1), trackLine(3, "IEM_Gtr", 2, 1)]);
  assert.deepStrictEqual(m.map((x) => [x.name, x.number, x.duplicate]), [["Gtr", 1, true], ["Keys", 2, false], ["Gtr", 3, true]]);
});

test("listMixes treats names that differ only after the prefix as different", () => {
  assert.strictEqual(mixes([trackLine(1, "IEM_Gtr", 1, 1), trackLine(2, "IEM_gtr", 1, 1)]).some((x) => x.duplicate), false);
});

// ---- issue 03: mix view ----
function sendLine(t, y, flags, vol, other) { return ["SEND", t, y, flags, vol, "0.000000", other].join("\t"); }

test("parseSendReply reads SEND lines and the mute flag", () => {
  const r = core.parseSendReply(sendLine(4, -1, 8, "0.500000", 1) + "\n" + sendLine(4, -2, 0, "1.000000", 2) + "\nTRANSPORT\t0\n");
  assert.deepStrictEqual(r, [
    { track: 4, y: -1, vol: 0.5, muted: true, source: 1 },
    { track: 4, y: -2, vol: 1, muted: false, source: 2 }
  ]);
});

test("parseSendReply skips malformed lines", () => {
  assert.deepStrictEqual(core.parseSendReply("SEND\t4\tx\n" + "SEND\t4\t-1\t0\tnope\t0\t1\n"), []);
});

test("applyReceives takes only indexes within recvcnt and ignores a last field of -1", () => {
  const text = [sendLine(4, -1, 0, "1.0", 1), sendLine(4, -2, 0, "0.5", -1), sendLine(4, -3, 0, "0.5", 2), sendLine(4, 0, 0, "1.0", -1), sendLine(4, 1, 0, "1.0", 3)].join("\n");
  const r = core.applyReceives([], text, 4, 2);
  assert.strictEqual(r.length, 1);
  assert.strictEqual(r[0].source, 1);
  assert.strictEqual(r[1], undefined);
});

test("applyReceives keeps rows a partial reply does not cover and drops rows beyond recvcnt", () => {
  const first = core.applyReceives([], [sendLine(4, -1, 0, "1.0", 1), sendLine(4, -2, 0, "1.0", 2), sendLine(4, -3, 0, "1.0", 3)].join("\n"), 4, 3);
  const second = core.applyReceives(first, sendLine(4, -2, 8, "0.25", 5), 4, 3);
  assert.deepStrictEqual(second.map((x) => x.source), [1, 5, 3]);
  assert.strictEqual(second[1].muted, true);
  assert.strictEqual(core.applyReceives(second, "", 4, 2).length, 2);
});

test("applyReceives ignores a late reply for another track number", () => {
  const first = core.applyReceives([], sendLine(4, -1, 0, "1.0", 1), 4, 1);
  const next = core.applyReceives(first, sendLine(3, -1, 0, "0.1", 9), 4, 1);
  assert.strictEqual(next[0].source, 1);
  assert.strictEqual(next[0].vol, 1);
});

test("dbText converts linear level to dB text", () => {
  assert.strictEqual(core.dbText(1), "0.0 dB");
  assert.strictEqual(core.dbText(0.5), "-6.0 dB");
  assert.strictEqual(core.dbText(Math.pow(10, 6 / 20)), "+6.0 dB");
  assert.strictEqual(core.dbText(0), "-inf dB");
  assert.strictEqual(core.dbText(0.99999), "0.0 dB");
});

test("buildReceiveRequests covers every receive and keeps each URL under the limit", () => {
  const reqs = core.buildReceiveRequests(123, 60, 900);
  assert.ok(reqs.length > 1);
  reqs.forEach((q) => assert.ok(("/_/" + q).length <= 900));
  const all = reqs.join(";").split(";");
  assert.strictEqual(all.length, 60);
  assert.strictEqual(all[0], "GET/TRACK/123/SEND/-1");
  assert.strictEqual(all[59], "GET/TRACK/123/SEND/-60");
  assert.deepStrictEqual(core.buildReceiveRequests(5, 0, 900), []);
  assert.deepStrictEqual(core.buildReceiveRequests(5, 2, 900), ["GET/TRACK/5/SEND/-1;GET/TRACK/5/SEND/-2"]);
});

function tracksOf(list) { return core.parseTrackReply(reply(list.length, [master].concat(list))).tracks; }

test("findMix matches by name, follows the track index and refuses gone or duplicated names", () => {
  const a = tracksOf([trackLine(1, "Kick", 0, 0), trackLine(2, "IEM_Drums", 2, 1)]);
  assert.deepStrictEqual(core.findMix(a, "Drums"), { status: "ok", number: 2, recvcnt: 2, hwoutcnt: 1 });
  const b = tracksOf([trackLine(1, "New", 0, 0), trackLine(2, "Kick", 0, 0), trackLine(3, "IEM_Drums", 5, 1)]);
  assert.deepStrictEqual(core.findMix(b, "Drums"), { status: "ok", number: 3, recvcnt: 5, hwoutcnt: 1 });
  assert.strictEqual(core.findMix(tracksOf([trackLine(1, "IEM_Bass", 1, 1)]), "Drums").status, "gone");
  assert.strictEqual(core.findMix(tracksOf([trackLine(1, "IEM_Drums", 1, 1), trackLine(2, "IEM_Drums", 1, 1)]), "Drums").status, "duplicate");
  assert.strictEqual(core.findMix(tracksOf([trackLine(1, "IEM_Drums", 1, 1), trackLine(2, "IEM_Drums", 0, 0)]), "Drums").status, "duplicate");
  assert.strictEqual(core.findMix(tracksOf([trackLine(1, "IEM_Drums", 0, 1)]), "Drums").status, "gone");
});

test("rowsFor builds one view row per receive with source name, colour, dB and mute", () => {
  const tracks = tracksOf([trackLine(1, "Kick", 0, 0, 0x10000ff), trackLine(2, "Snare", 0, 0), trackLine(3, "IEM_Drums", 2, 1)]);
  const recv = core.applyReceives([], [sendLine(3, -1, 0, "0.5", 1), sendLine(3, -2, 8, "1.0", 2)].join("\n"), 3, 2);
  assert.deepStrictEqual(core.rowsFor(recv, tracks), [
    { n: 1, y: -1, source: 1, name: "Kick", color: 0x10000ff, vol: 0.5, db: "-6.0 dB", muted: false },
    { n: 2, y: -2, source: 2, name: "Snare", color: 0, vol: 1, db: "0.0 dB", muted: true }
  ]);
});

test("tracksKey changes when tracks are added, moved or renamed", () => {
  const a = tracksOf([trackLine(1, "A", 0, 0), trackLine(2, "B", 0, 0)]);
  assert.strictEqual(core.tracksKey(a), core.tracksKey(tracksOf([trackLine(1, "A", 0, 0), trackLine(2, "B", 0, 0)])));
  assert.notStrictEqual(core.tracksKey(a), core.tracksKey(tracksOf([trackLine(1, "B", 0, 0), trackLine(2, "A", 0, 0)])));
  assert.notStrictEqual(core.tracksKey(a), core.tracksKey(tracksOf([trackLine(1, "N", 0, 0), trackLine(2, "A", 0, 0), trackLine(3, "B", 0, 0)])));
});

// ---- Faders (issue 04) ----
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

test("writeAllowed needs the same mix track, the same source, a fresh read and an online page", () => {
  const recv = [{ source: 7, vol: 1, muted: false }, { source: 9, vol: 1, muted: false }];
  const st = { number: 4, receives: recv, fresh: true, offline: false };
  assert.ok(core.writeAllowed({ track: 4, y: -2, source: 9 }, st));
  assert.ok(!core.writeAllowed({ track: 5, y: -2, source: 9 }, st));
  assert.ok(!core.writeAllowed({ track: 4, y: -2, source: 7 }, st));
  assert.ok(!core.writeAllowed({ track: 4, y: -3, source: 9 }, st));
  assert.ok(!core.writeAllowed({ track: 4, y: -2, source: 9 }, Object.assign({}, st, { fresh: false })));
  assert.ok(!core.writeAllowed({ track: 4, y: -2, source: 9 }, Object.assign({}, st, { offline: true })));
  assert.ok(!core.writeAllowed({ track: 4, y: -2, source: 9 }, null));
  // the overall fader: send index 0, hardware output, source -1
  // (the overall fader's stale check is in its own test below)
});

test("holdLevels keeps the local level of held rows when the source is the same", () => {
  const prev = [{ source: 1, vol: 0.3, muted: false }, { source: 2, vol: 0.4, muted: false }];
  const next = [{ source: 1, vol: 1, muted: true }, { source: 5, vol: 1, muted: false }];
  const out = core.holdLevels(prev, next, (i) => true);
  assert.deepStrictEqual(out, [{ source: 1, vol: 0.3, muted: true }, { source: 5, vol: 1, muted: false }]);
  assert.deepStrictEqual(core.holdLevels(prev, next, (i) => false), next);
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

test("holdLevels keeps the on-screen mute of rows whose mute is held, and the read level otherwise", () => {
  const prev = [{ source: 1, vol: 0.3, muted: true }, { source: 2, vol: 0.4, muted: false }];
  const next = [{ source: 1, vol: 1, muted: false }, { source: 2, vol: 0.9, muted: true }];
  const out = core.holdLevels(prev, next, () => false, (i) => i === 0);
  assert.deepStrictEqual(out, [{ source: 1, vol: 1, muted: true }, { source: 2, vol: 0.9, muted: true }]);
  // level held and mute not held: independent
  assert.deepStrictEqual(core.holdLevels(prev, next, (i) => i === 1, () => false),
    [{ source: 1, vol: 1, muted: false }, { source: 2, vol: 0.4, muted: true }]);
  // a different source is never held
  assert.deepStrictEqual(core.holdLevels(prev, [{ source: 9, vol: 1, muted: false }], () => true, () => true), [{ source: 9, vol: 1, muted: false }]);
});

// ---- Overall fader (issue 06) ----
function ovLine(t, y, vol, other, flags) { return ["SEND", t, y, flags || 0, vol, "0.000000", other].join("\t"); }

test("parseOverallReply reads SEND/0 for the mix, only when it is a hardware output", () => {
  const text = ovLine(4, 0, "0.5", -1) + "\n";
  assert.deepStrictEqual(core.parseOverallReply(text, 4, 1), { vol: 0.5 });
  // an ordinary send's line (real track number last) never drives the overall fader
  assert.strictEqual(core.parseOverallReply(ovLine(4, 0, "0.5", 7) + "\n", 4, 1), null);
  // another track number
  assert.strictEqual(core.parseOverallReply(text, 5, 1), null);
  // other send indexes
  assert.strictEqual(core.parseOverallReply(ovLine(4, 1, "0.5", -1) + "\n" + ovLine(4, -1, "0.5", -1) + "\n", 4, 1), null);
  // no hardware output: a missing send looks like a silent hardware output, so it is not read
  assert.strictEqual(core.parseOverallReply(text, 4, 0), null);
  assert.strictEqual(core.parseOverallReply("", 4, 1), null);
  // found among receive lines in one reply
  assert.deepStrictEqual(core.parseOverallReply(ovLine(4, -1, "1", 9) + "\n" + text, 4, 2), { vol: 0.5 });
});

test("applyReceives still ignores the hardware output and ordinary sends", () => {
  const text = ovLine(4, 0, "0.5", -1) + "\n" + ovLine(4, 1, "0.7", 9) + "\n" + ovLine(4, -1, "0.3", 7) + "\n";
  assert.deepStrictEqual(core.applyReceives([], text, 4, 1), [{ source: 7, vol: 0.3, muted: false }]);
});

test("buildReadRequests puts the overall read first and keeps every URL under the limit", () => {
  const reqs = core.buildReadRequests(123, 60, 900);
  reqs.forEach((q) => assert.ok(("/_/" + q).length <= 900));
  const all = reqs.join(";").split(";");
  assert.strictEqual(all.length, 61);
  assert.strictEqual(all[0], "GET/TRACK/123/SEND/0");
  assert.strictEqual(all[1], "GET/TRACK/123/SEND/-1");
  assert.strictEqual(all[60], "GET/TRACK/123/SEND/-60");
  assert.deepStrictEqual(core.buildReadRequests(5, 0, 900), ["GET/TRACK/5/SEND/0"]);
  assert.deepStrictEqual(core.buildReadRequests(5, 1, 900), ["GET/TRACK/5/SEND/0;GET/TRACK/5/SEND/-1"]);
});

test("writeAllowed for the overall fader needs the mix track, a fresh read, online and a known level", () => {
  const st = { number: 4, receives: [], fresh: true, offline: false, overall: 1 };
  const t = { track: 4, y: 0, source: -1 };
  assert.ok(core.writeAllowed(t, st));
  assert.ok(core.writeAllowed(t, Object.assign({}, st, { overall: 0 })));
  assert.ok(!core.writeAllowed({ track: 5, y: 0, source: -1 }, st));
  assert.ok(!core.writeAllowed(t, Object.assign({}, st, { fresh: false })));
  assert.ok(!core.writeAllowed(t, Object.assign({}, st, { offline: true })));
  assert.ok(!core.writeAllowed(t, Object.assign({}, st, { overall: null })));
  assert.ok(!core.writeAllowed(t, Object.assign({}, st, { overall: undefined })));
  assert.ok(!core.writeAllowed(t, null));
  // only the first hardware output (index 0) and never an ordinary send or a source
  assert.ok(!core.writeAllowed({ track: 4, y: 1, source: 9 }, st));
  assert.ok(!core.writeAllowed({ track: 4, y: 1, source: -1 }, st));
  assert.ok(!core.writeAllowed({ track: 4, y: 0, source: 9 }, st));
  assert.ok(!core.writeAllowed({ track: 4, y: "0", source: -1 }, st));
  assert.ok(!core.writeAllowed({ track: 4, y: NaN, source: -1 }, st));
});

test("on a track with an ordinary send, the overall fader writes only send index 0", async () => {
  const sent = [];
  const drag = core.createFaderDrag({
    now: () => 0, setTimer: () => 1, clearTimer: () => {}, travelPx: 100,
    send: (cmd) => { sent.push(cmd); return Promise.resolve(""); },
    check: (t) => core.writeAllowed(t, { number: 4, receives: [{ source: 7, vol: 1, muted: false }], fresh: true, offline: false, overall: 1 })
  });
  assert.ok(drag.begin({ track: 4, y: 0, source: -1 }, 1, 100));
  drag.move(-20);
  drag.end();
  await new Promise((r) => setImmediate(r)); // the write in flight lands, then the final request goes
  assert.ok(sent.length >= 2);
  sent.forEach((cmd) => cmd.split(";").forEach((c) => assert.match(c, /^SET\/TRACK\/4\/SEND\/0\/VOL\/[0-9.]+e?$/)));
  assert.ok(/e$/.test(sent[sent.length - 1]));
});
