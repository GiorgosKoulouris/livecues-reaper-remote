const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const snaps = require("../www/lcrr/iemmix/js/snapshots.js");
const bridge = require("../www/lcrr/iemmix/js/bridge.js");

// The bridge's own recorded replies (IEM Setup's contract fixture): the page must read what the bridge says.
const replies = {};
fs.readFileSync(path.join(__dirname, "../../iem/test/fixtures/bridge-replies.txt"), "utf8").split("\n").filter(Boolean)
  .forEach((line) => { const at = line.indexOf("\t"); replies[line.slice(0, at)] = JSON.parse(line.slice(at + 1)); });

test("the bridge state follows the heartbeat", () => {
  assert.strictEqual(snaps.bridgeState("unknown"), "checking");
  assert.strictEqual(snaps.bridgeState("running"), "ready");
  assert.strictEqual(snaps.bridgeState("stopped"), "down");
});

test("a snapshot write is allowed only unlocked, connected and with the bridge running", () => {
  assert.strictEqual(snaps.canWrite("connected", true, "ready"), true);
  assert.strictEqual(snaps.canWrite("connected", false, "ready"), false);
  assert.strictEqual(snaps.canWrite("offline", true, "ready"), false);
  assert.strictEqual(snaps.canWrite("connected", true, "down"), false);
  assert.strictEqual(snaps.canWrite("connected", true, "checking"), false);
});

test("with the bridge down the list is not read and the note says why; the lock note comes after", () => {
  assert.strictEqual(snaps.canRead("connected", "down"), false);
  assert.strictEqual(snaps.canRead("connected", "ready"), true);
  assert.strictEqual(snaps.canRead("offline", "ready"), false);
  assert.match(snaps.note("connected", true, "down", ""), /bridge, which is not running/);
  assert.match(snaps.note("connected", true, "down", ""), /still work/);
  assert.match(snaps.note("connected", true, "checking", ""), /Looking for/);
  assert.match(snaps.note("connected", false, "ready", ""), /Locked/);
  assert.strictEqual(snaps.note("connected", true, "ready", ""), snaps.UNDO_NOTE + snaps.RECALL_NOTE);
  assert.strictEqual(snaps.note("connected", true, "ready", "", "Recalled."), "Recalled.");
  assert.strictEqual(snaps.note("connected", true, "ready", "Failed.", "Recalled."), "Failed.");
  assert.strictEqual(snaps.note("connected", true, "ready", "Give the snapshot a name."), "Give the snapshot a name.");
  assert.strictEqual(snaps.note("offline", true, "down", ""), "");
});

test("a name is trimmed, never empty, free of control characters, not too long and unique", () => {
  assert.deepStrictEqual(snaps.checkName("  Show  ", []), { name: "Show" });
  assert.deepStrictEqual(snaps.checkName("   ", []), { code: "empty_name" });
  assert.deepStrictEqual(snaps.checkName(undefined, []), { code: "empty_name" });
  assert.deepStrictEqual(snaps.checkName("a\tb", []), { code: "bad_name" });
  assert.deepStrictEqual(snaps.checkName("x".repeat(41), []), { code: "name_too_long" });
  assert.deepStrictEqual(snaps.checkName("x".repeat(40), []), { name: "x".repeat(40) });
  assert.deepStrictEqual(snaps.checkName("Show ", ["Show"]), { code: "duplicate_name" });
  assert.deepStrictEqual(snaps.checkName("show", ["Show"]), { name: "show" });
  // Characters count, not code units.
  assert.deepStrictEqual(snaps.checkName("\u{1F3A4}".repeat(40), [], () => true).code, undefined);
});

test("the longest name still fits one request, and a name that would not fit is refused before it is sent", () => {
  assert.ok(bridge.nameFits("x".repeat(40)));
  assert.ok(bridge.nameFits("\u{1F3A4}".repeat(40))); // the widest case: 4-byte characters, 900 characters exactly
  assert.deepStrictEqual(snaps.checkName("Show", [], () => false), { code: "name_too_long" });
});

