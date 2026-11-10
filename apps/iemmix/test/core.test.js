const test = require("node:test");
const assert = require("node:assert");
const core = require("../www/lcrr/iemmix/js/core.js");

// Real reply shapes, captured from real REAPER (Nov 2026).
function trackLine(n, name, recv, hw, opts) {
  opts = opts || {};
  return ["TRACK", n, name, opts.flags || 0, "1.000000", "0.000000", -1500, -1500, "1.000000", 3, 0, recv, hw, opts.color || 0].join("\t");
}
function reply(lines) { return ["NTRACK\t" + lines.length].concat(["TRACK\t0\tMASTER\t0\t1\t0\t-1\t-1\t1\t3\t0\t0\t1\t0"], lines).join("\n") + "\n"; }
function sendLine(t, y, vol, other, flags) { return ["SEND", t, y, flags || 0, vol, "0.000000", other].join("\t"); }
function tracksOf(lines) { return core.parseTrackReply(reply(lines)).tracks; }

// Project: 1 Kick, 2 Snare, 3 Vox (muted), 4 IEM_Drums (2 recv), 5 IEM_Bass (1 recv)
const PROJECT = [trackLine(1, "Kick", 0, 0), trackLine(2, "Snare", 0, 0), trackLine(3, "Vox", 0, 0, { flags: 8, color: 0x10000ff }),
  trackLine(4, "IEM_Drums", 2, 1), trackLine(5, "IEM_Bass", 1, 1)];

test("parseTrackReply reads the mute flag and refuses a partial track set", () => {
  const r = core.parseTrackReply(reply(PROJECT));
  assert.deepStrictEqual(r.tracks.map((t) => t.muted), [false, false, true, false, false]);
  assert.strictEqual(r.tracks[2].color, 0x10000ff);
  assert.strictEqual(core.parseTrackReply("NTRACK\t3\n" + PROJECT[0] + "\n"), null);
});

test("listMixes applies Monitor's rule and marks duplicates not editable", () => {
  const m = core.listMixes(tracksOf([
    trackLine(1, "IEM_Gtr", 1, 1), trackLine(2, "IEM_Keys", 1, 1), trackLine(3, "IEM_Gtr", 2, 1),
    trackLine(4, "iem_x", 1, 1), trackLine(5, "IEM_", 1, 1), trackLine(6, "IEM_norecv", 0, 1), trackLine(7, "IEM_nohw", 1, 0)]));
  assert.deepStrictEqual(m.map((x) => [x.name, x.number, x.recvcnt, x.duplicate, x.editable]),
    [["Gtr", 1, 1, true, false], ["Keys", 2, 1, false, true], ["Gtr", 3, 2, true, false]]);
});

test("buildReadRequests covers every receive of every mix and splits under the limit", () => {
  const mixes = core.listMixes(tracksOf(PROJECT));
  assert.deepStrictEqual(core.buildReadRequests(mixes, 900), ["GET/TRACK/4/SEND/-1;GET/TRACK/4/SEND/-2;GET/TRACK/5/SEND/-1"]);
  const big = core.listMixes(tracksOf(Array.from({ length: 8 }, (_, i) => trackLine(40 + i, "IEM_M" + i, 24, 1))));
  const reqs = core.buildReadRequests(big, 900);
  assert.ok(reqs.length >= 2);
  reqs.forEach((r) => assert.ok(("/_/" + r).length <= 900));
  assert.strictEqual(reqs.join(";").split(";").length, 8 * 24);
});

// Drives the model the way the page does.
function started(lines) {
  const m = core.createGridModel();
  m.update(core.parseTrackReply(reply(lines || PROJECT)).tracks);
  return m;
}
function sweep(m, text) { const k = m.key(); m.apply(k, text); m.endSweep(k); }
const FULL = [sendLine(4, -1, 0.5, 1), sendLine(4, -2, 1, 3, 8), sendLine(5, -1, 2, 1)].join("\n");

test("rows are sources with a send to a listed mix, in project order, matched by source track index", () => {
  const m = started();
  sweep(m, [sendLine(4, -1, 1, 3), sendLine(4, -2, 0.5, 1), sendLine(5, -1, 1, 1)].join("\n"));
  const g = m.grid("");
  assert.deepStrictEqual(g.mixes.map((x) => x.name), ["Drums", "Bass"]);
  assert.deepStrictEqual(g.rows.map((r) => [r.source, r.name]), [[1, "Kick"], [3, "Vox"]]); // Snare has no send
  assert.deepStrictEqual(g.rows[0].cells.map((c) => c && c.db), ["-6.0", "0.0"]);
  assert.strictEqual(g.rows[1].cells[1], null);
});

