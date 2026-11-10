// IEM Mix: pure logic for the Snapshots section (no DOM, no network): is the bridge there, may a write go out, the
// name check, and every sentence (the key labels and hold titles too). Load after core.js; the DOM wiring is iemmix.js.
(function (root, factory) {
  var core = typeof module === "object" && module.exports ? require("./core.js") : root.LCRR.iemmix.core;
  var api = factory(core);
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.iemmix = L.iemmix || {}).snapshots = api; }
})(this, function (core) {
  "use strict";

  var MAX_NAME = 40; // characters; the bridge's own limit (snapshot_store.lua)

  // The bridge's state for the page, from the heartbeat ("unknown" | "running" | "stopped"):
  // "checking" until the heartbeat has been seen, "ready" while it beats, "down" when it does not. Snapshots need the
  // bridge only; REAPER being unreachable is the page's own offline state.
  function bridgeState(beat) {
    if (beat === "running") return "ready";
    if (beat === "stopped") return "down";
    return "checking";
  }

  // May a snapshot write go out? Behind the page's one gate (core.canEdit: connected and unlocked) and the bridge.
  function canWrite(phase, unlocked, bridge) { return core.canEdit(phase, unlocked) && bridge === "ready"; }

  // Is the list there to read? (Reading needs no Unlock.)
  function canRead(phase, bridge) { return phase === "connected" && bridge === "ready"; }

  // A name as the bridge will see it: trimmed, not empty, not too long, no control characters, not taken.
  // `existing` is the list's names; `fits(name)` tells whether the request would stay under the URL limit.
  // Returns { name } or { code }.
  function checkName(raw, existing, fits) {
    var name = String(raw === undefined || raw === null ? "" : raw).trim();
    if (!name) return { code: "empty_name" };
    if (/[\u0000-\u001f\u007f]/.test(name)) return { code: "bad_name" };
    if (Array.from(name).length > MAX_NAME || (fits && !fits(name))) return { code: "name_too_long" };
    if ((existing || []).indexOf(name) >= 0) return { code: "duplicate_name" };
    return { name: name };
  }

  // The `snapshots` reply's list, or null when it is not one this page can draw.
  function readList(reply) {
    if (!reply || reply.status !== "ok" || reply.command !== "snapshots" || !Array.isArray(reply.snapshots)) return null;
    return reply.snapshots.map(function (s) {
      return { name: String(s.name), saved: s.saved, mixes: s.mixes, sends: s.sends };
    });
  }

  function plural(n, one, many) { return n + " " + (n === 1 ? one : many); }
  function counts(s) { return plural(s.mixes, "mix", "mixes") + ", " + plural(s.sends, "send", "sends"); }

  var UNDO_NOTE = "Saving, overwriting and deleting a snapshot cannot be undone.";
  var ERRORS = {
    empty_name: "Give the snapshot a name.",
    bad_name: "A name cannot hold line breaks or other control characters.",
    name_too_long: "That name is too long. Use at most " + MAX_NAME + " characters.",
    duplicate_name: "A snapshot with that name already exists. Hold its Overwrite key to replace it.",
    not_found: "That snapshot is no longer saved.",
    nothing_to_save: "There are no sends to save yet.",
    unreadable: "The saved snapshots in this project could not be read, so nothing was changed.",
    mix_not_saved: "That snapshot holds nothing for this mix.",
    track_gone: "That mix is no longer in the project.",
    not_a_mix: "That track is not a mix any more.",
    mix_unknown: "REAPER's list of mixes does not hold that mix.",
    mix_ambiguous: "More than one mix has that name, so the page cannot tell which one to recall.",
    request_too_long: "That name is too long to send.",
    unreachable: "REAPER did not take the request.",
    no_reply: "The bridge did not answer."
  };
  function errorText(err) {
    var code = err && (err.code || (err.error && err.error.code));
    return ERRORS[code] || "The snapshot request failed" + (code ? " (" + code + ")." : ".");
  }

  // The mix to recall, found in the bridge's `state` reply by its name (the page reads the name from REAPER, the bridge
  // is the only place that knows GUIDs). Returns { guid } or { code }.
  function findMix(reply, name) {
    if (!reply || reply.status !== "ok" || !Array.isArray(reply.mixes)) return { code: "unreachable" };
    var found = reply.mixes.filter(function (m) { return m && m.name === name && typeof m.guid === "string"; });
    if (!found.length) return { code: "mix_unknown" };
    if (found.length > 1) return { code: "mix_ambiguous" };
    return { guid: found[0].guid };
  }

  // What a recall said, from the bridge's `snapshot_recall` reply: what was written, then what was skipped. `scope` is
  // null for the whole band, else the mix's name.
  function recallText(reply, name, scope) {
    var n = function (v) { return typeof v === "number" && v > 0 ? v : 0; };
    var sends = n(reply.sends), skipped = n(reply.skipped), missing = n(reply.missing), mixes = n(reply.mixes);
    var target = scope === null || scope === undefined ? "" : " to " + scope;
    var head = sends || mixes
      ? "Recalled “" + name + "”" + target + ": " + (scope === null || scope === undefined ? plural(mixes, "mix", "mixes") + ", " : "") +
        plural(sends, "send", "sends") + "."
      : "Nothing was recalled from “" + name + "”" + target + ".";
    var gone = [];
    if (skipped) gone.push(plural(skipped, "level was", "levels were") + " skipped because its source, mix or output is gone or no longer routed");
    if (missing) gone.push(plural(missing, "mix is", "mixes are") + " no longer in the project");
    return head + (gone.length ? " " + gone.join("; ") + "." : "");
  }

  // A key in a snapshot's row: "recallAll", "recallMix" (needs `mixName`, the short name), "overwrite" or "delete".
  // One table: the label (`recallMix`'s is built from the mix's name) and whether the key is a recall, which REAPER undoes.
  var KEYS = {
    recallAll: { label: "Recall all", recall: true },
    recallMix: { label: function (mixName) { return "Recall " + mixName; }, recall: true },
    overwrite: { label: "Overwrite", recall: false },
    delete: { label: "Delete", recall: false }
  };
  function keyLabel(kind, mixName) { var l = KEYS[kind].label; return typeof l === "function" ? l(mixName) : l; }
  // The hold key's title: what holding does to the snapshot, and whether REAPER can undo it.
  function holdTitle(kind, mixName, snapName) {
    var recall = KEYS[kind].recall, label = keyLabel(kind, mixName);
    return "Hold to " + (recall ? label : label.toLowerCase()) + " “" + snapName + "”. " +
      (recall ? "One undo step in REAPER." : "This cannot be undone.");
  }

  var BRIDGE_DOWN = "Snapshots need IEM Setup’s bridge, which is not running in REAPER. Levels, pans, mutes and Listen still work.";
  var BRIDGE_CHECKING = "Looking for IEM Setup’s bridge…";
  var LOCKED = "Locked. Unlock to save, overwrite, delete or recall a snapshot.";
  var RECALL_NOTE = " Recall is one undo step in REAPER, and overwrites what the musicians changed since the save.";

  // The line shown above the controls: why they are unavailable, else a refusal kept from the last write, else the
  // standing warning about undo.
  function note(phase, unlocked, bridge, lastError, result) {
    if (phase !== "connected") return "";
    if (bridge === "down") return BRIDGE_DOWN;
    if (bridge === "checking") return BRIDGE_CHECKING;
    if (lastError) return lastError;
    if (result) return result;
    if (!unlocked) return LOCKED;
    return UNDO_NOTE + RECALL_NOTE;
  }

  return { MAX_NAME: MAX_NAME, bridgeState: bridgeState, canWrite: canWrite, canRead: canRead, checkName: checkName,
    readList: readList, counts: counts, errorText: errorText, note: note, findMix: findMix, recallText: recallText, keyLabel: keyLabel, holdTitle: holdTitle, UNDO_NOTE: UNDO_NOTE, RECALL_NOTE: RECALL_NOTE, BRIDGE_DOWN: BRIDGE_DOWN };
});
