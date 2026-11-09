// Arrange: the words (pure). The bridge sends codes and fields; this turns them into sentences. The wording mirrors
// lib/text/ in the Lua slice, which words the same results for the dialog scripts: keep the two in step.
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.arrange = L.arrange || {}).words = api; }
})(this, function () {
  "use strict";

  function f(n, d) { return Number(n).toFixed(d); }
  function signed(n, d) { return (n < 0 ? "-" : "+") + Math.abs(n).toFixed(d); }
  function q(s) { return JSON.stringify(String(s)); }
  function lines(list, one) { return list.map(one).join("\n"); }
  function trackLabel(index) { return index < 0 ? "the master track" : "track " + (index + 1); }
  function named(index, name) { return "track " + (index + 1) + (name ? " " + name : ""); }

  function problems(list) {
    return lines(list || [], function (p) {
      if (p.code === "duplicate") return "  " + q(p.name) + " is used by " + p.numbers.length + " regions (Region Numbers " + p.numbers.join(", ") + ")";
      if (p.code === "empty") return "  " + p.numbers.length + " region(s) have no name (Region Numbers " + p.numbers.join(", ") + ")";
      if (p.code === "item_moved") return "  " + named(p.track_index, p.track_name ? q(p.track_name) : "") + ": beat-attached item at " + f(p.from, 3) + " followed the tempo-map edit to " + f(p.to, 3);
      return "  " + p.code;
    });
  }

  var EDIT_TAB = "the Edit tab";
  var NEEDS_UPDATING = "Arrange needs updating. Run the LCRR installer again, then restart REAPER.";
  var UNSAVED = "This project hasn't been saved. Save it in REAPER, then try again.";
  var TOO_LONG = "That name is too long. Use a shorter one.";

  function sec(n) { return f(n, 1) + " s"; }
  function where(i) { return "track " + (i.track_index + 1) + " at " + sec(i.position !== undefined ? i.position : i.from); }
  function plainList(names) { return names.map(function (n) { return "  " + n; }).join("\n"); }

  // The reasons a plan can be refused, each with its fix.
  var PLAN_REASONS = {
    region_overlap: function (e) { return q(e.region) + " ends after " + q(e.next_region) + " starts. Separate them in REAPER so there is a gap, then try again."; },
    region_missing: function (e) { return q(e.name) + " is in the Arrangement but not in the project. Restore it in REAPER, or remove it from the Arrangement on " + EDIT_TAB + "."; },
    headroom: function (e) {
      return lines(e.problems, function (p) {
        return p.kind === "shrink_too_far"
          ? q(p.name) + " can't shrink by " + sec(Math.abs(p.requested)) + ". The most it can lose without cutting into its content is " + sec(p.most) + ". Lower its Headroom on " + EDIT_TAB + ", then try again."
          : "The Headroom on " + q(p.name) + " is too large. Check the value on " + EDIT_TAB + ".";
      });
    },
    items_unsafe: function (e) {
      return "Apply can't move some items because their track's timebase isn't Time:\n\n" + plainList(e.items.map(where)) + "\n\nSet those tracks' timebase to Time, then try again.";
    },
    planner_bug: function () { return "Apply stopped before changing anything because the plan didn't add up. If it happens again, send the run log beside the project."; }
  };

  // Why something stopped: a refusal's `error`. Bridge codes first, then the cores'.
  var ERRORS = {
    bad_request: function () { return NEEDS_UPDATING; },
    request_truncated: function () { return TOO_LONG; },
    request_too_long: function () { return TOO_LONG; },
    unknown_command: function () { return NEEDS_UPDATING; },
    missing_field: function () { return NEEDS_UPDATING; },
    operation_unknown: function () { return NEEDS_UPDATING; },
    internal: function () { return "Apply stopped partway. Press Ctrl+Z in REAPER to undo what it did, then try again. If it happens again, send the run log beside the project."; },
    token_unknown: function () { return "This Check has expired. Run Check again, then Apply."; },
    token_stale: function (e) {
      if (e.reason === "other_project") return "A different project is open in REAPER. Open the right one and run Check again. Nothing was changed.";
      if (e.reason === "arrangement_changed") return q(e.name) + " was edited since this Check. Run Check again, then Apply. Nothing was changed.";
      return "The project changed since this Check. Run Check again, then Apply. Nothing was changed.";
    },
    project_unsaved: function () { return UNSAVED; },
    sidecar_unsaved: function () { return UNSAVED; },
    tempo_env_beats: function () { return "The project's tempo timebase is set to Beats. In Project Settings, set \"Timebase for tempo/time signature env\" to Time, save the project, and try again."; },
    no_regions: function () { return "This project has no regions. Add some in REAPER, then try again."; },
    no_tracks: function () { return "This project has no tracks."; },
    region_names: function (e) { return "Every region needs its own name:\n\n" + problems(e.problems) + "\n\nRename these in REAPER, then try again."; },
    sidecar_invalid: function (e) { return "The Arrangement file can't be read: " + (e.error || "unknown error") + ". Fix it in a text editor, then try again."; },
    sidecar_missing: function () { return "This project has no Arrangements yet. Capture one, or run \"LCRR Arrange: Apply Arrangement\" in REAPER to import a file."; },
    no_arrangements: function () { return "This project has no Arrangements yet. Capture one first."; },
    arrangement_unknown: function (e) { return q(e.name) + " isn't an Arrangement in this project. Choose one of: " + (e.available || []).join(", ") + "."; },
    arrangement_empty: function (e) { return q(e.name) + " has no regions. Add some on " + EDIT_TAB + "."; },
    arrangement_missing_regions: function (e) {
      return q(e.name) + " uses regions this project doesn't have:\n\n" + plainList(e.missing) + "\n\nRestore them in REAPER, or remove them from " + q(e.name) + " on " + EDIT_TAB + ".";
    },
    plan_refused: function (e) { var one = PLAN_REASONS[e.reason]; return one ? one(e) : NEEDS_UPDATING; },
    // Not reachable today: no plan category is blocked. Worded in case one is added.
    plan_out_of_scope: function (e) { return "Arrange can't apply " + q(e.name) + " yet. " + NEEDS_UPDATING; },
    anchors_moved_items: function (e) {
      return "Apply stopped because these items moved with the tempo:\n\n" + plainList(e.moved.map(where)) + "\n\nPress Ctrl+Z in REAPER, set those tracks' timebase to Time, then try again.";
    },
    import_unreadable: function (e) { return "That file can't be imported: " + (e.error || "unknown error") + ". Choose a different Arrangement file."; },
    import_invalid: function (e) { return "That file can't be imported: " + (e.error || "unknown error") + ". Choose a different Arrangement file."; },
    name_empty: function () { return "An Arrangement needs a name."; },
    name_taken: function () { return "An Arrangement with that name already exists. Pick another name."; },
    other_project: function () { return "A different project is open in REAPER. Press Refresh, then redo the edit. Nothing was changed."; },
    sidecar_changed: function () { return "The Arrangement file changed elsewhere and has been reloaded. Redo the edit. Nothing was changed."; },
    arrangement_not_found: function () { return "There is no Arrangement with that name."; },
    region_empty: function () { return "A region needs a name."; },
    region_repeated: function () { return "That region is already in the Arrangement."; },
    region_not_in_arrangement: function () { return "That region is not in the Arrangement."; },
    slot_invalid: function () { return "That position is outside the Arrangement."; },
    headroom_invalid: function () { return "Headroom must be a number of seconds."; },
    would_be_invalid: function () { return "That edit can't be saved. Reload the page and try again. Nothing was changed."; },
    save_failed: function (e) { return "The Arrangement file couldn't be saved: " + (e.error || "unknown error") + ". Check that the project folder can be written to, then try again."; }
  };

  function error(err) {
    var one = ERRORS[err.code];
    var message = one ? one(err) : err.code;
    // A refusal after the Tempo Anchors were written changed the project. Moved items already say how to undo it.
    if (err.anchors_written && err.code !== "anchors_moved_items") {
      message += "\n\nPress Ctrl+Z in REAPER to remove the changes made so far.";
    }
    return message;
  }

  // Why a call never got a proper answer. `code` is the client's.
  function failure(code) {
    if (code === "request_too_long") return TOO_LONG;
    if (code === "no_reply") return "REAPER didn't answer in time. Apply may still be running. Look at the project in REAPER before trying again.";
    return "Can't reach REAPER. Check the connection and try again.";
  }

  function plural(n, one, many) { return n === 1 ? one : many; }
  function names(list) { return list.join(", "); }

  // The lasting effects, one line each, for a Check (what will happen) and an Apply (what happened). Only these appear on
  // screen: Tempo Anchors, automation anchors and move counts are in the run log. Keep in step with lib/text/effects.lua;
  // the page does not cap its lists.
  // what: { parked: [names], pads: {count, added}, headroom: [{name, resolved}], dropped: {items, points}, cuts, unsafe: [items] }
  function effectLines(what, past, exact) {
    var out = [];
    if (what.parked && what.parked.length) {
      out.push((past ? "Moved " : "Move ") + what.parked.length + " left-out " + plural(what.parked.length, "region", "regions") + " after the end of the Arrangement: " + names(what.parked));
    }
    if (what.pads && what.pads.count > 0) {
      var c = what.pads.count, total = f(what.pads.added, 1) + " s";
      out.push(past
        ? "Added silence to " + c + " " + plural(c, "region", "regions") + " (" + total + ")"
        : "Add silence to " + c + " " + plural(c, "region", "regions") + " so they end on a bar line (" + (exact === false ? "about " : "") + total + " in total)");
    }
    var changed = [], tooSmall = [];
    (what.headroom || []).forEach(function (h) {
      if (h.resolved === 0) tooSmall.push(h.name); else changed.push(h.name + " " + signed(h.resolved, 1) + " s");
    });
    if (changed.length) out.push((past ? "Changed" : "Change") + " the end of " + changed.length + " " + plural(changed.length, "region", "regions") + " with Headroom: " + names(changed));
    if (tooSmall.length) out.push("Headroom on " + names(tooSmall) + " " + (past ? "was" : "is") + " too small to change anything (under half a bar).");
    var d = what.dropped || { items: 0, points: 0 };
    if (d.items + d.points > 0) {
      var parts = [];
      if (d.items) parts.push(d.items + " " + plural(d.items, "item", "items"));
      if (d.points) parts.push(d.points + " automation " + plural(d.points, "point", "points"));
      out.push((past ? "Discarded " : "Discard ") + parts.join(" and ") + " that " + (past ? "were" : "are") + " in no region");
    }
    if (what.cuts > 0) out.push("Cut " + what.cuts + " " + plural(what.cuts, "item", "items") + " at region edges");
    if (what.unsafe && what.unsafe.length) {
      out.push("Apply will stop if any of these are inside a moved region: " + names(what.unsafe.map(where)) + ". Set those tracks' timebase to Time to avoid this.");
    }
    return out;
  }

  function effectsOfFindings(findings) {
    var what = {};
    findings.forEach(function (e) {
      if (e.code === "parked") what.parked = e.regions;
      else if (e.code === "padded") what.pads = { count: e.pads.length, added: e.added };
      else if (e.code === "headroom") what.headroom = e.headroom;
      else if (e.code === "dropped") what.dropped = { items: e.items.length, points: e.envelope_points.length };
      else if (e.code === "cut") what.cuts = e.splits.length;
      else if (e.code === "unsafe_timebase") what.unsafe = e.items;
    });
    return what;
  }

  // What the page shows for a Check: a headline, each refusal with its fix, and one line per effect.
  // { headline, ready, problems: [text], notPlanned, effectsHeading, effects: [text] }
  function checkSummary(reply) {
    var refused = reply.findings.filter(function (e) { return e.severity === "refusal"; });
    var has = function (code) { return reply.findings.some(function (e) { return e.code === code; }); };
    var lines = effectLines(effectsOfFindings(reply.findings), false, reply.padding_exact);
    if (refused.length) {
      return { headline: q(reply.name) + " can't be applied yet.", ready: false, problems: refused.map(finding), effects: [],
        notPlanned: has("not_planned") ? "Fix these and run Check again to see what else it would do." : null };
    }
    if (has("no_change")) {
      return { headline: q(reply.name) + " already matches the timeline. Nothing to apply.", ready: false, problems: [], effects: lines, notPlanned: null };
    }
    return { headline: "Ready to apply " + q(reply.name) + ".", ready: true, problems: [], effects: lines,
      effectsHeading: lines.length ? "This will also:" : null, notPlanned: null };
  }

  // What the page shows for a Verify: { headline, pass, lines, fix }.
  function verifySummary(reply) {
    if (reply.verdict === "pass") return { headline: "The timeline matches " + q(reply.name) + ".", pass: true, lines: [], fix: null };
    var missing = reply.findings.some(function (e) { return e.code === "region_absent"; });
    return {
      headline: "The timeline doesn't match " + q(reply.name) + ".", pass: false, lines: reply.findings.map(finding),
      fix: missing ? "Restore the missing regions in REAPER, or remove them from " + q(reply.name) + " on " + EDIT_TAB + ", then Apply again." : "Apply " + q(reply.name) + " again to fix this."
    };
  }

  // One finding as a plain line: refusals, and Verify's problems.
  var FINDINGS = {
    project_unsaved: function (e) { return ERRORS.project_unsaved(e); },
    sidecar_invalid: function (e) { return ERRORS.sidecar_invalid(e); },
    sidecar_missing: function () { return ERRORS.sidecar_missing(); },
    tempo_env_beats: function (e) { return ERRORS.tempo_env_beats(e); },
    region_names: function (e) { return ERRORS.region_names(e); },
    arrangement_unknown: function (e) { return ERRORS.arrangement_unknown(e); },
    arrangement_empty: function (e) { return ERRORS.arrangement_empty(e); },
    arrangement_missing_regions: function (e) { return ERRORS.arrangement_missing_regions(e); },
    plan_refused: function (e) { return ERRORS.plan_refused(e); },
    // Verify
    region_absent: function (e) { return q(e.region_name) + " is in the Arrangement but not in the project"; },
    order_mismatch: function (e) { return q(e.region_name) + " is before " + q(e.after); },
    block_start: function () { return "The first region doesn't start at the beginning of the timeline"; },
    gap: function (e) { return "There is a gap after " + q(e.after); },
    overlap: function (e) { return q(e.region_name) + " overlaps " + q(e.after); },
    off_bar_line: function (e) { return q(e.region_name) + " isn't on a bar line"; },
    not_parked: function (e) { return q(e.region_name) + " isn't in the Arrangement but is still among its regions"; }
  };

  function finding(entry) {
    var one = FINDINGS[entry.code];
    return one ? one(entry) : entry.code;
  }

  // The Headroom question, before anything is written.
  function headroomQuestion(requests) {
    return "Apply Headroom to " + requests.length + " " + plural(requests.length, "region", "regions") + "?\n\n" +
      lines(requests, function (r) { return "  " + r.name + ": " + signed(r.seconds, 1) + " s"; }) +
      "\n\nEach Apply moves these region ends again.";
  }

  // What a finished Apply tells the user: { headline, effects: [text], tail }.
  function applySummary(r) {
    if (r.noop) return { headline: "Arrangement " + q(r.name) + " already matches the timeline. Nothing to do.", effects: [], tail: null };
    var what = {
      parked: r.parked.names || [],
      pads: { count: r.pads.length, added: r.pads.reduce(function (sum, p) { return sum + p.added; }, 0) },
      headroom: r.headroom,
      dropped: { items: r.dropped.items.length, points: r.dropped.envelope_points.length },
      cuts: r.counts.cuts
    };
    return { headline: "Applied " + q(r.name) + ".", effects: effectLines(what, true), tail: "Undo in REAPER takes it back.\nNext: run Verify." };
  }

  var TIMEBASE = { "-1": "project default", "0": "time", "1": "beats (position, length, rate)?", "2": "beats (position only)" };
  function timebase(mode) { return TIMEBASE[String(mode)] || "UNKNOWN"; }

  // Capture's next step, which nothing else explains.
  function replaceQuestion(name) {
    return "An Arrangement named " + q(name) + " already exists. Replace it with the project's current region order?";
  }

  function rewriteQuestion() {
    return "The Arrangement file has comments or formatting that saving does not keep. Saving rewrites the whole file. Continue?";
  }

  // The editor's own sentences.
  function headroomLabel(seconds) {
    return seconds === 0 ? "No Headroom" : (seconds < 0 ? "-" : "+") + Math.abs(Number(seconds.toFixed(3))) + " s at next Apply";
  }

  function deleteQuestion(name, count) {
    return "Delete " + q(name) + " and its " + count + " region" + (count === 1 ? "" : "s") + "? This can\u2019t be undone from the page.";
  }

  // Undo (issue 08). `entry` is an inverse from editor.inverseOf.
  function undoLabel(entry) {
    var a = entry.arrangement ? " in " + q(entry.arrangement) : "";
    var r = entry.region ? " " + q(entry.region) : "";
    switch (entry.operation) {
      case "move": return "the move of" + r + a;
      case "set_headroom": return "the Headroom change of" + r + a;
      case "add": return "adding" + r + a;
      case "remove": return "removing" + r + a;
      case "clear_headroom": return "clearing the Headroom of " + q(entry.arrangement);
      case "new": return "creating " + q(entry.arrangement);
      case "duplicate": return "duplicating into " + q(entry.arrangement);
      case "rename": return "renaming to " + q(entry.arrangement);
      default: return "the last change";
    }
  }
  function undoTitle(entry) { return entry ? "Undo " + undoLabel(entry) : "Nothing to undo"; }
  function dragLabel(name) { return "Drag " + name + " to a new position"; }
  function headroomInputLabel(name) { return "Headroom in seconds for " + name; }
  function undone(entry) { return "Undid " + undoLabel(entry) + "."; }
  function undoPartial(entry) { return "Undoing " + undoLabel(entry) + " stopped half way. Look at the Arrangement; it may be partly restored."; }
  function undoRefused(entry) { return "Could not undo " + undoLabel(entry) + ": it no longer applies. That step is dropped from Undo."; }
  function undoStale() { return "The Arrangement file changed elsewhere, so Undo is cleared. The page has reloaded it."; }

  function emptyArrangementNote(name) {
    return "Arrangement " + q(name) + " is empty. Check refuses an empty Arrangement; add the regions it should play from the list below.";
  }

  // The post-Apply offer to clear the Headroom just applied (issue 09).
  var clearOffer = {
    button: "Clear the Headroom just applied",
    text: function (name) { return "Applying " + q(name) + " again would move those region ends again. You can set its Headroom back to 0 now."; },
    done: function (name) { return "The Headroom of " + q(name) + " is cleared. Undo on the Edit tab puts it back."; },
    nothing: function (name) { return q(name) + " had no Headroom left to clear."; }
  };

  function headroomInputInvalid() { return "Headroom is a number of seconds, for example 4 or -2.5."; }

  function noSidecarEditNote(sidecar, parseError) {
    if (sidecar === "invalid") return error({ code: "sidecar_invalid", error: parseError || "unknown error" });
    if (sidecar === "unsaved") return error({ code: "sidecar_unsaved" });
    if (sidecar === "missing") return "This project has no Arrangements yet. New creates one, or Capture on the Run tab saves the current region order.";
    return "";
  }

  function captureSummary(r) {
    return (r.replaced ? "Replaced " : "Captured ") + q(r.name) + " with " + r.regions.length + " region" + (r.regions.length === 1 ? "" : "s") +
      ". Next: duplicate it on the Edit tab, reorder the copy, then Check.";
  }

  return { error: error, failure: failure, finding: finding, checkSummary: checkSummary, verifySummary: verifySummary, headroomQuestion: headroomQuestion,
    applySummary: applySummary, timebase: timebase, problems: problems, captureSummary: captureSummary, replaceQuestion: replaceQuestion, rewriteQuestion: rewriteQuestion,
    undoLabel: undoLabel, undoTitle: undoTitle, dragLabel: dragLabel, headroomInputLabel: headroomInputLabel, undone: undone, undoPartial: undoPartial, undoRefused: undoRefused, undoStale: undoStale,
    headroomLabel: headroomLabel, deleteQuestion: deleteQuestion, emptyArrangementNote: emptyArrangementNote,
    headroomInputInvalid: headroomInputInvalid, clearOffer: clearOffer, noSidecarEditNote: noSidecarEditNote, trackLabel: trackLabel };
});