test("a cell shows the level, dimmed (muted) when the send is muted", () => {
  const m = started();
  sweep(m, FULL);
  const g = m.grid("");
  assert.deepStrictEqual(g.rows.map((r) => r.source), [1, 3]);
  assert.strictEqual(g.rows[0].cells[0].muted, false);
  assert.strictEqual(g.rows[1].cells[0].muted, true);
  assert.strictEqual(g.rows[1].cells[0].db, "0.0");
  assert.strictEqual(g.rows[0].cells[1].db, "+6.0");
});

test("several sends of one pair show the first level with a 2x tag, read-only", () => {
  const m = started();
  sweep(m, [sendLine(4, -1, 0.5, 1), sendLine(4, -2, 1, 1), sendLine(5, -1, 1, 1)].join("\n"));
  const c = m.grid("").rows[0].cells[0];
  assert.deepStrictEqual([c.db, c.tag, c.sends, c.readOnly], ["-6.0", "2x", 2, true]);
  assert.strictEqual(m.grid("").rows[0].cells[1].tag, null);
});

test("a duplicated mix name shows both columns, every cell read-only", () => {
  const m = started([trackLine(1, "Kick", 0, 0), trackLine(2, "IEM_A", 1, 1), trackLine(3, "IEM_A", 1, 1)]);
  sweep(m, [sendLine(2, -1, 1, 1), sendLine(3, -1, 0.5, 1)].join("\n"));
  const g = m.grid("");
  assert.deepStrictEqual(g.mixes.map((x) => [x.number, x.editable]), [[2, false], [3, false]]);
  assert.deepStrictEqual(g.rows[0].cells.map((c) => [c.db, c.readOnly]), [["0.0", true], ["-6.0", true]]);
});

test("a listed mix with an unlisted track of the same name is marked duplicate and read-only, as Monitor refuses it", () => {
  const lines = [trackLine(1, "Kick", 0, 0), trackLine(2, "IEM_A", 1, 1), trackLine(3, "IEM_A", 0, 0), trackLine(4, "IEM_B", 1, 1)];
  const m = started(lines);
  sweep(m, [sendLine(2, -1, 1, 1), sendLine(4, -1, 1, 1)].join("\n"));
  assert.deepStrictEqual(core.listMixes(m.tracks()).map((x) => [x.name, x.number, x.duplicate, x.editable]), [["A", 2, true, false], ["B", 4, false, true]]);
  assert.deepStrictEqual(m.grid("").rows[0].cells.map((c) => c.readOnly), [true, false]);
  assert.deepStrictEqual(m.panel(core.selectSource(m.tracks(), 1)).rows.map((r) => r.readOnly), [true, false]);
  const st = m.writeState(true);
  assert.strictEqual(core.writeAllowed({ track: 2, y: -1, source: 1 }, st), false);
  assert.strictEqual(core.writeAllowed({ track: 4, y: -1, source: 1 }, st), true);
});

test("a muted source track is marked on its row", () => {
  const m = started();
  sweep(m, FULL);
  assert.deepStrictEqual(m.grid("").rows.map((r) => r.trackMuted), [false, true]);
  // the mute is read from the latest track list, with no new sweep and no layout change
  const t = core.parseTrackReply(reply([PROJECT[0], PROJECT[1], trackLine(3, "Vox", 0, 0), PROJECT[3], PROJECT[4]])).tracks;
  assert.strictEqual(m.update(t), false);
  assert.deepStrictEqual(m.grid("").rows.map((r) => r.trackMuted), [false, false]);
});

test("the name filter narrows rows, case-insensitively, and reports the total", () => {
  const m = started();
  sweep(m, FULL);
  const g = m.grid("  vOX ");
  assert.deepStrictEqual(g.rows.map((r) => r.name), ["Vox"]);
  assert.strictEqual(g.totalRows, 2);
});

test("a partial reply never removes a cell", () => {
  const m = started();
  sweep(m, FULL);
  // a later sweep answers only one line, another is a missing-send line (source -1), another is for a bad index
  sweep(m, [sendLine(4, -1, 0.25, 1), sendLine(4, -2, 0, -1), sendLine(5, -1, 1, 1, 0).replace("-1\t", "-9\t"), "TRANSPORT\t1\t2"].join("\n"));
  const g = m.grid("");
  assert.strictEqual(g.rows[0].cells[0].db, "-12.0"); // updated
  assert.strictEqual(g.rows[1].cells[0].db, "0.0");   // kept
  assert.strictEqual(g.rows[0].cells[1].db, "+6.0");  // kept
  assert.deepStrictEqual(g.rows.map((r) => r.source), [1, 3]);
});

test("the grid is null until something has been read, and rows appear as soon as every receive is known", () => {
  const m = started();
  assert.strictEqual(m.grid(""), null);
  m.apply(m.key(), sendLine(4, -1, 1, 1));
  assert.strictEqual(m.grid(""), null); // not every receive read yet, sweep not ended
  m.apply(m.key(), sendLine(4, -2, 1, 3) + "\n" + sendLine(5, -1, 1, 1));
  assert.notStrictEqual(m.grid(""), null);
});

