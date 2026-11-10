// Snapshots: every sentence the page shows (pure). The bridge sends codes and fields; the wording is here, so a
// reply never carries prose and each sentence can be tested against recorded replies.
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.snapshots = L.snapshots || {}).words = api; }
})(this, function () {
  "use strict";

  var CHIP = { connecting: "Connecting…", ready: "Connected", offline: "REAPER unreachable", "bridge-down": "Snapshots not running" };
  var BANNER = {
    offline: "Can’t reach REAPER. This page keeps retrying.",
    "bridge-down": "Snapshots isn’t running in REAPER, so nothing can be saved or restored. Open the Actions list and run “LCRR Snapshots: Bridge”."
  };

  var ERRORS = {
    bad_request: "REAPER’s bridge could not read that request.",
    request_truncated: "The request was cut off on the way to REAPER.",
    unknown_command: "This page asked for something the installed bridge does not know. Re-run install.ps1 and restart REAPER.",
    internal: "The bridge hit a problem with the project.",
    no_ticks: "Tick at least one kind of value to restore.",
    bad_ticks: "The bridge did not know one of the ticks. Re-run install.ps1 and restart REAPER.",
    not_found: "That snapshot is no longer saved.",
    empty_name: "Give the snapshot a name.",
    bad_name: "A name cannot hold line breaks or other control characters.",
    name_too_long: "That name is too long. Use at most 40 characters.",
    not_found: "That snapshot is no longer saved. The list has been refreshed.",
    duplicate_name: "A snapshot with that name already exists. Use another name.",
    unreadable: "The saved snapshots in this project could not be read, so nothing was changed.",
    request_too_long: "The request is too long to send.",
    unreachable: "REAPER did not take the request.",
    no_reply: "The bridge did not answer."
  };

  function error(err) {
    var code = err && err.code;
    return ERRORS[code] || ("Something went wrong (" + (code || "unknown") + ").");
  }

  var UI = { title: "Snapshots", unsavedProject: "(unsaved project)", name: "Name", save: "Save", overwrite: "Overwrite", delete: "Delete", holdLegend: "Hold", empty: "No snapshots saved yet." };
  function ui(key) { return UI[key] || ""; }

  function chip(phase) { return CHIP[phase] || ""; }
  function banner(phase) { return BANNER[phase] || ""; }

  // The active project's name for the bar.
  function projectName(project) {
    return project && project.name ? project.name : UI.unsavedProject;
  }

  function plural(n, one, many) { return n + " " + (n === 1 ? one : many); }

  // A row's second line: what it holds and when it was saved (`when` is the page's own time text, may be empty).
  function counts(s, when) {
    return plural(s.tracks, "track", "tracks") + ", " + plural(s.sends, "send", "sends") + (when ? " · " + when : "");
  }

  // The marks on a row: what the snapshot holds that the engineer should see before Restore. Words, not colour alone.
  function marks(s) {
    var out = [];
    if (s.solo) out.push("Solo");
    if (s.masterMuted) out.push("Master muted");
    return out;
  }

  // A row's key names for a screen reader and its tooltip: what holding it does to which snapshot.
  var HOLD_VERBS = { delete: "Delete ", restore: "Restore ", overwrite: "Overwrite " };
  function holdLabel(kind, name) { return (HOLD_VERBS[kind] || HOLD_VERBS.overwrite) + name + ", hold to confirm"; }
  // The restore's wording: the ticks' labels, the Restore key, and the result note.
  var TICK_LABELS = { levels: "Levels", pans: "Pans", mutes: "Mutes", solos: "Solos", polarity: "Polarity", sends: "Sends", fx: "FX on/off", inears: "In-ears" };
  UI.restore = "Restore";
  UI.tickNote = "With In-ears off, in-ear tracks and the sends into them are left alone. Restoring a source track’s mute, polarity or FX can still change what the musicians hear, even with In-ears off.";
  function tick(key) { return TICK_LABELS[key] || ""; }

  // The last restore's result: what was written, what was skipped because it is gone.
  function restoreNote(r) {
    var gone = r.skipped ? " " + plural(r.skipped, "saved item was", "saved items were") + " skipped, gone from the project." : "";
    var auto = r.automated ? " " + plural(r.automated, "restored value has", "restored values have") + " active automation and will follow it." : "";
    var muted = r.mutedSkipped ? " " + plural(r.mutedSkipped, "mute was", "mutes were") + " left alone, because the automation mode would write it into a Mute envelope." : "";
    if (!r.tracks && !r.sends) return "Nothing was restored from “" + r.name + "”." + gone + muted + auto;
    return "Restored “" + r.name + "”: " + plural(r.tracks, "track", "tracks") + ", " + plural(r.sends, "send", "sends") + " written." + gone + muted + auto;
  }

  var NO_SNAPSHOTS = UI.empty;
  var UNDO_NOTE = "Saving a snapshot cannot be undone.";

  return { tick: tick, restoreNote: restoreNote, holdLabel: holdLabel, counts: counts, marks: marks, NO_SNAPSHOTS: NO_SNAPSHOTS, UNDO_NOTE: UNDO_NOTE, error: error, ui: ui, chip: chip, banner: banner, projectName: projectName };
});
