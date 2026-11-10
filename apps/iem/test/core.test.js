const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const core = require("../www/lcrr/iem/js/core.js");

// Real replies, recorded from the Lua service (apps/iem/spec/bridge_contract_spec.lua).
const replies = {};
fs.readFileSync(path.join(__dirname, "fixtures/bridge-replies.txt"), "utf8").split("\n").filter(Boolean).forEach((line) => {
  const tab = line.indexOf("\t");
  replies[line.slice(0, tab)] = JSON.parse(line.slice(tab + 1));
});
const band = () => core.readState(replies.state_band);

test("the render gate defers a rebuild while a hold is active and paints once, latest state, when it ends", () => {
  let paints = 0;
  const gate = core.createRenderGate(() => { paints++; });
  gate.request();
  assert.strictEqual(paints, 1);
  gate.begin();
  gate.request(); gate.request(); gate.request();
  assert.strictEqual(paints, 1);
  assert.ok(gate.active() && gate.pending());
  gate.end();
  assert.strictEqual(paints, 2);
  assert.ok(!gate.active() && !gate.pending());
  gate.end(); // a stray end changes nothing
  assert.strictEqual(paints, 2);
  gate.begin(); gate.end(); // nothing asked meanwhile: no repaint
  assert.strictEqual(paints, 2);
});

test("with two holds down the rebuild waits for the last", () => {
  let paints = 0;
  const gate = core.createRenderGate(() => { paints++; });
  gate.begin(); gate.begin();
  gate.request();
  gate.end();
  assert.strictEqual(paints, 0);
  gate.end();
  assert.strictEqual(paints, 1);
});

test("dbText turns linear gain into dB with one decimal and a sign", () => {
  assert.strictEqual(core.dbText(1), "0.0");
  assert.strictEqual(core.dbText(0.5), "-6.0");
  assert.strictEqual(core.dbText(2), "+6.0");
  assert.strictEqual(core.dbText(0), "-inf");
  assert.strictEqual(core.dbText(0.9999), "0.0");
});

test("connectionPhase: offline wins, then connecting until a heartbeat decides", () => {
  assert.strictEqual(core.connectionPhase(true, true, "running"), "offline");
  assert.strictEqual(core.connectionPhase(false, false, "unknown"), "connecting");
  assert.strictEqual(core.connectionPhase(false, true, "unknown"), "connecting");
  assert.strictEqual(core.connectionPhase(false, true, "stopped"), "bridge-down");
  assert.strictEqual(core.connectionPhase(false, true, "running"), "ready");
});

test("readState accepts a state reply and nothing else", () => {
  assert.ok(core.readState(replies.state_band));
  assert.ok(core.readState(replies.state_empty));
  assert.strictEqual(core.readState(replies.unknown_command), null);
  assert.strictEqual(core.readState(replies.bad_request), null);
  assert.strictEqual(core.readState(null), null);
  assert.strictEqual(core.readState({ status: "ok", command: "state" }), null);
});

test("the recorded replies carry the project", () => {
  assert.strictEqual(replies.state_band.project.name, "Sunday");
  assert.strictEqual(replies.state_unsaved.project.path, "");
});

test("mix headers: stray, duplicate, no output, outputs", () => {
  const h = core.mixHeaders(band());
  assert.deepStrictEqual(h.map((x) => x.name), ["Stray", "Drummer", "Singer", "Bassist", "Singer"]);
  assert.deepStrictEqual(h.map((x) => x.stray), [true, false, false, false, false]);
  assert.deepStrictEqual(h.map((x) => x.duplicate), [false, false, true, false, true]);
  assert.deepStrictEqual(h.map((x) => x.noOutput), [false, false, false, true, false]);
  assert.deepStrictEqual(h[2].output, { channel: 2, mono: true });
  assert.strictEqual(h[3].output, null);
  assert.strictEqual(h[4].extraOutputs, 1);
  assert.strictEqual(h[1].masterSend, false);
  assert.strictEqual(h[0].masterSend, true);
});

test("matrix: rows are the source tracks in project order with depth", () => {
  const m = core.buildMatrix(band(), "");
  assert.deepStrictEqual(m.rows.map((r) => r.name), ["Drums", "Kick", "Snare", "Bass", "Vocals"]);
  assert.deepStrictEqual(m.rows.map((r) => r.depth), [0, 1, 1, 0, 0]);
  assert.strictEqual(m.columns.length, 5);
  m.rows.forEach((r) => assert.strictEqual(r.cells.length, 5));
});