test("an ended sweep shows what was read even when a request failed", () => {
  const m = started();
  m.apply(m.key(), sendLine(4, -1, 1, 1));
  m.endSweep(m.key());
  const g = m.grid("");
  assert.deepStrictEqual(g.rows.map((r) => r.source), [1]);
});

test("a track list that changes between sweeps drops old reads and a late reply for the old layout", () => {
  const m = started();
  const oldKey = m.key();
  sweep(m, FULL);
  // a track is inserted at 1: every source number shifts
  const moved = [trackLine(1, "New", 0, 0), trackLine(2, "Kick", 0, 0), trackLine(3, "Snare", 0, 0), trackLine(4, "Vox", 0, 0),
    trackLine(5, "IEM_Drums", 2, 1), trackLine(6, "IEM_Bass", 1, 1)];
  assert.strictEqual(m.update(core.parseTrackReply(reply(moved)).tracks), true);
  assert.strictEqual(m.grid(""), null);                      // no stale levels against shifted rows
  assert.strictEqual(m.apply(oldKey, FULL), false);          // a reply read under the old numbers is dropped
  assert.strictEqual(m.grid(""), null);
  sweep(m, [sendLine(5, -1, 1, 2), sendLine(5, -2, 1, 4), sendLine(6, -1, 1, 2)].join("\n"));
  assert.deepStrictEqual(m.grid("").rows.map((r) => r.name), ["Kick", "Vox"]);
});

test("a list with the same layout keeps the reads; a rename or a new receive starts over", () => {
  const m = started();
  sweep(m, FULL);
  assert.strictEqual(m.update(core.parseTrackReply(reply(PROJECT)).tracks), false);
  assert.notStrictEqual(m.grid(""), null);
  const renamed = PROJECT.slice(); renamed[0] = trackLine(1, "Kick In", 0, 0);
  assert.strictEqual(m.update(core.parseTrackReply(reply(renamed)).tracks), true);
  const more = PROJECT.slice(); more[4] = trackLine(5, "IEM_Bass", 2, 1);
  assert.strictEqual(m.update(core.parseTrackReply(reply(more)).tracks), true);
});

test("no mixes gives an empty grid once the (empty) sweep has ended", () => {
  const m = started([trackLine(1, "Kick", 0, 0)]);
  assert.notStrictEqual(m.grid(""), null); // nothing to read, so nothing is missing
  assert.deepStrictEqual(m.grid("").rows, []);
  assert.deepStrictEqual(m.requests(900).commands, []);
});

// ---- issue 04: the lock, the panel, the stale check, the holds ----
const fc = require("../../../shared/www/lcrr/shared/js/fader-core.js");
const MASTERS = [sendLine(4, 0, 0.8, -1), sendLine(5, 0, 1, -1)].join("\n");
function read(lines) { const m = started(); sweep(m, FULL); if (lines) m.apply(m.key(), lines); return m; }
// Vox (3) feeds Drums receive 2, Kick (1) feeds Drums 1 and Bass 1 (FULL: Drums -1 is Kick at 0.5, -2 is Vox muted, Bass -1 is Kick at 2).

test("canEdit needs a live connection and an Unlock", () => {
  assert.strictEqual(core.canEdit("connected", true), true);
  assert.strictEqual(core.canEdit("connected", false), false);
  assert.strictEqual(core.canEdit("offline", true), false);
  assert.strictEqual(core.canEdit("connecting", true), false);
});

// ---- the project marker (project ExtState): the form is unmeasured on real REAPER, see CONTEXT.md ----
const MARK = "GET/PROJEXTSTATE/LCRR_IEMMIX/project_id";
const markLine = (v) => "PROJEXTSTATE\tLCRR_IEMMIX\tproject_id\t" + v + "\n";

test("the marker's commands name one section and key, and the value is URL-encoded", () => {
  assert.strictEqual(core.markerReadCommand(), MARK);
  assert.strictEqual(core.markerWriteCommand("ab12"), "SET/PROJEXTSTATE/LCRR_IEMMIX/project_id/ab12");
  assert.strictEqual(core.markerWriteCommand("a b"), "SET/PROJEXTSTATE/LCRR_IEMMIX/project_id/a%20b");
});

