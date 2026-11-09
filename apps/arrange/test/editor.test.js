const test = require("node:test");
const assert = require("node:assert");
const ed = require("../www/lcrr/arrange/js/editor.js");

const regions = [{ name: "A" }, { name: "B" }, { name: "C" }, { name: "D" }];

test("splitLists: in order, left out in timeline order, unknown names flagged", () => {
  const s = ed.splitLists([{ name: "C", headroom: 2 }, { name: "Ghost" }, { name: "A", headroom: 0 }], regions);
  assert.deepStrictEqual(s.inList.map((r) => [r.name, r.headroom, r.inProject]), [["C", 2, true], ["Ghost", 0, false], ["A", 0, true]]);
  assert.deepStrictEqual(s.leftOut.map((r) => r.name), ["B", "D"]);
});

test("slotForDrop: final slot, null when nothing changes", () => {
  assert.strictEqual(ed.slotForDrop(0, 0, 4), null);
  assert.strictEqual(ed.slotForDrop(0, 1, 4), null);
  assert.strictEqual(ed.slotForDrop(0, 2, 4), 2);
  assert.strictEqual(ed.slotForDrop(0, 4, 4), 4);
  assert.strictEqual(ed.slotForDrop(3, 0, 4), 1);
  assert.strictEqual(ed.slotForDrop(3, 3, 4), null);
  assert.strictEqual(ed.slotForDrop(2, 1, 4), 2);
  assert.strictEqual(ed.slotForDrop(5, 1, 4), null);
});

test("slotForStep stops at the ends", () => {
  assert.strictEqual(ed.slotForStep(0, -1, 3), null);
  assert.strictEqual(ed.slotForStep(0, 1, 3), 2);
  assert.strictEqual(ed.slotForStep(2, 1, 3), null);
  assert.strictEqual(ed.slotForStep(2, -1, 3), 2);
});

test("gapAt counts row midpoints above the pointer", () => {
  assert.strictEqual(ed.gapAt(0, [10, 30, 50]), 0);
  assert.strictEqual(ed.gapAt(40, [10, 30, 50]), 2);
  assert.strictEqual(ed.gapAt(99, [10, 30, 50]), 3);
  assert.strictEqual(ed.gapAt(5, []), 0);
});

test("parseHeadroom", () => {
  const ok = (t, n) => assert.deepStrictEqual(ed.parseHeadroom(t), { ok: true, seconds: n }, t);
  ok("4", 4); ok("+4", 4); ok("-2.5", -2.5); ok("2,5", 2.5); ok(" 4 s ", 4); ok("", 0); ok("-0", 0); ok(".5", 0.5); ok("1.23456", 1.235);
  ["abc", "1e3", "--1", "+", "1 2", "4 m"].forEach((t) => assert.strictEqual(ed.parseHeadroom(t).ok, false, t));
});

test("formatSeconds and stepHeadroom", () => {
  assert.strictEqual(ed.formatSeconds(4), "4");
  assert.strictEqual(ed.formatSeconds(-2.5), "-2.5");
  assert.strictEqual(ed.formatSeconds(0), "0");
  assert.strictEqual(ed.stepHeadroom(0.5, 1), 1.5);
  assert.strictEqual(ed.stepHeadroom(1, -1), 0);
  assert.strictEqual(ed.stepHeadroom(0.1 + 0.2, 1), 1.3);
});

test("checkName and copyName", () => {
  assert.deepStrictEqual(ed.checkName("  Show ", ["A"]), { ok: true, name: "Show" });
  assert.strictEqual(ed.checkName("  ", []).code, "name_empty");
  assert.strictEqual(ed.checkName("A", ["A"]).code, "name_taken");
  assert.strictEqual(ed.copyName("A", ["A"]), "A copy");
  assert.strictEqual(ed.copyName("A", ["A", "A copy"]), "A copy 2");
});

// An editor over a scripted client.
function scripted(replies) {
  const sent = [];
  const base = { status: "ok", project: { name: "P", path: "/p.rpp" }, sidecar: "ok", revision: "r1", canonical: true,
    regions, arrangements: [{ name: "X", entries: [{ name: "A", headroom: 0 }, { name: "B", headroom: 1 }] }, { name: "Y", entries: [] }] };
  const client = {
    arrangements: () => Promise.resolve(replies.read ? replies.read() : base),
    edit: (b, op, f) => { sent.push({ b, op, f }); const r = replies.edit.shift(); return r instanceof Error ? Promise.reject(r) : Promise.resolve(r); }
  };
  return { client, sent };
}