test("the recorded replies read as a list, and every refusal has words", () => {
  assert.deepStrictEqual(snaps.readList(replies.snapshots_empty), []);
  const list = snaps.readList(replies.snapshots_saved);
  assert.deepStrictEqual(list.map((s) => s.name), ["Soundcheck", "Show"]);
  assert.strictEqual(snaps.counts(list[0]), "4 mixes, 7 sends");
  assert.strictEqual(snaps.counts({ mixes: 1, sends: 1 }), "1 mix, 1 send");
  assert.strictEqual(snaps.readList(replies.snapshot_delete_ok), null);
  assert.strictEqual(snaps.readList(null), null);
  ["snapshot_save_duplicate", "snapshot_save_empty_name", "snapshot_save_nothing", "snapshot_save_not_found",
    "snapshot_delete_not_found"].forEach((name) => {
    const text = snaps.errorText(replies[name].error);
    assert.ok(text && !/failed/.test(text), name + ": " + text);
  });
  ["request_too_long", "unreachable", "no_reply"].forEach((code) => assert.ok(!/failed/.test(snaps.errorText({ code }))));
  assert.match(snaps.errorText({ code: "odd" }), /\(odd\)/);
});

// The client speaks to LCRR_IEM through the shared transport, and sends only the name.
function rig() {
  const urls = [];
  let t = 0, n = 0;
  const c = bridge.createClient({
    fetchText: (url) => { urls.push(url); return Promise.resolve(""); },
    newId: () => "id" + (++n), now: () => t, wait: (ms) => { t += ms; return Promise.resolve(); }
  });
  return { c, urls };
}
function sent(urls) { return urls.filter((u) => u.indexOf("/_/SET/") === 0).map((u) => decodeURIComponent(decodeURIComponent(u))); }

test("save, overwrite and delete send only the name, in IEM Setup's section", async () => {
  const { c, urls } = rig();
  await c.save("Soundcheck", false).catch(() => {});
  await c.save("Soundcheck", true).catch(() => {});
  await c.remove("Soundcheck").catch(() => {});
  await c.snapshots().catch(() => {});
  const s = sent(urls);
  assert.ok(urls[0].indexOf("/_/SET/EXTSTATE/LCRR_IEM/req/") === 0);
  assert.match(s[0], /cmd=snapshot_save&name=Soundcheck$/);
  assert.match(s[1], /cmd=snapshot_save&name=Soundcheck&overwrite=1$/);
  assert.match(s[2], /cmd=snapshot_delete&name=Soundcheck$/);
  assert.match(s[3], /cmd=snapshots$/);
  urls.forEach((u) => assert.ok(("/_/" + u).length < 900 + 4));
});

const mixesReply = (names) => ({ status: "ok", command: "state",
  mixes: names.map((name, i) => ({ guid: "{G" + i + "}", name })) });

test("a mix is found by name in the bridge's state reply, and only when exactly one has it", () => {
  assert.deepStrictEqual(snaps.findMix(mixesReply(["A", "B"]), "B"), { guid: "{G1}" });
  assert.deepStrictEqual(snaps.findMix(mixesReply(["A", "B"]), "C"), { code: "mix_unknown" });
  assert.deepStrictEqual(snaps.findMix(mixesReply(["A", "A"]), "A"), { code: "mix_ambiguous" });
  assert.deepStrictEqual(snaps.findMix({ status: "refused" }, "A"), { code: "unreachable" });
  assert.deepStrictEqual(snaps.findMix(null, "A"), { code: "unreachable" });
  const real = replies.state_band.mixes[0];
  assert.deepStrictEqual(snaps.findMix(replies.state_band, real.name), { guid: real.guid });
});

test("the recall result says what was written and what was skipped", () => {
  assert.strictEqual(snaps.recallText({ mixes: 2, sends: 3, skipped: 0, missing: 0 }, "Show", null),
    "Recalled “Show”: 2 mixes, 3 sends.");
  assert.strictEqual(snaps.recallText({ mixes: 1, sends: 1, skipped: 0, missing: 0 }, "Show", null),
    "Recalled “Show”: 1 mix, 1 send.");
  assert.strictEqual(snaps.recallText({ mixes: 1, sends: 4, skipped: 0, missing: 0 }, "Show", "Drums"),
    "Recalled “Show” to Drums: 4 sends.");
  assert.strictEqual(snaps.recallText({ mixes: 1, sends: 2, skipped: 1, missing: 0 }, "Show", null),
    "Recalled “Show”: 1 mix, 2 sends. 1 level was skipped because its source, mix or output is gone or no longer routed.");
  assert.strictEqual(snaps.recallText({ mixes: 1, sends: 2, skipped: 3, missing: 2 }, "Show", null),
    "Recalled “Show”: 1 mix, 2 sends. 3 levels were skipped because its source, mix or output is gone or no longer routed; 2 mixes are no longer in the project.");
  assert.strictEqual(snaps.recallText({ mixes: 0, sends: 0, skipped: 2, missing: 0 }, "Show", "Drums"),
    "Nothing was recalled from “Show” to Drums. 2 levels were skipped because its source, mix or output is gone or no longer routed.");
});

