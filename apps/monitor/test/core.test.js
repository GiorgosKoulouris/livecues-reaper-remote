const test = require("node:test");
const assert = require("node:assert");
const core = require("../www/lcrr/monitor/js/core.js");
const faderCore = require("../../../shared/www/lcrr/shared/js/fader-core.js");

// Real reply shape, captured from real REAPER (Nov 2026).
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

test("dbText converts linear level to the dB value, with no unit", () => {
  assert.strictEqual(core.dbText(1), "0.0");
  assert.strictEqual(core.dbText(0.5), "-6.0");
  assert.strictEqual(core.dbText(Math.pow(10, 6 / 20)), "+6.0");
  assert.strictEqual(core.dbText(0), "-inf");
  assert.strictEqual(core.dbText(0.99999), "0.0");
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
    { n: 1, y: -1, source: 1, name: "Kick", color: 0x10000ff, vol: 0.5, db: "-6.0", muted: false },
    { n: 2, y: -2, source: 2, name: "Snare", color: 0, vol: 1, db: "0.0", muted: true }
  ]);
});

test("tracksKey changes when tracks are added, moved or renamed", () => {
  const a = tracksOf([trackLine(1, "A", 0, 0), trackLine(2, "B", 0, 0)]);
  assert.strictEqual(core.tracksKey(a), core.tracksKey(tracksOf([trackLine(1, "A", 0, 0), trackLine(2, "B", 0, 0)])));
  assert.notStrictEqual(core.tracksKey(a), core.tracksKey(tracksOf([trackLine(1, "B", 0, 0), trackLine(2, "A", 0, 0)])));
  assert.notStrictEqual(core.tracksKey(a), core.tracksKey(tracksOf([trackLine(1, "N", 0, 0), trackLine(2, "A", 0, 0), trackLine(3, "B", 0, 0)])));
});

// ---- Faders (issue 04) ----

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
  // the master fader: send index 0, hardware output, source -1
  // (the master fader's stale check is in its own test below)
});

