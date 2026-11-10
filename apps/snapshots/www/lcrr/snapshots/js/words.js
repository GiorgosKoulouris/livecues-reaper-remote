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
    empty_name: "Give the snapshot a name.",
    bad_name: "A name cannot hold line breaks or other control characters.",
    name_too_long: "That name is too long. Use at most 40 characters.",
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

  var UI = { title: "Snapshots", unsavedProject: "(unsaved project)", name: "Name", save: "Save", empty: "No snapshots saved yet." };
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

  var NO_SNAPSHOTS = UI.empty;
  var UNDO_NOTE = "Saving a snapshot cannot be undone.";

  return { counts: counts, NO_SNAPSHOTS: NO_SNAPSHOTS, UNDO_NOTE: UNDO_NOTE, error: error, ui: ui, chip: chip, banner: banner, projectName: projectName };
});