test("matrix: ON cells carry the level, mute and signal point", () => {
  const m = core.buildMatrix(band(), "");
  const row = (n) => m.rows.find((r) => r.name === n);
  const drummer = 1;
  assert.strictEqual(row("Drums").cells[drummer].db, "-6.0");
  assert.strictEqual(row("Vocals").cells[drummer].muted, true);
  assert.strictEqual(row("Vocals").cells[drummer].db, "-12.0");
  assert.strictEqual(row("Snare").cells[drummer], null);
  assert.strictEqual(row("Kick").cells[drummer].nonStandard, false);
  assert.strictEqual(row("Bass").cells[drummer].nonStandard, true);
  assert.strictEqual(row("Bass").cells[drummer].mode, 0);
  assert.strictEqual(row("Bass").cells[drummer].db, "+6.0");
  assert.strictEqual(row("Bass").cells[4].mode, 1);
});

test("matrix: a folder and its child feeding one mix is a double feed on both cells, and only there", () => {
  const m = core.buildMatrix(band(), "");
  const row = (n) => m.rows.find((r) => r.name === n);
  assert.deepStrictEqual(row("Kick").cells[1].doubleFeed, { with: "folder", name: "Drums" });
  assert.deepStrictEqual(row("Drums").cells[1].doubleFeed, { with: "child", name: "Kick" });
  assert.strictEqual(row("Vocals").cells[1].doubleFeed, null);
  assert.strictEqual(row("Vocals").cells[2].doubleFeed, null);
});

test("matrix: the filter matches names case-insensitively and double feeds survive hidden rows", () => {
  const m = core.buildMatrix(band(), "  KIC ");
  assert.deepStrictEqual(m.rows.map((r) => r.name), ["Kick"]);
  assert.strictEqual(m.totalRows, 5);
  assert.deepStrictEqual(m.rows[0].cells[1].doubleFeed, { with: "folder", name: "Drums" });
  assert.deepStrictEqual(core.buildMatrix(band(), "zzz").rows, []);
});

test("matrix: sends from tracks that are not source rows are ignored; an empty project draws nothing", () => {
  const state = core.readState(replies.state_empty);
  const m = core.buildMatrix(state, "");
  assert.deepStrictEqual(m.rows, []);
  assert.deepStrictEqual(m.columns, []);
  const odd = JSON.parse(JSON.stringify(band()));
  odd.mixes[0].sends.push({ source: "{nobody}", vol: 1, muted: false, mode: 3 });
  assert.doesNotThrow(() => core.buildMatrix(odd, ""));
});

test("matrix: two sends from one source to one mix show once and are counted", () => {
  const state = JSON.parse(JSON.stringify(band()));
  state.mixes[0].sends.push(Object.assign({}, state.mixes[0].sends[0], { vol: 0.5 }));
  const cell = core.buildMatrix(state, "").rows.find((r) => r.name === "Vocals").cells[0];
  assert.strictEqual(cell.sends, 2);
  assert.strictEqual(cell.db, "0.0");
});

test("a project with no folder shows its mix as a stray; an empty folder holds nothing", () => {
  assert.strictEqual(core.mixHeaders(core.readState(replies.state_no_folder))[0].stray, true);
  assert.strictEqual(replies.state_empty_folder.folder.is_folder, false);
});

test("the lock: editing needs a live bridge and one Unlock, and the lock closes with the bridge or the project", () => {
  assert.strictEqual(core.canEdit("ready", false), false);
  assert.strictEqual(core.canEdit("ready", true), true);
  ["connecting", "offline", "bridge-down"].forEach((phase) => assert.strictEqual(core.canEdit(phase, true), false, phase));
  assert.strictEqual(core.stillUnlocked(false, "ready", "a.rpp", "a.rpp"), false);
  assert.strictEqual(core.stillUnlocked(true, "ready", "a.rpp", "a.rpp"), true);
  assert.strictEqual(core.stillUnlocked(true, "ready", null, "a.rpp"), true);
  assert.strictEqual(core.stillUnlocked(true, "ready", "a.rpp", "b.rpp"), false);
  assert.strictEqual(core.stillUnlocked(true, "bridge-down", "a.rpp", "a.rpp"), false);
});