test("parseMarker: the value, empty when never set, null when the reply has no marker line", () => {
  assert.strictEqual(core.parseMarker("TRANSPORT\t0\t0\n" + markLine("ab12")), "ab12");
  assert.strictEqual(core.parseMarker(markLine("ab12").replace("\n", "\r\n")), "ab12");
  assert.strictEqual(core.parseMarker(markLine("")), "");
  assert.strictEqual(core.parseMarker("PROJEXTSTATE\tLCRR_IEMMIX\tproject_id\n"), "");
  assert.strictEqual(core.parseMarker("TRANSPORT\t0\t0\n"), null);
  assert.strictEqual(core.parseMarker("PROJEXTSTATE\tOTHER\tproject_id\tzz\n"), null);
  assert.strictEqual(core.parseMarker("PROJEXTSTATE\tLCRR_IEMMIX\tother\tzz\n"), null);
  assert.strictEqual(core.parseMarker(""), null);
});

test("newProjectId is 16 URL-safe characters from the injected random", () => {
  assert.strictEqual(core.newProjectId(() => 0), "0000000000000000");
  assert.match(core.newProjectId(() => 0.999), /^[0-9a-z]{16}$/);
});

function fakeReaper(start) {
  const r = { stored: start, sent: [], store: true };
  r.send = (cmd) => {
    r.sent.push(cmd);
    let out = "";
    cmd.split(";").forEach((c) => {
      if (c.startsWith("SET/PROJEXTSTATE/") && r.store) r.stored = decodeURIComponent(c.split("/")[4]);
      if (c === MARK && r.stored !== null) out += markLine(r.stored);
    });
    return Promise.resolve(out);
  };
  return r;
}
const notRandom = () => 0.5;

test("Unlock in a project with an ID remembers it and writes nothing (a second tablet)", async () => {
  const r = fakeReaper("taken");
  assert.deepStrictEqual(await core.claimProject(r.send, notRandom), { ok: true, id: "taken", fresh: false });
  assert.deepStrictEqual(r.sent, [MARK]);
  assert.strictEqual(r.stored, "taken");
});

test("Unlock in a project with no ID writes a new one and needs the read-back to match", async () => {
  const r = fakeReaper("");
  const c = await core.claimProject(r.send, notRandom);
  assert.strictEqual(c.ok, true);
  assert.strictEqual(c.fresh, true);
  assert.strictEqual(c.id, r.stored);
  assert.deepStrictEqual(r.sent, [MARK, core.markerWriteCommand(c.id) + ";" + MARK]);
});

test("Unlock stays locked when the read-back differs or the write did not take", async () => {
  const lost = fakeReaper("");
  lost.store = false;
  assert.deepStrictEqual(await core.claimProject(lost.send, notRandom), { ok: false, reason: "mismatch" });
  const raced = fakeReaper("");
  const send = (cmd) => raced.send(cmd).then((t) => (cmd.startsWith("SET/") ? markLine("other tablet") : t));
  assert.deepStrictEqual(await core.claimProject(send, notRandom), { ok: false, reason: "mismatch" });
});

test("Unlock stays locked when the marker cannot be read, with no write", async () => {
  const none = fakeReaper(null);
  assert.deepStrictEqual(await core.claimProject(none.send, notRandom), { ok: false, reason: "unreadable" });
  assert.deepStrictEqual(none.sent, [MARK]);
  assert.deepStrictEqual(await core.claimProject(() => Promise.reject(new Error("x")), notRandom), { ok: false, reason: "unreadable" });
});

test("Unlock stays locked when the write's request fails or its reply has no marker", async () => {
  let n = 0;
  const failsSecond = () => (++n === 1 ? Promise.resolve(markLine("")) : Promise.reject(new Error("x")));
  assert.deepStrictEqual(await core.claimProject(failsSecond, notRandom), { ok: false, reason: "unreadable" });
  n = 0;
  const silentSecond = () => (++n === 1 ? Promise.resolve(markLine("")) : Promise.resolve(""));
  assert.deepStrictEqual(await core.claimProject(silentSecond, notRandom), { ok: false, reason: "unreadable" });
});

test("while unlocked the lock holds only on the same ID: changed, empty or absent relocks", () => {
  const claim = () => ({ ok: true, id: "abc", fresh: false });
  assert.strictEqual(core.markerHolds(claim(), markLine("abc")), true);
  assert.strictEqual(core.markerHolds(claim(), markLine("xyz")), false);
  assert.strictEqual(core.markerHolds(claim(), markLine("")), false);
  assert.strictEqual(core.markerHolds(claim(), "TRANSPORT\t0\t0\n"), false);
  assert.strictEqual(core.markerHolds(null, markLine("abc")), false);
});

test("two projects with identical track names are told apart by the marker", () => {
  const c = { ok: true, id: "song-one", fresh: false };
  assert.strictEqual(core.markerHolds(c, reply(PROJECT) + markLine("song-one")), true);
  assert.strictEqual(core.markerHolds(c, reply(PROJECT) + markLine("song-two")), false);
});

