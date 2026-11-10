const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const restore = require("../www/lcrr/snapshots/js/restore.js");
const words = require("../www/lcrr/snapshots/js/words.js");
const client = require("../www/lcrr/snapshots/js/client.js");

const replies = {};
fs.readFileSync(path.join(__dirname, "fixtures/bridge-replies.txt"), "utf8").split("\n").filter(Boolean).forEach((line) => {
  const tab = line.indexOf("\t");
  replies[line.slice(0, tab)] = JSON.parse(line.slice(tab + 1));
});

test("the ticks start as the spec says: all on except FX on/off", () => {
  const ticks = restore.defaults();
  assert.strictEqual(ticks.fx, false);
  assert.ok(["levels", "pans", "mutes", "solos", "polarity", "sends"].every((k) => ticks[k] === true));
  assert.strictEqual(restore.field(ticks), "LPMSRE");
});

test("the compact field follows the ticks, and is empty when none is on", () => {
  assert.strictEqual(restore.field({ fx: true }), "F");
  assert.strictEqual(restore.field({ levels: true, sends: true }), "LE");
  assert.strictEqual(restore.field({}), "");
});

test("every tick has a label", () => {
  restore.TICKS.forEach((t) => assert.ok(words.tick(t.key).length > 0, t.key));
});

test("the recorded restore reply is pushed through to its note", () => {
  const result = restore.readResult(replies.snapshot_restore);
  assert.deepStrictEqual(result, { name: "Verse", tracks: 3, sends: 3, skipped: 0 });
  assert.strictEqual(words.restoreNote(result), "Restored “Verse”: 3 tracks, 3 sends written.");
  assert.strictEqual(words.restoreNote({ name: "V", tracks: 1, sends: 1, skipped: 2 }),
    "Restored “V”: 1 track, 1 send written. 2 saved items were skipped, gone from the project.");
  assert.ok(words.restoreNote({ name: "V", tracks: 0, sends: 0, skipped: 1 }).startsWith("Nothing was restored"));
  assert.strictEqual(restore.readResult(replies.snapshot_restore_no_ticks), null);
  assert.strictEqual(restore.readResult(replies.snapshot_save), null);
});

test("the recorded restore refusals are worded", () => {
  ["snapshot_restore_no_ticks", "snapshot_restore_not_found"].forEach((name) => {
    assert.strictEqual(replies[name].status, "refused", name);
    assert.ok(!words.error(replies[name].error).startsWith("Something went wrong"), name);
  });
  assert.ok(!words.error({ code: "bad_ticks" }).startsWith("Something went wrong"));
});

test("restore(name, ticks) sends the name and the compact ticks", async () => {
  const urls = [];
  let n = 0, t = 0;
  const c = client.createClient({
    fetchText: (url) => {
      urls.push(url);
      return Promise.resolve(url.indexOf("/_/SET/") === 0 ? "" : 'EXTSTATE\tLCRR_SNAPSHOTS\tres\tid1|{"status":"ok"}\n');
    },
    newId: () => "id" + (++n), now: () => t, wait: (ms) => { t += ms; return Promise.resolve(); }
  });
  await c.restore("Verse", "LPE");
  assert.ok(decodeURIComponent(urls[0]).endsWith("|cmd=snapshot_restore&name=Verse&ticks=LPE"));
});

test("In-ears is a tick that starts off, and sends the letter I", () => {
  const ticks = restore.defaults();
  assert.strictEqual(ticks.inears, false);
  assert.strictEqual(restore.field(ticks), "LPMSRE");
  assert.strictEqual(restore.field({ inears: true }), "I");
  assert.strictEqual(words.tick("inears"), "In-ears");
  assert.ok(/even with In-ears off/.test(words.ui("tickNote")));
});

test("the recorded In-ears restore reply is pushed through to its note", () => {
  const result = restore.readResult(replies.snapshot_restore_in_ears);
  assert.ok(result && result.tracks >= 0);
  assert.ok(words.restoreNote(result).length > 0);
});