test("checkMixName: trimmed, never empty, never another mix's name; a mix may keep its own", () => {
  const state = band(); // Stray, Drummer, Singer, Bassist, Singer (a duplicate pair)
  assert.deepStrictEqual(core.checkMixName(state, "  Keys ", null), { ok: true, name: "Keys" });
  assert.deepStrictEqual(core.checkMixName(state, "", null), { ok: false, code: "empty_name" });
  assert.deepStrictEqual(core.checkMixName(state, "   ", null), { ok: false, code: "empty_name" });
  assert.deepStrictEqual(core.checkMixName(state, undefined, null), { ok: false, code: "empty_name" });
  assert.deepStrictEqual(core.checkMixName(state, "Drummer", null), { ok: false, code: "duplicate_name" });
  assert.deepStrictEqual(core.checkMixName(state, "drummer", null), { ok: true, name: "drummer" });
  const drummer = state.mixes[1].guid;
  assert.deepStrictEqual(core.checkMixName(state, "Drummer", drummer), { ok: true, name: "Drummer", unchanged: true });
  assert.deepStrictEqual(core.checkMixName(state, "Bassist", drummer), { ok: false, code: "duplicate_name" });
});

test("duplicates already in the project can be renamed apart", () => {
  const state = band();
  const [first, second] = state.mixes.filter((m) => m.name === "Singer");
  assert.strictEqual(core.checkMixName(state, "Singer", second.guid).unchanged, true);
  assert.strictEqual(core.checkMixName(state, "Singer 2", second.guid).ok, true);
  assert.strictEqual(core.checkMixName(state, "Singer", first.guid).unchanged, true);
});

test("folderOffer: Move to end only while tracks sit after the folder; the colour is the project's", () => {
  assert.deepStrictEqual(core.folderOffer(core.readState(replies.state_band)),
    { exists: true, guid: "{GUID-7}", moveToEnd: false, colour: "#3b82c4" });
  const after = core.folderOffer(core.readState(replies.state_tracks_after));
  assert.strictEqual(after.moveToEnd, true);
  assert.strictEqual(after.exists, true);
  const none = core.folderOffer(core.readState(replies.state_empty));
  assert.deepStrictEqual([none.exists, none.guid, none.moveToEnd], [false, null, false]);
  assert.strictEqual(core.folderOffer({ mixes: [], sources: [], colour: "FF8000" }).colour, "#ff8000");
  assert.strictEqual(core.folderOffer({ mixes: [], sources: [], colour: "junk" }).colour, "#3b82c4");
});

test("colourField turns a colour input value into the bridge's six digits", () => {
  assert.strictEqual(core.colourField("#FF8000"), "ff8000");
  assert.strictEqual(core.colourField("ff8000"), null);
  assert.strictEqual(core.colourField(""), null);
});

// ---- hardware outputs (issue 06) ------------------------------------------------------------------------------------
const mixOf = (guid, name, outputs) => ({ guid, name, in_folder: true, master_send: false, outputs, sends: [] });
const stateOf = (mixes, extra) => Object.assign({ status: "ok", command: "state", mixes, sources: [], device: { channels: [] }, master_outputs: [] }, extra || {});
const st = (channel) => ({ channel, mono: false });
const mono = (channel) => ({ channel, mono: true });

test("a stereo output occupies two channels, a mono one a single channel", () => {
  assert.deepStrictEqual(core.outputChannels(st(2)), [2, 3]);
  assert.deepStrictEqual(core.outputChannels(mono(2)), [2]);
});

test("clash: an equal start channel, and an overlap of a stereo pair with a neighbour, are both flagged", () => {
  const same = core.outputClashes(stateOf([mixOf("a", "A", [st(0)]), mixOf("b", "B", [st(0)])]));
  assert.deepStrictEqual(same.a, [{ "with": "mix", guid: "b", name: "B" }]);
  assert.deepStrictEqual(same.b, [{ "with": "mix", guid: "a", name: "A" }]);
  // stereo 2-3 against stereo 3-4: different start channels, channel 3 in common
  const overlap = core.outputClashes(stateOf([mixOf("a", "A", [st(2)]), mixOf("b", "B", [st(3)])]));
  assert.ok(overlap.a && overlap.b);
  // a mono output inside a pair
  const inside = core.outputClashes(stateOf([mixOf("a", "A", [st(2)]), mixOf("b", "B", [mono(3)])]));
  assert.ok(inside.a && inside.b);
});

