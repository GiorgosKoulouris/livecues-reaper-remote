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

  // Why something stopped: a refusal's `error`. Bridge codes first, then the cores'.
  var ERRORS = {
    bad_request: function () { return "The bridge could not read the request. Reload the page; if it keeps happening, the page and the bridge are different versions: run scripts/install.ps1 and restart REAPER."; },
    request_truncated: function () { return "REAPER cut the request short, so nothing was done. Try a shorter name."; },
    unknown_command: function (e) { return "The bridge does not know the command " + q(e.command) + ". The page and the bridge are different versions: run scripts/install.ps1 and restart REAPER."; },
    missing_field: function (e) { return "The request left out " + q(e.field) + "."; },
    internal: function (e) { return "The bridge failed: " + (e.message || "unknown error") + "\n\nNothing may have been done. Check the run log beside the project before trying again."; },
    token_unknown: function () { return "This Check has expired, or was already used. Check again, then apply."; },
    token_stale: function (e) {
      if (e.reason === "other_project") return "A different project is open in REAPER now. Nothing was applied. Check again on the project you want.";
      if (e.reason === "arrangement_changed") return "This Arrangement was edited since this Check, so what you read is not what would run. Nothing was applied. Check again, then apply.";
      return "The project changed in REAPER since this Check. Nothing was applied. Check again, then apply.";
    },
    project_unsaved: function (e) { return e.message; },
    tempo_env_beats: function (e) { return e.message; },
    no_regions: function () { return "This project has no regions."; },
    region_names: function (e) { return "Every region needs a unique, non-empty name:\n\n" + problems(e.problems) + "\n\nFind them with Duplicate and unnamed regions under Diagnostics."; },
    sidecar_invalid: function (e) { return "The Arrangement sidecar exists but could not be read, so it will not be changed. Fix the file in a text editor:\n\n" + e.error; },
    sidecar_missing: function () { return "This project has no Arrangement sidecar yet. Capture an Arrangement here, or run LCRR Arrange: Apply Arrangement in REAPER to import one."; },
    sidecar_unsaved: function () { return "This project has never been saved, so it has no Arrangement sidecar. Save it in REAPER first."; },
    no_arrangements: function () { return "This project has no Arrangements yet. Capture one first."; },
    arrangement_unknown: function (e) { return q(e.name) + " is not a known Arrangement. Available: " + (e.available || []).join(", "); },
    arrangement_missing_regions: function (e) { return "Arrangement " + q(e.name) + " names regions this project does not have:\n\n  " + e.missing.join("\n  "); },
    plan_refused: function (e) { return e.error; },
    plan_out_of_scope: function (e) { return "Arrangement " + q(e.name) + " needs more than this can do yet:\n\n" + e.error; },
    anchors_moved_items: function (e) {
      return "Writing the Tempo Anchors moved media items, so this run was stopped before it planned anything against the moved timeline.\n\nBeat-attached material follows a tempo-map edit, and these items followed one:\n\n" + problems(e.moved);
    },
    name_empty: function () { return "An Arrangement needs a name."; },
    name_taken: function () { return "An Arrangement with that name already exists. Pick another name."; },
    other_project: function () { return "A different project is active in REAPER now. Nothing was changed. Reload the page's view of the project before editing."; },
    sidecar_changed: function () { return "The Arrangement file changed since this page read it (in a text editor, or by a Capture). Nothing was changed. The page has reloaded it: redo the edit."; },
    operation_unknown: function () { return "The bridge does not know that edit. The page and the bridge are different versions: run scripts/install.ps1 and restart REAPER."; },
    arrangement_not_found: function () { return "There is no Arrangement with that name."; },
    region_empty: function () { return "A region needs a name."; },
    region_repeated: function () { return "That region is already in the Arrangement."; },
    region_not_in_arrangement: function () { return "That region is not in the Arrangement."; },
    slot_invalid: function () { return "That position is outside the Arrangement."; },
    headroom_invalid: function () { return "Headroom must be a number of seconds."; },
    would_be_invalid: function () { return "That edit would produce a file that cannot be read, so nothing was written."; },
    save_failed: function (e) { return e.error; },
    no_tracks: function () { return "This project has no tracks."; }
  };

  function error(err) {
    var one = ERRORS[err.code];
    var message = one ? one(err) : err.code;
    if (err.anchors_written) {
      message += "\n\n" + err.anchors_written + " Tempo Anchor(s) were written before this was detected, and nothing else was. They are one undo step: Undo in REAPER removes them.";
    }
    return message;
  }

  // Why a call never got a proper answer. `code` is the client's.
  function failure(code) {
    if (code === "request_too_long") return "That request is too long to send. Use a shorter name.";
    if (code === "no_reply") return "REAPER took the request but the bridge did not answer in time. If this was Apply, it may still be running or may have finished: check REAPER and the run log beside the project before doing anything else.";
    return "REAPER did not take the request. Check the connection and try again.";
  }

  var SEVERITY_HEADING = {
    refusal: "Would refuse",
    permanent: "Would happen, and running again will not undo it",
    informational: "For information"
  };
  function severityHeading(s) { return SEVERITY_HEADING[s] || s; }

  var BLIND_SPOTS = {
    padding_grid: "Padding measured against the grid the Tempo Anchors will create. Until they are written, Padding is computed against the grid as it stands now.",
    anchor_drift: "Whether writing the Tempo Anchors moves beat-attached material. That can only be detected after the write, and the run refuses if it happens.",
    padding_overlap: "Whether Padding would run a region into its neighbour once the anchors exist, which follows from the two above.",
    headroom_count: "Whether a Headroom was applied once or twice. Headroom describes a change to a region's end rather than a target length, so nothing in the finished timeline records how many times it was applied. Apply's confirmation is the only guard against that."
  };
  function blindSpot(code) { return BLIND_SPOTS[code] || code; }

  var FINDINGS = {
    project_unsaved: function (e) { return e.message; },
    sidecar_invalid: function (e) { return "The Arrangement sidecar exists but could not be read: " + (e.error || "unknown error"); },
    sidecar_missing: function () { return ERRORS.sidecar_missing(); },
    tempo_env_beats: function (e) { return e.message; },
    region_names: function (e) { return "Every region needs a unique, non-empty name before an Arrangement can key on it:\n" + problems(e.problems); },
    arrangement_unknown: function (e) { return q(e.name) + " is not a known Arrangement. Available: " + (e.available || []).join(", "); },
    arrangement_empty: function (e) { return "Arrangement " + q(e.name) + " has no regions in it. Applying it would park every region, which is never what an Arrangement is for. Add the regions it should play, in order."; },
    arrangement_missing_regions: function (e) { return "This Arrangement names regions the project does not have:\n  " + e.missing.join("\n  "); },
    parked: function (e) {
      return e.regions.length + " region(s) this Arrangement omits will be moved beyond the Packed Block as Parked Material. Nothing is deleted, and the run log records the offset that reverses it:\n  " + e.regions.join("\n  ");
    },
    unsafe_timebase: function (e) {
      return e.items.length + " item(s) sit on a timebase this suite cannot confirm safe to reposition. A run refuses if any of them is inside a region it moves:\n" +
        lines(e.items, function (i) { return "    " + named(i.track_index, i.track_name) + " at " + f(i.position, 3) + " (" + f(i.length, 3) + "s)"; });
    },
    not_planned: function () {
      return "The problems above stopped this check before it could plan the Repack, so it has NOT reported Padding, Dropped Material, Straddling Item cuts, or whether the pack itself would refuse. Fix them and check again.";
    },
    plan_refused: function (e) { return e.error; },
    headroom: function (e) {
      return e.headroom.length + " region(s) will have their end moved by HEADROOM. This is relative, not absolute: applying this Arrangement again moves them again, and you will be asked to confirm before it does:\n" +
        lines(e.headroom, function (r) {
          return "    " + r.name + ": asked " + signed(r.requested, 3) + "s, resolves to " + signed(r.resolved, 3) + "s (" + (r.bars < 0 ? "-" : "+") + Math.abs(r.bars) + " bar(s)), end " + f(r.from_end, 3) + " -> " + f(r.to_end, 3) +
            (r.resolved === 0 ? " -- NO CHANGE, the request is under half a bar" : "");
        });
    },
    padded: function (e) {
      return e.pads.length + " region(s) will be PADDED to the next bar line, adding " + f(e.added, 3) + "s of silence inside their bounds -- permanently, and this does not happen again on a later Repack:\n" +
        lines(e.pads, function (p) { return "    " + p.name + ": end " + f(p.from_end, 3) + " -> " + f(p.to_end, 3) + " (+" + f(p.added, 3) + "s)"; });
    },
    dropped: function (e) {
      var rows = e.items.map(function (d) {
        return "    " + named(d.track_index, d.track_name) + ": " + f(d.position, 3) + ".." + f(d.position + d.length, 3) + " (" + f(d.length, 3) + "s)";
      }).concat(e.envelope_points.map(function (d) {
        return "    envelope point, " + named(d.track_index, d.track_name) + ", " + q(d.envelope_name) + ": " + f(d.position, 3);
      }));
      return e.items.length + " piece(s) of material and " + e.envelope_points.length + " envelope point(s) touch no region and will be DISCARDED. Undo restores them; the run log is the only other record:\n" + rows.join("\n");
    },
    cut: function (e) {
      return e.splits.length + " Straddling Item cut(s) will be made, at region bounds this run moves:\n" +
        lines(e.splits, function (s) { return "    " + named(s.track_index, s.track_name) + " at " + f(s.position, 3); });
    },
    no_change: function () { return "This Arrangement already matches the timeline. Applying it would change nothing."; },
    moves: function (e) {
      var c = e.counts;
      return c.regions + " region(s), " + c.markers + " marker(s), " + c.tempo_markers + " tempo marker(s), " + c.envelope_points + " envelope point(s) and " + c.items + " item(s) will move.";
    },
    // Verify
    region_absent: function (e) { return "Arrangement names region " + q(e.region_name) + ", which this project does not have."; },
    order_mismatch: function (e) { return "Region " + q(e.region_name) + " starts at " + f(e.at, 3) + ", before " + q(e.after) + " at " + f(e.after_at, 3) + ", but the Arrangement puts it after."; },
    block_start: function (e) { return "The Packed Block starts at " + f(e.at, 3) + " rather than at the beginning of the timeline."; },
    gap: function (e) { return "Region " + q(e.region_name) + " starts " + f(e.size, 3) + "s after " + q(e.after) + " ends -- the Packed Block is not contiguous."; },
    overlap: function (e) { return "Region " + q(e.region_name) + " starts " + f(e.size, 3) + "s before " + q(e.after) + " ends."; },
    off_bar_line: function (e) { return "Region " + q(e.region_name) + " starts at " + f(e.at, 3) + "; the nearest bar line at or after it is " + f(e.expected, 3) + "."; },
    not_parked: function (e) { return "Region " + q(e.region_name) + " is not in the Arrangement but starts at " + f(e.at, 3) + ", inside the Packed Block which ends at " + f(e.packed_end, 3) + "."; }
  };

  function finding(entry) {
    var one = FINDINGS[entry.code];
    return one ? one(entry) : entry.code;
  }

  // Padding's accuracy, stated once for a Check.
  function paddingNote(exact) {
    return exact
      ? "Padding and Headroom above are EXACT: every Tempo Anchor this project needs is already present, so the current bar grid is the one a run would plan against."
      : "Padding and Headroom above are ESTIMATES: this project still needs Tempo Anchors, and they are what put region starts on bar lines. Both are measured against bar lines, so both move with the grid. Check again after applying to see exact figures.";
  }

  // One line above a Check's findings.
  function checkVerdict(reply) {
    var refusals = 0, permanent = 0;
    reply.findings.forEach(function (e) { if (e.severity === "refusal") refusals++; else if (e.severity === "permanent") permanent++; });
    if (refusals > 0) return "Applying " + q(reply.name) + " WOULD REFUSE: " + refusals + " problem(s)" + (permanent ? ", plus " + permanent + " permanent effect(s) to be aware of" : "") + ". Nothing has been changed.";
    if (permanent > 0) return "Applying " + q(reply.name) + " would proceed, with " + permanent + " permanent effect(s) worth reading first. Nothing has been changed.";
    return "Applying " + q(reply.name) + " would proceed, with nothing permanent beyond the Repack itself. Nothing has been changed.";
  }

  function verifyVerdict(reply) {
    return reply.verdict === "pass"
      ? "PASS: the timeline matches " + q(reply.name) + ". The named regions are in order and contiguous from the start of the timeline, every packed region start is on a bar line, and every omitted region sits beyond the Packed Block."
      : "FAIL: the timeline does not match " + q(reply.name) + ". " + reply.findings.length + " problem(s) found.";
  }

  // The Headroom question, before anything is written.
  function headroomQuestion(requests) {
    return "This Arrangement adjusts the Headroom of " + requests.length + " region(s):\n\n" +
      lines(requests, function (r) { return "  " + r.name + ": " + signed(r.seconds, 3) + "s"; }) +
      "\n\nHeadroom is RELATIVE: it moves each region's end from where it is now, so applying this Arrangement a second time moves those ends a second time. Every other part of a Repack can be run repeatedly without changing the result; this cannot." +
      "\n\nEach end is rounded to the nearest bar line, so a request under half a bar resolves to no change. The run log records what each one actually resolved to.";
  }

  // What a finished Apply tells the user: a list of paragraphs.
  function applySummary(r) {
    if (r.noop) return ["Arrangement " + q(r.name) + " already matches the timeline. Nothing to do."];
    var c = r.counts, out = [];
    out.push("Applied " + q(r.name) + ": " + c.regions + " region(s), " + c.markers + " marker(s), " + c.tempo_markers + " tempo marker(s), " + c.envelope_points + " envelope point(s) and " + c.items + " item(s) moved, " + c.cuts + " cut(s) made.");
    if (r.anchors.changing > 0) {
      out.push(r.anchors.changing + " Tempo Anchor(s) were written at region starts (" + (r.anchors.total - r.anchors.changing) + " of " + r.anchors.total + " region(s) already had one with the right values), so each region carries its own bar grid regardless of what a Repack puts in front of it.");
    }
    if (r.headroom.length) {
      out.push(r.headroom.length + " region(s) had their end moved by HEADROOM:\n  " + r.headroom.map(function (h) {
        return h.name + ": " + signed(h.resolved, 3) + "s (" + (h.bars < 0 ? "-" : "+") + Math.abs(h.bars) + " bar(s))" + (h.resolved === 0 ? " -- no change, the request was under half a bar" : "");
      }).join("\n  ") + "\n\nThis is relative, not absolute: applying this Arrangement again would move them again.");
    }
    if (r.pads.length) {
      var added = r.pads.reduce(function (sum, p) { return sum + p.added; }, 0);
      out.push(r.pads.length + " region(s) were PADDED to the next bar line, adding " + f(added, 3) + "s of silence inside their bounds -- permanently, and this does not happen again on a later Repack:\n  " +
        r.pads.map(function (p) { return p.name + " (+" + f(p.added, 3) + "s)"; }).join("\n  "));
    }
    if (c.envelope_anchors > 0) {
      out.push(c.envelope_anchors + " automation anchor(s) were written at region bounds, so each region keeps its own automation values instead of inheriting its new neighbour's. They are listed in the run log.");
    }
    if (r.parked.regions + r.parked.other > 0) {
      out.push(r.parked.regions + " region(s) this Arrangement omits, and " + r.parked.other + " other piece(s) of material, were PARKED " + f(r.parked.delta, 3) + "s later -- beyond the Packed Block, with their internal timing intact. Nothing was deleted; the run log gives the offset, and negating it reverses the parking.");
    }
    var discarded = r.dropped.items.length + r.dropped.envelope_points.length;
    if (discarded > 0) {
      out.push(r.dropped.items.length + " piece(s) of material and " + r.dropped.envelope_points.length + " envelope point(s) touching no region were DISCARDED. They are listed in the run log beside the project; Undo in REAPER restores them.");
    }
    return out;
  }

  var TIMEBASE = { "-1": "project default", "0": "time", "1": "beats (position, length, rate)?", "2": "beats (position only)" };
  function timebase(mode) { return TIMEBASE[String(mode)] || "UNKNOWN"; }

  // Capture's next step, which nothing else explains.
  function replaceQuestion(name) {
    return "An Arrangement named " + q(name) + " already exists. Replace it with the project's current region order?";
  }

  function rewriteQuestion() {
    return "The Arrangement sidecar has comments or formatting that saving does not keep. Saving rewrites the whole file. Continue?";
  }

  // The editor's own sentences.
  function headroomLabel(seconds) {
    return seconds === 0 ? "No Headroom" : (seconds < 0 ? "-" : "+") + Math.abs(Number(seconds.toFixed(3))) + " s at next Apply";
  }

  function deleteQuestion(name, count) {
    return "Delete the Arrangement " + q(name) + " and its " + count + " region" + (count === 1 ? "" : "s") + "? This cannot be undone from the page. The run log keeps the list of regions, so it could be rebuilt.";
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
    if (sidecar === "missing") return "This project has no Arrangement sidecar yet. New creates one, or Capture on the Run tab saves the current region order.";
    return "";
  }

  function captureSummary(r) {
    return (r.replaced ? "Replaced " : "Captured ") + q(r.name) + " with " + r.regions.length + " regions.\n\n" +
      "Next, in a text editor on the host, open " + r.path + ":\n" +
      "  1. Duplicate the [" + q(r.name) + "] = { ... } block and give the copy a different name.\n" +
      "  2. Reorder the Region Names inside the copy, or delete some to make a subset.\n" +
      "  3. Set `headroom` on any entry to add or remove seconds at that region's end. It is rounded to the nearest bar, and it is relative: applying twice moves twice.\n" +
      "  4. Come back here: Check the new name, then Apply, then Verify.\n\n" +
      "Editing the copy leaves " + q(r.name) + " intact as a record of the current order.";
  }

  return { error: error, failure: failure, finding: finding, severityHeading: severityHeading, blindSpot: blindSpot,
    paddingNote: paddingNote, checkVerdict: checkVerdict, verifyVerdict: verifyVerdict, headroomQuestion: headroomQuestion,
    applySummary: applySummary, timebase: timebase, problems: problems, captureSummary: captureSummary, replaceQuestion: replaceQuestion, rewriteQuestion: rewriteQuestion,
    undoLabel: undoLabel, undone: undone, undoPartial: undoPartial, undoRefused: undoRefused, undoStale: undoStale,
    headroomLabel: headroomLabel, deleteQuestion: deleteQuestion, emptyArrangementNote: emptyArrangementNote,
    headroomInputInvalid: headroomInputInvalid, clearOffer: clearOffer, noSidecarEditNote: noSidecarEditNote, trackLabel: trackLabel };
});