test("an ID just written tolerates the one empty reply of the poll already out, and only that", () => {
  const c = { ok: true, id: "abc", fresh: true };
  assert.strictEqual(core.markerHolds(c, markLine("")), true);
  assert.strictEqual(core.markerHolds(c, markLine("")), false);
  const d = { ok: true, id: "abc", fresh: true };
  assert.strictEqual(core.markerHolds(d, markLine("abc")), true);
  assert.strictEqual(core.markerHolds(d, markLine("")), false);
  assert.strictEqual(core.markerHolds({ ok: true, id: "abc", fresh: true }, markLine("xyz")), false);
  assert.strictEqual(core.markerHolds({ ok: true, id: "abc", fresh: true }, "no marker"), false);
});

test("the panel for a source lists its send in every mix that has one, by mix, with the first level of a repeated pair", () => {
  const m = read(MASTERS);
  const p = m.panel(core.selectSource(m.tracks(), 1));
  assert.strictEqual(p.kind, "source");
  assert.strictEqual(p.title, "Kick");
  assert.deepStrictEqual(p.rows.map((r) => [r.key, r.name, r.track, r.y, r.source, r.db, r.muted, r.readOnly]),
    [["4:1", "Drums", 4, -1, 1, "-6.0", false, false], ["5:1", "Bass", 5, -1, 1, "+6.0", false, false]]);
  assert.strictEqual(p.master, null);
  const v = m.panel(core.selectSource(m.tracks(), 3));
  assert.deepStrictEqual(v.rows.map((r) => [r.name, r.y, r.muted]), [["Drums", -2, true]]); // no send to Bass: no row
  assert.strictEqual(v.trackMuted, true);
});

test("a repeated pair and a duplicated mix have no fader (readOnly) in the panel", () => {
  const m = started([trackLine(1, "Kick", 0, 0), trackLine(2, "IEM_A", 2, 1), trackLine(3, "IEM_B", 1, 1), trackLine(4, "IEM_B", 1, 1)]);
  sweep(m, [sendLine(2, -1, 1, 1), sendLine(2, -2, 0.5, 1), sendLine(3, -1, 1, 1), sendLine(4, -1, 1, 1)].join("\n"));
  const p = m.panel(core.selectSource(m.tracks(), 1));
  assert.deepStrictEqual(p.rows.map((r) => [r.name, r.tag, r.readOnly]), [["A", "2x", true], ["B", null, true], ["B", null, true]]);
});

test("the panel for a mix lists its sources in project order and its master level", () => {
  const m = read(MASTERS);
  const p = m.panel(core.selectMix(m.tracks(), 4));
  assert.strictEqual(p.kind, "mix");
  assert.strictEqual(p.title, "Drums");
  assert.deepStrictEqual(p.rows.map((r) => [r.key, r.name, r.y, r.db]), [["4:1", "Kick", -1, "-6.0"], ["4:3", "Vox", -2, "0.0"]]);
  assert.deepStrictEqual([p.master.key, p.master.track, p.master.y, p.master.source, p.master.db, p.master.readOnly], ["4:master", 4, 0, -1, "-1.9", false]);
  const unread = read().panel(core.selectMix(m.tracks(), 4));
  assert.strictEqual(unread.master.vol, null);
});

test("a selection whose track moved or was renamed is gone, never another track's panel", () => {
  const m = read(MASTERS);
  const sel = core.selectSource(m.tracks(), 1);
  m.update(tracksOf([trackLine(1, "Other", 0, 0)].concat(PROJECT.slice(1))));
  assert.strictEqual(m.panel(sel), null);
  assert.strictEqual(core.selectSource(m.tracks(), 99), null);
  assert.strictEqual(core.selectMix(m.tracks(), 1), null); // not a listed mix
});

test("a cell the open panel holds keeps that panel and highlights its row", () => {
  const m = read(MASTERS), t = m.tracks();
  let s = core.selectCell(t, core.selectSource(t, 1), 1, 5);
  assert.deepStrictEqual([s.kind, s.number, s.focus], ["source", 1, { mix: 5, source: 1 }]);
  s = core.selectCell(t, core.selectMix(t, 4), 1, 4);
  assert.deepStrictEqual([s.kind, s.number, s.focus], ["mix", 4, { mix: 4, source: 1 }]);
  const p = m.panel(core.selectCell(t, core.selectSource(t, 1), 1, 5));
  assert.deepStrictEqual(p.rows.map((r) => r.focused), [false, true]);
});

test("a cell the open panel does not hold opens a panel of the same kind, and with none open its mix", () => {
  const t = read(MASTERS).tracks();
  let s = core.selectCell(t, core.selectMix(t, 4), 1, 5);
  assert.deepStrictEqual([s.kind, s.number, s.focus], ["mix", 5, { mix: 5, source: 1 }]);
  s = core.selectCell(t, core.selectSource(t, 1), 3, 4);
  assert.deepStrictEqual([s.kind, s.number, s.focus], ["source", 3, { mix: 4, source: 3 }]);
  s = core.selectCell(t, null, 3, 4);
  assert.deepStrictEqual([s.kind, s.number, s.focus], ["mix", 4, { mix: 4, source: 3 }]);
});