test("the recorded recall replies read in words, and every recall refusal has words", () => {
  assert.match(snaps.recallText(replies.snapshot_recall_ok, "Soundcheck", null), /^Recalled “Soundcheck”: 4 mixes, 7 sends\.$/);
  assert.match(snaps.recallText(replies.snapshot_recall_mix, "Soundcheck", "Drummer"), /^Recalled “Soundcheck” to Drummer: 4 sends\.$/);
  assert.match(snaps.recallText(replies.snapshot_recall_skipped, "Soundcheck", null), /1 level was skipped/);
  assert.match(snaps.errorText(replies.snapshot_recall_not_found.error), /no longer saved/);
  assert.match(snaps.errorText(replies.snapshot_recall_track_gone.error), /no longer in the project/);
  ["mix_not_saved", "not_a_mix", "mix_unknown", "mix_ambiguous"].forEach((code) =>
    assert.doesNotMatch(snaps.errorText({ code }), /request failed/));
});

test("recall sends the name, and for one mix its GUID, to the bridge in IEM Setup's section", async () => {
  // The clock must advance with wait(), or the transport's reply timeout never comes.
  const { c, urls } = rig();
  await c.recall("Show", "{G1}").catch(() => {});
  await c.recall("Show").catch(() => {});
  await c.state().catch(() => {});
  const s = sent(urls);
  assert.match(s[0], /cmd=snapshot_recall&name=Show&mix=\{G1\}$/);
  assert.match(s[1], /cmd=snapshot_recall&name=Show$/);
  assert.match(s[2], /cmd=state$/);
  urls.forEach((u) => assert.ok(("/_/" + u).length < 900 + 4));
});

test("one-mix recall: the selected mix's short name finds the mix in the bridge's recorded state reply", () => {
  const core = require("../www/lcrr/iemmix/js/core.js");
  const line = (n, name) => ["TRACK", n, name, 0, "1.000000", "0.000000", -1500, -1500, "1.000000", 3, 0, 1, 1, 0].join("\t");
  const real = replies.state_band.mixes.filter((m) => m.name === "Drummer")[0];
  const text = "NTRACK\t2\n" + ["TRACK\t0\tMASTER\t0\t1\t0\t-1\t-1\t1\t3\t0\t0\t1\t0", line(1, "Kick"), line(2, "IEM_Drummer")].join("\n") + "\n";
  const tracks = core.parseTrackReply(text).tracks;
  const sel = core.selectMix(tracks, 2);
  assert.strictEqual(sel.name, "IEM_Drummer"); // the guard stays the full track name
  assert.strictEqual(core.selectedMixName(tracks, sel), "Drummer");
  assert.deepStrictEqual(snaps.findMix(replies.state_band, core.selectedMixName(tracks, sel)), { guid: real.guid });
  assert.strictEqual(core.selectedMixName(tracks, core.selectSource(tracks, 1)), null);
  assert.strictEqual(core.selectedMixName(tracks, null), null);
  assert.strictEqual(core.selectedMixName(tracks, { kind: "mix", number: 1, name: "Kick" }), null);
});

test("the key labels and hold titles are the page's words: recall by the short name with its undo note, the rest not undoable", () => {
  assert.strictEqual(snaps.keyLabel("recallAll"), "Recall all");
  assert.strictEqual(snaps.keyLabel("recallMix", "Drummer"), "Recall Drummer");
  assert.strictEqual(snaps.keyLabel("overwrite"), "Overwrite");
  assert.strictEqual(snaps.keyLabel("delete"), "Delete");
  assert.strictEqual(snaps.holdTitle("recallAll", null, "Show"), "Hold to Recall all “Show”. One undo step in REAPER.");
  assert.strictEqual(snaps.holdTitle("recallMix", "Drummer", "Show"), "Hold to Recall Drummer “Show”. One undo step in REAPER.");
  assert.strictEqual(snaps.holdTitle("overwrite", null, "Show"), "Hold to overwrite “Show”. This cannot be undone.");
  assert.strictEqual(snaps.holdTitle("delete", null, "Show"), "Hold to delete “Show”. This cannot be undone.");
});
