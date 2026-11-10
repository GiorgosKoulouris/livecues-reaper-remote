const test = require("node:test");
const assert = require("node:assert");
const reaper = require("../www/lcrr/shared/js/reaper.js");

test("parseTransport reads state and position from a TRANSPORT line", () => {
  const t = reaper.parseTransport("TRANSPORT\t1\t12.5\t0\t0:12.500\t7.2.50\n");
  assert.deepStrictEqual(t, { playstate: 1, position: 12.5 });
});

test("parseTransport finds the line among other output and tolerates CRLF", () => {
  const t = reaper.parseTransport("REGION_LIST\r\nTRANSPORT\t5\t3\t0\tx\ty\r\nREGION_LIST_END\r\n");
  assert.deepStrictEqual(t, { playstate: 5, position: 3 });
});

test("parseTransport returns null for missing or malformed lines", () => {
  assert.strictEqual(reaper.parseTransport(""), null);
  assert.strictEqual(reaper.parseTransport("TRANSPORT\tx\ty"), null);
  assert.strictEqual(reaper.parseTransport("TRANSPORT\t1"), null);
});

test("stateName maps the playstate bitfield", () => {
  assert.strictEqual(reaper.stateName(0), "stopped");
  assert.strictEqual(reaper.stateName(1), "playing");
  assert.strictEqual(reaper.stateName(2), "paused");
  assert.strictEqual(reaper.stateName(5), "recording");
  assert.strictEqual(reaper.stateName(6), "paused");
});

test("parseRegions reads REGION lines between the list markers, sorted by start", () => {
  const text = "TRANSPORT\t0\t0\t0\tx\ty\nREGION_LIST\nREGION\tChorus\t2\t30.5\t60\t0\nREGION\tIntro\t1\t0\t30.5\t0\nREGION_LIST_END\n";
  assert.deepStrictEqual(reaper.parseRegions(text), [
    { name: "Intro", id: 1, start: 0, end: 30.5, color: 0 },
    { name: "Chorus", id: 2, start: 30.5, end: 60, color: 0 }
  ]);
});

test("parseRegions allows empty names, skips malformed lines, and returns [] without a list", () => {
  const text = "REGION_LIST\nREGION\t\t1\t5\t9\t0\nREGION\tbad\t2\tx\t9\t0\nREGION_LIST_END";
  assert.deepStrictEqual(reaper.parseRegions(text), [{ name: "", id: 1, start: 5, end: 9, color: 0 }]);
  assert.deepStrictEqual(reaper.parseRegions("TRANSPORT\t0\t0"), []);
});

test("hasRegionList distinguishes an empty list from a missing one", () => {
  assert.strictEqual(reaper.hasRegionList("REGION_LIST\nREGION_LIST_END"), true);
  assert.strictEqual(reaper.hasRegionList("TRANSPORT\t0\t0"), false);
});

test("colorToCss decodes the web interface RGB color (blue in the low byte), null when uncolored", () => {
  assert.strictEqual(reaper.colorToCss(0), null);
  assert.strictEqual(reaper.colorToCss(0x1000000 | (0xff << 16) | (0x20 << 8) | 0x30), "rgb(255,32,48)");
  assert.strictEqual(reaper.colorToCss(16777471), "rgb(0,0,255)"); // REAPER showed this marker blue;
  assert.strictEqual(reaper.colorToCss(undefined), null);
});

test("seekPlayCommand seeks then plays in one request", () => {
  assert.strictEqual(reaper.seekPlayCommand(12.5), "SET/POS/12.5;1007");
});

test("parseMarkers reads MARKER lines, sorted by position, ignoring region lines", () => {
  const text = "TRANSPORT\t0\t0\t0\tx\ty\nMARKER_LIST\nMARKER\tKey change\t7\t60\t16777471\nMARKER\t\t8\t130\t0\nMARKER\tCount-in\t6\t8\t0\nMARKER_LIST_END\nREGION_LIST\nREGION\tIntro\t1\t0\t16\t0\nREGION_LIST_END\n";
  assert.deepStrictEqual(reaper.parseMarkers(text), [
    { name: "Count-in", id: 6, position: 8, color: 0 },
    { name: "Key change", id: 7, position: 60, color: 16777471 },
    { name: "", id: 8, position: 130, color: 0 }
  ]);
});

test("parseMarkers skips malformed lines; hasMarkerList detects the block", () => {
  assert.deepStrictEqual(reaper.parseMarkers("MARKER_LIST\nMARKER\tx\t1\tbad\t0\nMARKER_LIST_END"), []);
  assert.deepStrictEqual(reaper.parseMarkers("TRANSPORT\t0\t0"), []);
  assert.strictEqual(reaper.hasMarkerList("MARKER_LIST\nMARKER_LIST_END"), true);
  assert.strictEqual(reaper.hasMarkerList("REGION_LIST\nREGION_LIST_END"), false);
});

const track = (number, name, recvcnt, hwoutcnt) => ({ number, name, recvcnt, hwoutcnt });

test("listMixes: exact IEM_ prefix, a name after it, a receive and a hardware output", () => {
  const m = reaper.listMixes([track(1, "Kick", 0, 0), track(2, "IEM_Drums", 1, 1), track(3, "iem_x", 1, 1), track(4, "IEM_", 1, 1), track(5, "IEM_norecv", 0, 1), track(6, "IEM_nohw", 1, 0)]);
  assert.deepStrictEqual(m, [{ name: "Drums", number: 2, duplicate: false }]);
});

test("listMixes marks a name shared by listed tracks, and only those", () => {
  const m = reaper.listMixes([track(1, "IEM_Gtr", 1, 1), track(2, "IEM_Keys", 1, 1), track(3, "IEM_Gtr", 2, 1), track(4, "IEM_Keys", 0, 0)]);
  assert.deepStrictEqual(m.map((x) => [x.name, x.number, x.duplicate]), [["Gtr", 1, true], ["Keys", 2, false], ["Gtr", 3, true]]);
});

test("tracksNamed finds every track of that mix name, listed or not", () => {
  const tracks = [track(1, "IEM_A", 1, 1), track(2, "IEM_A", 0, 0), track(3, "IEM_a", 1, 1), track(4, "A", 1, 1)];
  assert.deepStrictEqual(reaper.tracksNamed(tracks, "A").map((t) => t.number), [1, 2]);
  assert.deepStrictEqual(reaper.tracksNamed(tracks, "B"), []);
});

test("dbText gives one decimal with a sign, no -0.0, and -inf at silence", () => {
  assert.deepStrictEqual([0, 1, 0.5, 2, 0.0001, 0.99999].map(reaper.dbText), ["-inf", "0.0", "-6.0", "+6.0", "-80.0", "0.0"]);
});