test("the cell already highlighted, or a mix that is gone, leaves the selection as it was", () => {
  const t = read(MASTERS).tracks();
  const s = core.selectCell(t, core.selectMix(t, 4), 1, 4);
  assert.strictEqual(core.selectCell(t, s, 1, 4), s);
  assert.strictEqual(core.selectCell(t, null, 1, 99), null);
});

test("the Source column's width stays usable, and is null when nothing is saved", () => {
  assert.strictEqual(core.sourceWidth(200.4, 1000), 200);
  assert.strictEqual(core.sourceWidth(10, 1000), 120);
  assert.strictEqual(core.sourceWidth(900, 1000), 480);
  assert.strictEqual(core.sourceWidth(400, 300), 204);   // room left for a mix column
  assert.strictEqual(core.sourceWidth(400, 150), 120);
  assert.strictEqual(core.sourceWidth(400, 0), 400);     // the grid is still hidden
  assert.strictEqual(core.sourceWidth(NaN, 1000), null);
  assert.strictEqual(core.sourceWidth(null, 1000), null);
});

test("the grid's shape ignores levels and mutes, and follows what its DOM is built from", () => {
  const cell = (o) => Object.assign({ vol: 1, db: "0.0", muted: false, sends: 1, tag: null, readOnly: false }, o);
  const grid = (c, name) => ({ totalRows: 1, mixes: [{ number: 4, name: "Anna", duplicate: false }], rows: [{ source: 1, name: name || "Kick", color: 0, trackMuted: false, cells: [c] }] });
  const base = core.gridShape(grid(cell()));
  assert.strictEqual(core.gridShape(grid(cell({ vol: 0.5, db: "-6.0", muted: true }))), base);
  assert.notStrictEqual(core.gridShape(grid(cell(), "Snare")), base);
  assert.notStrictEqual(core.gridShape(grid(null)), base);
  assert.notStrictEqual(core.gridShape(grid(cell({ tag: "2x", readOnly: true }))), base);
});

test("the stale check: a write goes only while unlocked and the row still addresses the same send", () => {
  const m = read(MASTERS);
  const t = { track: 4, y: -1, source: 1 };
  const ok = (target, canEdit) => core.writeAllowed(target, m.writeState(canEdit === undefined ? true : canEdit));
  assert.strictEqual(ok(t), true);
  assert.strictEqual(ok(t, false), false);                              // locked or offline
  assert.strictEqual(ok({ track: 4, y: -1, source: 3 }), false);        // another source at that index
  assert.strictEqual(ok({ track: 5, y: -2, source: 1 }), false);        // no such receive
  assert.strictEqual(ok({ track: 6, y: -1, source: 1 }), false);        // not a mix
  assert.strictEqual(ok({ track: 4, y: 1, source: 3 }), false);         // an ordinary send is never written
  assert.strictEqual(ok({ track: 4, y: 0, source: -1 }), true);         // the master, once read
  m.update(tracksOf(PROJECT)); // same layout: reads kept
  assert.strictEqual(ok(t), true);
  m.update(tracksOf([trackLine(1, "New", 0, 0)].concat(PROJECT.map((l, i) => l.replace(/^TRACK\t\d+/, "TRACK\t" + (i + 2))))));
  assert.strictEqual(ok(t), false);                                     // layout changed, nothing read under it yet
  assert.strictEqual(core.writeAllowed(t, null), false);
});

test("the stale check refuses a repeated pair, a duplicated mix and an unread master", () => {
  const m = started([trackLine(1, "Kick", 0, 0), trackLine(2, "IEM_A", 2, 1), trackLine(3, "IEM_B", 1, 1), trackLine(4, "IEM_B", 1, 1)]);
  sweep(m, [sendLine(2, -1, 1, 1), sendLine(2, -2, 0.5, 1), sendLine(3, -1, 1, 1), sendLine(4, -1, 1, 1)].join("\n"));
  const st = m.writeState(true);
  assert.deepStrictEqual([{ track: 2, y: -1, source: 1 }, { track: 3, y: -1, source: 1 }, { track: 2, y: 0, source: -1 }].map((t) => core.writeAllowed(t, st)), [false, false, false]);
});