test("load, then a move folds the reply and tells subscribers", async () => {
  const { client, sent } = scripted({ edit: [{ status: "ok", name: "X", names: ["X", "Y"], revision: "r2", entries: [{ name: "B", headroom: 1 }, { name: "A", headroom: 0 }] }] });
  const e = ed.createEditor(client);
  const seen = [];
  e.subscribe((o) => seen.push(o));
  assert.strictEqual((await e.load()).changed, true);
  assert.strictEqual((await e.load()).changed, false);
  const out = await e.dispatch("move", { arrangement: "X", region: "B", slot: "1" });
  assert.strictEqual(out.kind, "ok");
  assert.deepStrictEqual(sent[0].b, { project: "/p.rpp", revision: "r1", rewrite: false });
  assert.deepStrictEqual(out.before.map((x) => x.name), ["A", "B"]);
  assert.deepStrictEqual(out.after.map((x) => x.name), ["B", "A"]);
  assert.strictEqual(e.view().revision, "r2");
  assert.strictEqual(seen.length, 1);
});

test("new, rename, duplicate, delete keep the list in the reply's order", async () => {
  const { client } = scripted({ edit: [
    { status: "ok", name: "Aaa", names: ["Aaa", "X", "Y"], revision: "r2" },
    { status: "ok", name: "Z", names: ["Aaa", "X", "Z"], revision: "r3" },
    { status: "ok", name: "Copy", from: "X", names: ["Aaa", "Copy", "X", "Z"], revision: "r4", entries: [{ name: "A", headroom: 0 }, { name: "B", headroom: 1 }] },
    { status: "ok", name: "X", names: ["Aaa", "Copy", "Z"], revision: "r5", deleted_entries: [] }
  ] });
  const e = ed.createEditor(client);
  await e.load();
  await e.dispatch("new", { name: "Aaa" });
  assert.deepStrictEqual(e.names(), ["Aaa", "X", "Y"]);
  await e.dispatch("rename", { arrangement: "Y", name: "Z" });
  assert.deepStrictEqual(e.names(), ["Aaa", "X", "Z"]);
  const d = await e.dispatch("duplicate", { arrangement: "X", name: "Copy" });
  assert.deepStrictEqual(e.names(), ["Aaa", "Copy", "X", "Z"]);
  assert.strictEqual(d.after.length, 2);
  await e.dispatch("delete", { arrangement: "X" });
  assert.deepStrictEqual(e.names(), ["Aaa", "Copy", "Z"]);
});

test("the rewrite question is returned, and the retry carries rewrite", async () => {
  const { client, sent } = scripted({ edit: [{ status: "confirm", confirm: { code: "rewrite" } }, { status: "ok", name: "X", names: ["X", "Y"], revision: "r2", entries: [] }] });
  const e = ed.createEditor(client);
  await e.load();
  const first = await e.dispatch("clear_headroom", { arrangement: "X" });
  assert.deepStrictEqual(first, { kind: "confirm", code: "rewrite" });
  assert.strictEqual(e.view().revision, "r1");
  const second = await e.dispatch("clear_headroom", { arrangement: "X" }, { rewrite: true });
  assert.strictEqual(second.kind, "ok");
  assert.strictEqual(sent[1].b.rewrite, true);
  assert.strictEqual(e.view().canonical, true);
});

test("a stale refusal reloads; other refusals and failures do not", async () => {
  let reads = 0;
  const { client } = scripted({ read: () => { reads++; return { status: "ok", project: { path: "/p.rpp" }, sidecar: "ok", revision: "r" + reads, regions, arrangements: [] }; },
    edit: [{ status: "refused", error: { code: "sidecar_changed" } }, { status: "refused", error: { code: "name_taken" } }, Object.assign(new Error("x"), { code: "request_too_long" })] });
  const e = ed.createEditor(client);
  await e.load();
  const a = await e.dispatch("new", { name: "N" });
  assert.strictEqual(a.kind, "stale");
  assert.strictEqual(reads, 2);
  assert.strictEqual(e.view().revision, "r2");
  assert.strictEqual((await e.dispatch("new", { name: "N" })).kind, "refused");
  assert.deepStrictEqual(await e.dispatch("new", { name: "N" }), { kind: "failed", code: "request_too_long" });
  assert.strictEqual(reads, 2);
});