test("clash: neighbouring pairs, a mono beside a pair and a mix with no output do not clash", () => {
  const none = core.outputClashes(stateOf([mixOf("a", "A", [st(0)]), mixOf("b", "B", [st(2)]), mixOf("c", "C", [mono(4)]), mixOf("d", "D", [])]));
  assert.deepStrictEqual(none, {});
  assert.deepStrictEqual(core.outputClashes(stateOf([mixOf("a", "A", [mono(0)]), mixOf("b", "B", [mono(1)])])), {});
});

test("clash: the master track's own hardware outputs count, stereo and mono", () => {
  const master = core.outputClashes(stateOf([mixOf("a", "A", [st(2)]), mixOf("b", "B", [st(4)])], { master_outputs: [st(0), mono(3)] }));
  assert.deepStrictEqual(master, { a: [{ "with": "master" }] });
});

test("clash: a mix with several outputs is checked on all of them, and a mix never clashes with itself", () => {
  const many = core.outputClashes(stateOf([mixOf("a", "A", [st(0), st(2)]), mixOf("b", "B", [mono(3)]), mixOf("c", "C", [st(0), st(1)])]));
  assert.deepStrictEqual(many.b, [{ "with": "mix", guid: "a", name: "A" }]);
  assert.deepStrictEqual(many.a.map((x) => x.name), ["B", "C"]);
});

test("clash: the recorded band flags the mixes that overlap, and the headers carry it", () => {
  const h = core.mixHeaders(band());
  // Drummer is stereo 0, and the second Singer has stereo 0 and 2; Singer (mono 2) lies inside that pair too
  assert.deepStrictEqual(h.map((x) => x.clashes.length > 0), [false, true, true, false, true]);
  assert.strictEqual(h[3].clashes.length, 0);
  const open = core.mixHeaders(core.readState(replies.state_device_open));
  assert.ok(open[1].clashes.some((c) => c["with"] === "master"), "Drummer shares output 1-2 with the master");
});

test("headers: more than one output is read-only", () => {
  const h = core.mixHeaders(band());
  assert.deepStrictEqual(h.map((x) => x.readOnlyOutput), [false, false, false, false, true]);
});

test("picker: lists none, mono per channel, stereo per pair, and selects the current output", () => {
  const state = core.readState(replies.state_device_open); // five channels
  const drummer = state.mixes[1];
  const p = core.outputPicker(state, drummer);
  assert.strictEqual(p.deviceClosed, false);
  assert.strictEqual(p.readOnly, false);
  assert.strictEqual(p.value, "s:0");
  assert.deepStrictEqual(p.options.map((o) => o.value), ["none", "m:0", "m:1", "m:2", "m:3", "m:4", "s:0", "s:2"]);
  assert.strictEqual(core.outputPicker(state, state.mixes[3]).value, "none");
  assert.strictEqual(core.outputPicker(state, state.mixes[2]).value, "m:2");
});

test("picker: closed device is disabled and an existing output is still shown, by number", () => {
  const state = band(); // no channels
  const p = core.outputPicker(state, state.mixes[2]);
  assert.strictEqual(p.deviceClosed, true);
  assert.strictEqual(p.value, "m:2");
  assert.deepStrictEqual(p.options.map((o) => o.value), ["none", "m:2"]);
  assert.strictEqual(core.outputPicker(state, state.mixes[4]).readOnly, true);
});

test("picker: an existing pair the list does not offer (an odd start) is added", () => {
  const state = stateOf([mixOf("a", "A", [st(1)])], { device: { channels: ["1", "2", "3", "4"] } });
  const p = core.outputPicker(state, state.mixes[0]);
  assert.strictEqual(p.value, "s:1");
  assert.ok(p.options.some((o) => o.value === "s:1"));
});

test("a picker value becomes the bridge's choice", () => {
  assert.deepStrictEqual(core.parseOutputChoice("none"), { none: true });
  assert.deepStrictEqual(core.parseOutputChoice("m:3"), { channel: 3, mono: true });
  assert.deepStrictEqual(core.parseOutputChoice("s:0"), { channel: 0, mono: false });
  assert.strictEqual(core.parseOutputChoice("x:1"), null);
  assert.strictEqual(core.parseOutputChoice(""), null);
});