test("a read does not move a level held by a drag or a write in flight, and keeps the slot's source check", () => {
  const m = read(MASTERS);
  const held = (track, y, field) => track === 4 && y === -1 && field === "vol";
  m.apply(m.key(), [sendLine(4, -1, 0.1, 1, 8), sendLine(4, -2, 0.25, 3), sendLine(4, 0, 0.3, -1)].join("\n"), held);
  const p = m.panel(core.selectMix(m.tracks(), 4));
  assert.deepStrictEqual(p.rows.map((r) => [r.db, r.muted]), [["-6.0", true], ["-12.0", false]]); // Kick: level held, mute taken; Vox: both taken
  assert.strictEqual(p.master.db, "-10.5");                                                  // the master is not held here
  m.apply(m.key(), sendLine(4, 0, 1, -1), (track, y) => y === 0);
  assert.strictEqual(m.panel(core.selectMix(m.tracks(), 4)).master.db, "-10.5");             // held master keeps its level
  m.apply(m.key(), sendLine(4, -1, 0.25, 99), held);                                        // another source now at that index: taken whole
  assert.deepStrictEqual(m.panel(core.selectMix(m.tracks(), 4)).rows.filter((r) => r.source === 99).map((r) => r.db), ["-12.0"]);
});

test("setLocal moves a level on screen before the read confirms it", () => {
  const m = read(MASTERS);
  m.setLocal(4, -1, { vol: 0.25 });
  m.setLocal(4, 0, { vol: 2 });
  const p = m.panel(core.selectMix(m.tracks(), 4));
  assert.deepStrictEqual([p.rows[0].db, p.master.db], ["-12.0", "+6.0"]);
});

test("the panel is read from its visible sends, in requests under the URL limit", () => {
  const m = read(MASTERS);
  const p = m.panel(core.selectMix(m.tracks(), 4));
  assert.deepStrictEqual(core.buildPanelRequests(p, 900), ["GET/TRACK/4/SEND/-1;GET/TRACK/4/SEND/-2;GET/TRACK/4/SEND/0"]);
  const s = m.panel(core.selectSource(m.tracks(), 1));
  assert.deepStrictEqual(core.buildPanelRequests(s, 900), ["GET/TRACK/4/SEND/-1;GET/TRACK/5/SEND/-1"]);
  assert.strictEqual(core.buildPanelRequests(s, 40).length, 2);
});

test("a drag cancelled by a track or send change ends with no final write", () => {
  const m = read(MASTERS);
  const sent = [], timers = [];
  let t = 0;
  const target = { track: 4, y: -1, source: 1 };
  const drag = fc.createFaderDrag({ now: () => t, setTimer: (fn) => timers.push(fn), clearTimer() {}, send: (c) => { sent.push(c); return Promise.resolve(); },
    check: (x) => core.writeAllowed(x, m.writeState(true)), gateMs: 50, slopPx: 3, travelPx: 200 });
  assert.strictEqual(drag.begin(target, 0.5, 200), true);
  assert.ok(drag.move(20));
  assert.strictEqual(sent.length, 1);
  // the receive at y -1 is now another source's (layout read again under the same numbers)
  m.apply(m.key(), sendLine(4, -1, 1, 3));
  t = 100;
  drag.move(40);
  drag.end();
  assert.strictEqual(sent.length, 1); // nothing after the change, not even the final e
});

// ---- pan and mute on the panel (issue 05) ----
function panLine(t, y, pan, other, flags) { return ["SEND", t, y, flags || 0, "1", pan, other].join("\t"); }

test("parseSendReply reads the pan field and skips a line whose pan is unusable", () => {
  const out = core.parseSendReply([panLine(4, -1, "-0.500000", 1), panLine(4, -2, "1.5", 3), panLine(4, -3, "x", 3)].join("\n"));
  assert.deepStrictEqual(out.map((s) => [s.y, s.pan]), [[-1, -0.5], [-2, 1.5]]);
});

test("the panel row carries the pan, and setLocal moves it on screen", () => {
  const m = read(MASTERS);
  m.apply(m.key(), panLine(4, -1, "-0.25", 1));
  const p = () => m.panel(core.selectMix(m.tracks(), 4));
  assert.strictEqual(p().rows[0].pan, -0.25);
  m.setLocal(4, -1, { pan: 0.75 });
  assert.strictEqual(p().rows[0].pan, 0.75);
});

test("a read does not move a pan or a mute held by a control, and takes the other fields", () => {
  const m = read(MASTERS);
  m.apply(m.key(), panLine(4, -1, "0.5", 1));
  const heldPan = (track, y, field) => track === 4 && y === -1 && field === "pan";
  m.apply(m.key(), panLine(4, -1, "-1", 1, 8), heldPan);
  let r = m.panel(core.selectMix(m.tracks(), 4)).rows[0];
  assert.deepStrictEqual([r.pan, r.muted], [0.5, true]);
  const heldMute = (track, y, field) => track === 4 && y === -1 && field === "muted";
  m.apply(m.key(), panLine(4, -1, "-1", 1, 0), heldMute);
  r = m.panel(core.selectMix(m.tracks(), 4)).rows[0];
  assert.deepStrictEqual([r.pan, r.muted], [-1, true]);
  assert.deepStrictEqual(core.holdSlot({ source: 1, vol: 1, muted: false, pan: 0.2 }, { source: 2, vol: 1, muted: true, pan: 0.9 }, () => true, 4, -1).pan, 0.9); // another source: taken whole
});