test("holdLevels keeps the local level of held rows when the source is the same", () => {
  const prev = [{ source: 1, vol: 0.3, muted: false }, { source: 2, vol: 0.4, muted: false }];
  const next = [{ source: 1, vol: 1, muted: true }, { source: 5, vol: 1, muted: false }];
  const out = core.holdLevels(prev, next, (i) => true);
  assert.deepStrictEqual(out, [{ source: 1, vol: 0.3, muted: true }, { source: 5, vol: 1, muted: false }]);
  assert.deepStrictEqual(core.holdLevels(prev, next, (i) => false), next);
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

// ---- Master fader (issue 06) ----
function ovLine(t, y, vol, other, flags) { return ["SEND", t, y, flags || 0, vol, "0.000000", other].join("\t"); }

test("parseMasterReply reads SEND/0 for the mix, only when it is a hardware output", () => {
  const text = ovLine(4, 0, "0.5", -1) + "\n";
  assert.deepStrictEqual(core.parseMasterReply(text, 4, 1), { vol: 0.5 });
  // an ordinary send's line (real track number last) never drives the master fader
  assert.strictEqual(core.parseMasterReply(ovLine(4, 0, "0.5", 7) + "\n", 4, 1), null);
  // another track number
  assert.strictEqual(core.parseMasterReply(text, 5, 1), null);
  // other send indexes
  assert.strictEqual(core.parseMasterReply(ovLine(4, 1, "0.5", -1) + "\n" + ovLine(4, -1, "0.5", -1) + "\n", 4, 1), null);
  // no hardware output: a missing send looks like a silent hardware output, so it is not read
  assert.strictEqual(core.parseMasterReply(text, 4, 0), null);
  assert.strictEqual(core.parseMasterReply("", 4, 1), null);
  // found among receive lines in one reply
  assert.deepStrictEqual(core.parseMasterReply(ovLine(4, -1, "1", 9) + "\n" + text, 4, 2), { vol: 0.5 });
});

test("applyReceives still ignores the hardware output and ordinary sends", () => {
  const text = ovLine(4, 0, "0.5", -1) + "\n" + ovLine(4, 1, "0.7", 9) + "\n" + ovLine(4, -1, "0.3", 7) + "\n";
  assert.deepStrictEqual(core.applyReceives([], text, 4, 1), [{ source: 7, vol: 0.3, muted: false }]);
});

test("buildReadRequests puts the master read first and keeps every URL under the limit", () => {
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

test("writeAllowed for the master fader needs the mix track, a fresh read, online and a known level", () => {
  const st = { number: 4, receives: [], fresh: true, offline: false, master: 1 };
  const t = { track: 4, y: 0, source: -1 };
  assert.ok(core.writeAllowed(t, st));
  assert.ok(core.writeAllowed(t, Object.assign({}, st, { master: 0 })));
  assert.ok(!core.writeAllowed({ track: 5, y: 0, source: -1 }, st));
  assert.ok(!core.writeAllowed(t, Object.assign({}, st, { fresh: false })));
  assert.ok(!core.writeAllowed(t, Object.assign({}, st, { offline: true })));
  assert.ok(!core.writeAllowed(t, Object.assign({}, st, { master: null })));
  assert.ok(!core.writeAllowed(t, Object.assign({}, st, { master: undefined })));
  assert.ok(!core.writeAllowed(t, null));
  // only the first hardware output (index 0) and never an ordinary send or a source
  assert.ok(!core.writeAllowed({ track: 4, y: 1, source: 9 }, st));
  assert.ok(!core.writeAllowed({ track: 4, y: 1, source: -1 }, st));
  assert.ok(!core.writeAllowed({ track: 4, y: 0, source: 9 }, st));
  assert.ok(!core.writeAllowed({ track: 4, y: "0", source: -1 }, st));
  assert.ok(!core.writeAllowed({ track: 4, y: NaN, source: -1 }, st));
});

test("on a track with an ordinary send, the master fader writes only send index 0", async () => {
  const sent = [];
  const drag = faderCore.createFaderDrag({
    now: () => 0, setTimer: () => 1, clearTimer: () => {}, travelPx: 100,
    send: (cmd) => { sent.push(cmd); return Promise.resolve(""); },
    check: (t) => core.writeAllowed(t, { number: 4, receives: [{ source: 7, vol: 1, muted: false }], fresh: true, offline: false, master: 1 })
  });
  assert.ok(drag.begin({ track: 4, y: 0, source: -1 }, 1, 100));
  drag.move(-20);
  drag.end();
  await new Promise((r) => setImmediate(r)); // the write in flight lands, then the final request goes
  assert.ok(sent.length >= 2);
  sent.forEach((cmd) => cmd.split(";").forEach((c) => assert.match(c, /^SET\/TRACK\/4\/SEND\/0\/VOL\/[0-9.]+e?$/)));
  assert.ok(/e$/.test(sent[sent.length - 1]));
});

test("soloPlan mutes every other receive and unmutes the soloed one, recording what it changed", () => {
  const rx = [{ source: 1, muted: false }, { source: 2, muted: true }, { source: 3, muted: true }];
  const p = core.soloPlan(rx, 1, []);
  assert.deepStrictEqual(p.moves, [{ index: 0, to: true }, { index: 1, to: false }]);
  assert.deepStrictEqual(p.changes, [{ index: 0, source: 1, from: false, to: true }, { index: 1, source: 2, from: true, to: false }]);
});

test("soloPlan moving solo keeps the original states", () => {
  const first = [{ source: 1, muted: false }, { source: 2, muted: true }, { source: 3, muted: false }];
  const a = core.soloPlan(first, 0, []);
  const after = [{ source: 1, muted: false }, { source: 2, muted: true }, { source: 3, muted: true }];
  const b = core.soloPlan(after, 2, a.changes);
  assert.deepStrictEqual(b.moves, [{ index: 0, to: true }, { index: 2, to: false }]);
  assert.deepStrictEqual(b.changes, [{ index: 0, source: 1, from: false, to: true }]);
  assert.deepStrictEqual(core.restorePlan([{ source: 1, muted: true }, { source: 2, muted: true }, { source: 3, muted: false }], b.changes).moves, [{ index: 0, to: false }]);
});

test("restorePlan leaves receives changed by someone else or now another source", () => {
  const changes = [{ index: 0, source: 1, from: false, to: true }, { index: 1, source: 2, from: false, to: true }, { index: 2, source: 3, from: true, to: false }];
  const now = [{ source: 1, muted: false }, { source: 9, muted: true }, { source: 3, muted: false }];
  assert.deepStrictEqual(core.restorePlan(now, changes).moves, [{ index: 2, to: true }]);
  assert.deepStrictEqual(core.restorePlan([], changes).moves, []);
});
