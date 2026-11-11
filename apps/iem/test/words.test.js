const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const core = require("../www/lcrr/iem/js/core.js");
const words = require("../www/lcrr/iem/js/words.js");

const replies = {};
fs.readFileSync(path.join(__dirname, "fixtures/bridge-replies.txt"), "utf8").split("\n").filter(Boolean).forEach((line) => {
  const tab = line.indexOf("\t");
  replies[line.slice(0, tab)] = JSON.parse(line.slice(tab + 1));
});

function clean(text, label) {
  assert.strictEqual(typeof text, "string", label);
  assert.ok(text.length > 0, label + " is empty");
  assert.ok(!/undefined|NaN|\[object|null/.test(text), label + " has a hole in it: " + text);
}

test("every refusal the bridge can send has words, not just its code", () => {
  let count = 0;
  Object.keys(replies).forEach((name) => {
    const r = replies[name];
    if (r.status !== "refused") return;
    if (/^snapshot/.test(name)) return; // IEM Mix's commands, worded by its page (apps/iemmix/test/snapshots.test.js)
    const text = words.error(r.error);
    clean(text, name);
    assert.ok(!text.startsWith("Something went wrong"), name + " has no wording for " + r.error.code);
    count++;
  });
  assert.ok(count >= 3);
});

test("the page's own failures have words", () => {
  ["request_too_long", "unreachable", "no_reply", "internal"].forEach((code) => {
    assert.ok(!words.error({ code }).startsWith("Something went wrong"), code);
  });
  assert.match(words.error({ code: "novel" }), /novel/);
});

test("every phase has a chip, and the ones that need attention a banner", () => {
  ["connecting", "ready", "offline", "bridge-down"].forEach((p) => clean(words.chip(p), p));
  clean(words.banner("offline"), "offline");
  assert.match(words.banner("bridge-down"), /LCRR IEM: Bridge/);
  assert.strictEqual(words.banner("ready"), "");
});

test("output wording numbers channels from 1", () => {
  assert.strictEqual(words.outputText(null), "No output");
  assert.strictEqual(words.outputText({ channel: 0, mono: false }), "Out 1–2");
  assert.strictEqual(words.outputText({ channel: 2, mono: true }), "Out 3 mono");
});

test("every header flag and cell note in the recorded band reads cleanly", () => {
  const state = core.readState(replies.state_band);
  const m = core.buildMatrix(state, "");
  let flags = 0, notes = 0;
  m.columns.forEach((header, col) => {
    words.headerFlags(header).forEach((f) => { clean(f.text, header.name); flags++; });
    clean(words.outputText(header.output), header.name);
    m.rows.forEach((row) => {
      const cell = row.cells[col];
      clean(words.cellLabel(row, header, cell), row.name);
      if (!cell) return;
      if (cell.nonStandard) { clean(words.modeNote(cell.mode), row.name); clean(words.modeTag(cell.mode), row.name); notes++; }
      if (cell.doubleFeed) { clean(words.doubleFeedNote(cell.doubleFeed), row.name); notes++; }
    });
  });
  assert.ok(flags >= 4 && notes >= 4);
});

test("empty states and the filter miss say what to do", () => {
  clean(words.emptyMatrix(core.readState(replies.state_empty)), "empty");
  clean(words.emptyMatrix(core.readState(replies.state_unsaved)), "no mixes");
  assert.strictEqual(words.emptyMatrix(core.readState(replies.state_band)), "");
  assert.match(words.noMatch("kik"), /kik/);
});

test("every refusal a write can answer with has its own wording", () => {
  ["empty_name", "duplicate_name", "track_gone", "not_a_mix", "not_the_folder", "nothing_to_move", "not_a_source", "not_a_stray", "bad_colour", "multiple_outputs", "bad_channel", "no_device"].forEach((code) => {
    const text = words.error({ code });
    clean(text, code);
    assert.ok(!text.startsWith("Something went wrong"), code);
  });
  const written = Object.keys(replies).filter((n) => /^(adopt|create|rename|colour|move_to_end|delete|output|cell|row|column)_/.test(n));
  assert.ok(written.length >= 28, "the write scenarios are recorded");
});

test("the editing controls have labels", () => {
  ["newMix", "create", "rename", "save", "cancel", "colour", "moveToEnd",
    "moveToEndHint", "copyFrom", "copyFromNone", "copyFromHint", "adopt", "adoptHint", "colourHint", "delete", "deleteHint"].forEach((key) => clean(words.ui(key), key));
  assert.match(words.renameLabel("Drums"), /Drums/);
  assert.match(words.deleteLabel("Drums"), /Drums.*hold/);
  assert.match(words.adoptLabel("Drums"), /Drums.*IEMs folder.*hold/);
});

test("cell wording says what a tap will do", () => {
  const row = { name: "Kick" }, col = { name: "Drummer" };
  assert.strictEqual(words.cellAction(row, col, null), "Switch on Kick to Drummer");
  assert.strictEqual(words.cellAction(row, col, { db: "0.0" }), "Switch off Kick to Drummer");
});

test("picker wording: named channels, numbers when there is no name, and the flags", () => {
  const names = ["Output 1", "Output 2", "Output 3"];
  assert.strictEqual(words.optionLabel(names, { channel: null, mono: false }), "No output");
  assert.strictEqual(words.optionLabel(names, { channel: 1, mono: true }), "Mono 2 Output 2");
  assert.strictEqual(words.optionLabel(names, { channel: 0, mono: false }), "Stereo 1 Output 1 + 2 Output 2");
  assert.strictEqual(words.optionLabel([], { channel: 2, mono: true }), "Mono 3");
  assert.strictEqual(words.optionLabel([], { channel: 0, mono: false }), "Stereo 1 + 2");
  // A blank or missing name from the device falls back to the number, never an empty label.
  assert.strictEqual(words.optionLabel(["", "Out B"], { channel: 0, mono: false }), "Stereo 1 + 2 Out B");
  assert.strictEqual(words.optionLabel([""], { channel: 0, mono: true }), "Mono 1");
  ["output", "outputNone", "deviceClosed", "outputReadOnly"].forEach((key) => clean(words.ui(key), key));
  clean(words.pickerLabel("Drums"), "label");
  const flags = words.headerFlags({ clashes: [{ "with": "mix", name: "Singer" }, { "with": "master" }] });
  assert.strictEqual(flags[0].text, "Output shared with mix Singer, the master");
  assert.match(words.headerFlags({ extraOutputs: 1 })[0].text, /read-only/);
});

test("the cue track's keys have words", () => {
  ["createCue", "repairCue", "cueOutput", "cueOutputNeeded", "createCueHint", "repairCueHint", "cueOutputHint", "cueOutputNeededHint"].forEach((k) => clean(words.ui(k), k));
  clean(words.cuePickerLabel, "cue picker");
});

test("the panels, the hold legend, the cue and folder sentences and the tag legend have words", () => {
  ["adoptNote", "holdLegend", "more", "less", "moreHint", "panelMixes", "panelFolder", "panelCue", "applying", "tracks", "unsavedProject", "cueReady"].forEach((k) => clean(words.ui(k), k));
  assert.match(words.cueStatus({ exists: false }), /No cue track/);
  assert.match(words.cueStatus({ exists: true, action: "repair" }), /send to the cue track|solo defeat/);
  assert.match(words.cueStatus({ exists: true, action: null, needsOutput: true }), /headphones/);
  assert.match(words.cueStatus({ exists: true, action: null, needsOutput: false }), /ready/);
  assert.ok(!/Move the folder/.test(words.folderNote({ moveToEnd: false })));
  assert.match(words.folderNote({ moveToEnd: true }), /Move the folder/);
  [0, 1, 3].forEach((m) => clean(words.modeLegend(m), "mode " + m));
  clean(words.doubleLegend, "double");
});

test("the summary line has words", () => {
  assert.strictEqual(words.mixesStatus(0), "None yet");
  assert.strictEqual(words.mixesStatus(1), "1 mix");
  assert.strictEqual(words.mixesStatus(3), "3 mixes");
  assert.strictEqual(words.folderStatus({ exists: false }), "None yet");
  assert.strictEqual(words.folderStatus({ exists: true, moveToEnd: true }), "Tracks after it");
  assert.strictEqual(words.folderStatus({ exists: true, moveToEnd: false }), "Ready");
  assert.strictEqual(words.cueSummary(null), "Not made yet");
  assert.strictEqual(words.cueSummary({ exists: true, action: "repair" }), "Needs repair");
  assert.strictEqual(words.cueSummary({ exists: true, action: null, needsOutput: true }), "Choose output");
  assert.strictEqual(words.cueSummary({ exists: true, action: null, needsOutput: false }), "Ready");
  assert.match(words.emptyMatrix({ sources: [{}], mixes: [] }), /Add mix above/);
});

test("short output labels for a narrow header", () => {
  assert.equal(words.outputShort(null), "None");
  assert.equal(words.outputShort({ channel: 0, mono: false }), "1–2");
  assert.equal(words.outputShort({ channel: 2, mono: true }), "Mono 3");
  assert.equal(words.outputsStatus(0), "All set");
  assert.equal(words.outputsStatus(2), "2 without output");
});