// ---- Undo (issue 08) --------------------------------------------------------------------------------------------

// A fake bridge that applies the nine operations to an in-memory sidecar, with the revision check.
function fakeBridge(initial) {
  let arrs = JSON.parse(JSON.stringify(initial)), rev = 1, fail = null;
  const sent = [];
  const get = (n) => arrs.find((a) => a.name === n);
  const reply = (a, extra) => { rev++; return Object.assign({ status: "ok", revision: "r" + rev, names: arrs.map((x) => x.name).sort(), name: a && a.name, entries: a && a.entries.map((e) => ({ ...e })) }, extra); };
  const client = {
    arrangements: () => Promise.resolve({ status: "ok", project: { path: "/p.rpp" }, sidecar: "ok", revision: "r" + rev, canonical: true, regions, arrangements: JSON.parse(JSON.stringify(arrs)) }),
    edit: (b, op, f) => {
      sent.push({ op, f });
      if (fail) { const e = fail; fail = null; return Promise.resolve({ status: "refused", error: { code: e } }); }
      if (b.revision !== "r" + rev) return Promise.resolve({ status: "refused", error: { code: "sidecar_changed" } });
      const a = get(f.arrangement);
      if (op !== "new" && !a) return Promise.resolve({ status: "refused", error: { code: "arrangement_not_found" } });
      const idx = a && f.region != null ? a.entries.findIndex((e) => e.name === f.region) : -1;
      if (op === "move") { const [e] = a.entries.splice(idx, 1); a.entries.splice(Number(f.slot) - 1, 0, e); return Promise.resolve(reply(a)); }
      if (op === "set_headroom") { a.entries[idx].headroom = Number(f.headroom); return Promise.resolve(reply(a)); }
      if (op === "add") { a.entries.splice(f.slot ? Number(f.slot) - 1 : a.entries.length, 0, { name: f.region, headroom: 0 }); return Promise.resolve(reply(a)); }
      if (op === "remove") { a.entries.splice(idx, 1); return Promise.resolve(reply(a)); }
      if (op === "clear_headroom") { a.entries.forEach((e) => { e.headroom = 0; }); return Promise.resolve(reply(a)); }
      if (op === "new") { arrs.push({ name: f.name, entries: [] }); return Promise.resolve(reply(get(f.name))); }
      if (op === "duplicate") { arrs.push({ name: f.name, entries: a.entries.map((e) => ({ ...e })) }); return Promise.resolve(reply(get(f.name))); }
      if (op === "rename") { a.name = f.name; return Promise.resolve(reply(a)); }
      if (op === "delete") { arrs = arrs.filter((x) => x !== a); return Promise.resolve(reply(null)); }
    }
  };
  return { client, sent, snapshot: () => JSON.parse(JSON.stringify(arrs)), touch: () => { rev++; }, failNext: (c) => { fail = c; } };
}

const start = [
  { name: "X", entries: [{ name: "A", headroom: 0 }, { name: "B", headroom: 2.5 }, { name: "C", headroom: -1 }] },
  { name: "Y", entries: [{ name: "D", headroom: 0 }] }
];

const edits = [
  ["move", { arrangement: "X", region: "C", slot: "1" }],
  ["move", { arrangement: "X", region: "A", slot: "3" }],
  ["set_headroom", { arrangement: "X", region: "B", headroom: "7" }],
  ["set_headroom", { arrangement: "X", region: "B", headroom: "0" }],
  ["add", { arrangement: "X", region: "D" }],
  ["add", { arrangement: "X", region: "D", slot: "2" }],
  ["remove", { arrangement: "X", region: "A" }],
  ["remove", { arrangement: "X", region: "B" }],
  ["remove", { arrangement: "X", region: "C" }],
  ["clear_headroom", { arrangement: "X" }],
  ["new", { name: "Fresh" }],
  ["duplicate", { arrangement: "X", name: "X copy" }],
  ["rename", { arrangement: "X", name: "Renamed" }]
];