test("pan and mute writes pass the same lock gate and stale check as the level", () => {
  const m = read(MASTERS);
  const row = { track: 4, y: -1, source: 1 }, pair = { track: 4, y: -1, source: 3 };
  assert.strictEqual(core.writeAllowed(row, m.writeState(true)), true);
  assert.strictEqual(core.writeAllowed(row, m.writeState(false)), false);   // locked or offline
  assert.strictEqual(core.writeAllowed(pair, m.writeState(true)), false);   // another source at that index
  const w = fc.createMuteWriter({ check: (t) => core.writeAllowed(t, m.writeState(false)), send: () => { throw new Error("sent"); } });
  assert.strictEqual(w.press(row, false), false);
  const sent = [];
  const w2 = fc.createMuteWriter({ check: (t) => core.writeAllowed(t, m.writeState(true)), send: (c) => { sent.push(c); return Promise.resolve(); } });
  assert.strictEqual(w2.press(row, false), true);
  assert.deepStrictEqual(sent, ["SET/TRACK/4/SEND/-1/MUTE/1"]);
});

test("a repeated pair is read-only, so its panel row has no pan or mute control", () => {
  const m = started();
  sweep(m, [sendLine(5, -1, 1, 2), sendLine(5, -2, 1, 2), sendLine(4, -1, 1, 1)].join("\n"));
  const rows = m.panel(core.selectMix(m.tracks(), 5)).rows;
  assert.ok(rows.every((r) => r.readOnly === (r.sends > 1)));
});

test("setPanCommand writes the value, clamps to -1..1 and ends with e", () => {
  assert.strictEqual(core.setPanCommand(3, -2, 0.25, false), "SET/TRACK/3/SEND/-2/PAN/0.25");
  assert.strictEqual(core.setPanCommand(3, -2, -0.5, true), "SET/TRACK/3/SEND/-2/PAN/-0.5e");
  assert.strictEqual(core.setPanCommand(3, -2, 1.5, false), "SET/TRACK/3/SEND/-2/PAN/1");
  assert.strictEqual(core.setPanCommand(3, -2, -7, false), "SET/TRACK/3/SEND/-2/PAN/-1");
  assert.strictEqual(core.setPanCommand(3, -2, 0, false), "SET/TRACK/3/SEND/-2/PAN/0");
  assert.strictEqual(core.setPanCommand(3, -2, -1e-9, false), "SET/TRACK/3/SEND/-2/PAN/0");
  assert.strictEqual(core.setPanCommand(3, -2, NaN, false), "SET/TRACK/3/SEND/-2/PAN/0");
  assert.ok(!/e-/.test(core.setPanCommand(1, -1, 1e-9, false)));
});

test("pan mapping: position 0..1 is -1..1, linear, with centre at 0.5", () => {
  assert.strictEqual(core.panValue(0), -1);
  assert.strictEqual(core.panValue(0.5), 0);
  assert.strictEqual(core.panValue(1), 1);
  assert.strictEqual(core.panValue(2), 1);
  assert.strictEqual(core.panValue(-1), -1);
  assert.strictEqual(core.panPos(-1), 0);
  assert.strictEqual(core.panPos(0), 0.5);
  assert.strictEqual(core.panPos(0.5), 0.75);
  assert.strictEqual(core.panPos(1.5), 1); // REAPER stores anything: the thumb parks at the end
  assert.strictEqual(core.panPos(-3), 0);
  assert.strictEqual(core.panPos(NaN), 0.5);
});

test("the shared drag controller writes pan with this app's command and mapping, the value then e in one request", async () => {
  const sent = [];
  const d = fc.createFaderDrag({ now: () => 0, setTimer: () => 0, clearTimer() {}, send: (c) => { sent.push(c); return Promise.resolve(); }, check: () => true,
    command: core.setPanCommand, toValue: core.panValue, toPos: core.panPos, gateMs: 50, slopPx: 0, travelPx: 100 });
  d.begin({ track: 2, y: -1, source: 1 }, 0);
  d.move(10);
  await Promise.resolve(); await Promise.resolve();
  d.move(-20);
  d.end();
  assert.deepStrictEqual(sent, ["SET/TRACK/2/SEND/-1/PAN/0.2", "SET/TRACK/2/SEND/-1/PAN/-0.4;SET/TRACK/2/SEND/-1/PAN/-0.4e"]);
});

test("panText shows centre, left and right in percent, and a dash before a pan is read", () => {
  assert.deepStrictEqual([0, -0.25, 1, -1, 0.004, 1.5, undefined].map(core.panText), ["C", "L25", "R100", "L100", "C", "R100", "–"]);
});