test("an open picker survives a refresh: the rebuild waits for it and happens once when it closes", () => {
  let paints = 0;
  const gate = core.createRenderGate(() => { paints++; });
  const picker = core.createPickerGuard(gate);
  picker.open(); picker.open(); // focus and press both report it
  gate.request(); gate.request(); // two refreshes while the engineer chooses
  assert.strictEqual(paints, 0);
  assert.ok(picker.isOpen() && gate.pending());
  picker.close(); picker.close(); // change and blur both report it
  assert.strictEqual(paints, 1);
  assert.ok(!gate.active());
});

test("an open picker and a hold key keep the grid still together", () => {
  let paints = 0;
  const gate = core.createRenderGate(() => { paints++; });
  const picker = core.createPickerGuard(gate);
  picker.open(); gate.begin(); gate.request();
  picker.close();
  assert.strictEqual(paints, 0);
  gate.end();
  assert.strictEqual(paints, 1);
});

// ---- row and column toggles (issue 08) ---------------------------------------------------------------------------------
test("a row or column toggle carries only the ID and the wanted state", () => {
  assert.deepStrictEqual(core.rowRequest({ guid: "{K}", name: "Kick" }, true), { source: "{K}", on: true });
  assert.deepStrictEqual(core.columnRequest({ guid: "{A}", name: "Drummer" }, false), { mix: "{A}", on: false });
});

// ---- matrix cells (issue 07) -------------------------------------------------------------------------------------------
test("a tap asks for the opposite of what the cell shows, by GUID, as a state rather than a toggle", () => {
  const row = { guid: "{K}" }, col = { guid: "{A}" };
  assert.deepStrictEqual(core.cellRequest(row, col, null), { source: "{K}", mix: "{A}", on: true });
  assert.deepStrictEqual(core.cellRequest(row, col, { on: true }), { source: "{K}", mix: "{A}", on: false });
});

// ---- the cue track (IEM Mix issue 07) -----------------------------------------------------------------------------------
test("the cue track is no mix and no source row in the recorded state, and the page offers what is missing", () => {
  const state = core.readState(replies.state_cue);
  assert.ok(state);
  assert.deepStrictEqual(state.mixes.map((m) => m.name), ["A", "B"]);
  assert.deepStrictEqual(state.sources.map((s) => s.name), ["Kick"]);
  const matrix = core.buildMatrix(state, "");
  assert.deepStrictEqual(matrix.columns.map((c) => c.name), ["A", "B"]);
  assert.deepStrictEqual(matrix.rows.map((r) => r.name), ["Kick"]);

  const offer = core.cueOffer(state);
  assert.strictEqual(offer.exists, true);
  assert.strictEqual(offer.guid, state.cue.guid);
  assert.strictEqual(offer.action, null);
  assert.strictEqual(offer.picker.value, "m:2");
  assert.strictEqual(offer.picker.deviceClosed, false);
});

test("without a cue track the page offers Create cue; with sends missing, the same command repairs", () => {
  const none = core.cueOffer(core.readState(replies.state_band));
  assert.deepStrictEqual([none.exists, none.action, none.picker], [false, "create", null]);
  const gap = core.cueOffer({ mixes: [], sources: [], device: { channels: [] }, cue: { guid: "{Q}", outputs: [], missing: 2 } });
  assert.strictEqual(gap.action, "repair");
  assert.strictEqual(gap.picker.value, "none");
});

test("Monitor's mix list is the same with the cue track in the project (shared listing rule, recorded state)", () => {
  const reaper = require("../../../shared/www/lcrr/shared/js/reaper.js");
  const state = replies.state_cue;
  const tracks = state.mixes.map((m, i) => ({ name: "IEM_" + m.name, number: i + 2, recvcnt: Math.max(m.sends.length, 1), hwoutcnt: m.outputs.length }));
  const listed = (list) => reaper.listMixes(list).map((m) => m.name);
  const before = listed(tracks);
  const cue = { name: "IEM-Cue", number: 9, recvcnt: state.mixes.length, hwoutcnt: state.cue.outputs.length };
  assert.deepStrictEqual(listed(tracks.concat([cue])), before);
  assert.deepStrictEqual(before, ["A", "B"]);
  assert.strictEqual(reaper.tracksNamed(tracks.concat([cue]), "Cue").length, 0);
});

test("the recorded cue replies say what they did", () => {
  assert.strictEqual(replies.cue_create.status, "ok");
  assert.strictEqual(replies.cue_unchanged.changed, false);
  assert.strictEqual(replies.cell_cue_not_a_source.error.code, "not_a_source");
});