for (const [op, fields] of edits) {
  test("undo: " + op + " " + JSON.stringify(fields) + " then its inverse returns the same Arrangements", async () => {
    const bridge = fakeBridge(start);
    const e = ed.createEditor(bridge.client);
    await e.load();
    const out = await e.dispatch(op, fields);
    assert.strictEqual(out.kind, "ok");
    assert.notDeepStrictEqual(bridge.snapshot(), start);
    assert.strictEqual(e.undoDepth(), 1);
    assert.strictEqual((await e.undo()).kind, "undone");
    assert.deepStrictEqual(bridge.snapshot().sort((a, b) => a.name.localeCompare(b.name)), start);
    assert.strictEqual(e.undoDepth(), 0);
    assert.deepStrictEqual(e.names(), ["X", "Y"]); // the page's own state agrees
    assert.deepStrictEqual(e.entriesOf("X"), start[0].entries);
  });
}

test("inverseOf: shapes", () => {
  const before = [{ name: "A", headroom: 0 }, { name: "B", headroom: 2 }];
  const inv = (operation, fields, b, name) => ed.inverseOf({ kind: "ok", operation, fields, name: name || fields.arrangement, before: b === undefined ? before : b });
  assert.deepStrictEqual(inv("move", { arrangement: "X", region: "B", slot: "1" }).steps, [{ operation: "move", fields: { arrangement: "X", region: "B", slot: "2" } }]);
  assert.deepStrictEqual(inv("remove", { arrangement: "X", region: "B" }).steps.map((s) => [s.operation, s.fields.slot || s.fields.headroom]), [["add", "2"], ["set_headroom", "2"]]);
  assert.strictEqual(inv("remove", { arrangement: "X", region: "A" }).steps.length, 1);
  assert.strictEqual(inv("clear_headroom", { arrangement: "X" }).steps.length, 1);
  assert.strictEqual(inv("clear_headroom", { arrangement: "X" }, [{ name: "A", headroom: 0 }]), null);
  assert.strictEqual(inv("delete", { arrangement: "X" }), null);
  assert.deepStrictEqual(inv("rename", { arrangement: "X", name: "Z" }, null, "Z").steps, [{ operation: "rename", fields: { arrangement: "Z", name: "X" } }]);
});

test("undo runs newest first, an Undo is not itself undoable, and an empty stack is empty", async () => {
  const bridge = fakeBridge(start);
  const e = ed.createEditor(bridge.client);
  await e.load();
  assert.strictEqual((await e.undo()).kind, "empty");
  await e.dispatch("move", { arrangement: "X", region: "C", slot: "1" });
  await e.dispatch("set_headroom", { arrangement: "X", region: "C", headroom: "9" });
  assert.strictEqual(e.undoDepth(), 2);
  await e.undo();
  assert.strictEqual(e.undoDepth(), 1);
  await e.undo();
  assert.strictEqual(e.undoDepth(), 0);
  assert.deepStrictEqual(bridge.snapshot(), start);
});

test("an edit sent from elsewhere on the page is undoable the same way (issue 09)", async () => {
  const bridge = fakeBridge(start);
  const e = ed.createEditor(bridge.client);
  await e.load();
  await e.dispatch("clear_headroom", { arrangement: "X" });
  assert.deepStrictEqual(e.entriesOf("X").map((x) => x.headroom), [0, 0, 0]);
  await e.undo();
  assert.deepStrictEqual(e.entriesOf("X").map((x) => x.headroom), [0, 2.5, -1]);
  assert.strictEqual(bridge.sent.filter((s) => s.op === "set_headroom").length, 2);
});

test("a stale Undo reloads and drops the whole stack", async () => {
  const bridge = fakeBridge(start);
  const e = ed.createEditor(bridge.client);
  await e.load();
  await e.dispatch("move", { arrangement: "X", region: "C", slot: "1" });
  await e.dispatch("rename", { arrangement: "Y", name: "Why" });
  bridge.touch();
  const out = await e.undo();
  assert.strictEqual(out.kind, "stale");
  assert.strictEqual(e.undoDepth(), 0);
  assert.strictEqual(e.view().revision, "r" + 4);
});

test("a changed file seen by a re-read drops the stack; an unchanged one keeps it", async () => {
  const bridge = fakeBridge(start);
  const e = ed.createEditor(bridge.client);
  await e.load();
  await e.dispatch("move", { arrangement: "X", region: "C", slot: "1" });
  await e.load();
  assert.strictEqual(e.undoDepth(), 1);
  bridge.touch();
  await e.load();
  assert.strictEqual(e.undoDepth(), 0);
});

test("Delete is not undoable and drops entries about the deleted Arrangement", async () => {
  const bridge = fakeBridge(start);
  const e = ed.createEditor(bridge.client);
  await e.load();
  await e.dispatch("move", { arrangement: "X", region: "C", slot: "1" });
  await e.dispatch("move", { arrangement: "Y", region: "D", slot: "1" });
  assert.strictEqual(e.undoDepth(), 2);
  await e.dispatch("delete", { arrangement: "X" });
  assert.strictEqual(e.undoDepth(), 1);
  assert.strictEqual(e.peekUndo().arrangement, "Y");
});

test("a refused Undo drops its entry; a failed one keeps it", async () => {
  const bridge = fakeBridge(start);
  const e = ed.createEditor(bridge.client);
  await e.load();
  await e.dispatch("move", { arrangement: "X", region: "C", slot: "1" });
  await e.dispatch("move", { arrangement: "X", region: "B", slot: "1" });
  bridge.failNext("would_be_invalid");
  const refused = await e.undo();
  assert.strictEqual(refused.kind, "refused");
  assert.strictEqual(e.undoDepth(), 1);
  const failing = ed.createEditor({ arrangements: bridge.client.arrangements, edit: () => Promise.reject(Object.assign(new Error("x"), { code: "unreachable" })) });
  await failing.load();
  assert.strictEqual(failing.undoDepth(), 0);
});

test("a multi-edit Undo that fails part-way reports partial and drops the entry", async () => {
  const bridge = fakeBridge(start);
  const e = ed.createEditor(bridge.client);
  await e.load();
  await e.dispatch("remove", { arrangement: "X", region: "B" });
  const real = bridge.client.edit;
  let n = 0;
  bridge.client.edit = (b, op, f) => (++n === 2 ? Promise.resolve({ status: "refused", error: { code: "would_be_invalid" } }) : real(b, op, f));
  const out = await e.undo();
  assert.strictEqual(out.kind, "partial");
  assert.strictEqual(e.undoDepth(), 0);
});

test("a failed Undo (no answer) keeps its entry", async () => {
  const bridge = fakeBridge(start);
  const e = ed.createEditor(bridge.client);
  await e.load();
  await e.dispatch("move", { arrangement: "X", region: "C", slot: "1" });
  const real = bridge.client.edit;
  bridge.client.edit = () => Promise.reject(Object.assign(new Error("x"), { code: "unreachable" }));
  assert.deepStrictEqual(await e.undo(), { kind: "failed", code: "unreachable" });
  assert.strictEqual(e.undoDepth(), 1);
  bridge.client.edit = real;
  assert.strictEqual((await e.undo()).kind, "undone");
});

test("clearHeadroomOffer: only after an Apply that applied a non-zero Headroom", () => {
  const ok = (extra) => Object.assign({ status: "ok", noop: false, name: "This", headroom: [{ name: "Outro", requested: 300, resolved: 296 }] }, extra);
  assert.deepStrictEqual(ed.clearHeadroomOffer("apply", ok()), { arrangement: "This" });
  assert.deepStrictEqual(ed.clearHeadroomOffer("apply", ok({ headroom: [{ name: "A", requested: 0, resolved: 0 }, { name: "B", requested: -2, resolved: 0 }] })), { arrangement: "This" });
  assert.strictEqual(ed.clearHeadroomOffer("zero", ok()), null);
  assert.strictEqual(ed.clearHeadroomOffer("cancel", ok()), null);
  assert.strictEqual(ed.clearHeadroomOffer("apply", { status: "cancelled" }), null);
  assert.strictEqual(ed.clearHeadroomOffer(null, ok({ headroom: [{ name: "A", requested: 0, resolved: 0 }] })), null);
  assert.strictEqual(ed.clearHeadroomOffer(null, ok({ headroom: [] })), null);
  assert.strictEqual(ed.clearHeadroomOffer("apply", ok({ noop: true })), null);
  assert.strictEqual(ed.clearHeadroomOffer("apply", { status: "refused", error: { code: "x" } }), null);
  assert.strictEqual(ed.clearHeadroomOffer("apply", null), null);
});

test("clear_headroom after an Apply is one undoable edit", async () => {
  const bridge = fakeBridge([{ name: "X", entries: [{ name: "A", headroom: 3 }, { name: "B", headroom: 0 }] }]);
  const e = ed.createEditor(bridge.client);
  await e.load();
  assert.strictEqual((await e.dispatch("clear_headroom", { arrangement: "X" })).kind, "ok");
  assert.strictEqual(e.undoDepth(), 1);
});
