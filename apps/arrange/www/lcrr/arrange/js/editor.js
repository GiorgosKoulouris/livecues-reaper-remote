// Arrange: the Arrangement editor's model (pure). The two lists, drop and step arithmetic, Headroom input, name checks,
// and the one place an edit is sent and its reply folded back into what the page knows (`createEditor`). No DOM here:
// node tests drive it. Undo (issue 08) is the stack inside `createEditor`: every `ok` dispatch pushes its inverse, so an
// edit sent from anywhere on the page (the post-Apply offer, issue 09) is undoable with no extra call.
// See apps/arrange/docs/bridge.md for the wire and ADR-0009 for why the page edits the sidecar.
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.arrange = L.arrange || {}).editor = api; }
})(this, function () {
  "use strict";

  // ---- lists ------------------------------------------------------------------------------------------------------

  // The Arrangement's entries ("In this Arrangement", in play order) and the project's regions it omits ("Left out",
  // timeline order). An entry whose name is no region of the project is flagged and can only be removed.
  function splitLists(entries, regions) {
    var inProject = {}, used = {};
    regions.forEach(function (r) { inProject[r.name] = true; });
    entries.forEach(function (e) { used[e.name] = true; });
    return {
      inList: entries.map(function (e) { return { name: e.name, headroom: e.headroom || 0, inProject: !!inProject[e.name] }; }),
      leftOut: regions.filter(function (r) { return !used[r.name]; }).map(function (r) { return { name: r.name }; })
    };
  }

  // ---- moves ------------------------------------------------------------------------------------------------------

  // Dropping row `from` (0-based) into gap `gap` (0 = before the first row, length = after the last) is one move to a
  // final 1-based slot. Null when it would not change anything.
  function slotForDrop(from, gap, length) {
    if (from < 0 || from >= length || gap < 0 || gap > length) return null;
    var final = gap > from ? gap - 1 : gap;
    return final === from ? null : final + 1;
  }

  // Up (-1) or down (+1) one step: the final 1-based slot, or null at the end of the list.
  function slotForStep(from, direction, length) {
    var to = from + direction;
    if (from < 0 || from >= length || to < 0 || to >= length) return null;
    return to + 1;
  }

  // The gap a pointer at `y` is over, given the vertical midpoints of the rows in order.
  function gapAt(y, mids) {
    var gap = 0;
    mids.forEach(function (m) { if (m < y) gap++; });
    return gap;
  }

  // ---- Headroom ---------------------------------------------------------------------------------------------------

  function round3(n) {
    var r = Math.round(n * 1000) / 1000;
    return r === 0 ? 0 : r; // no -0
  }

  // Typed seconds: "4", "+4", "-2.5", "2,5", "4 s", "" (= none). { ok, seconds }.
  function parseHeadroom(text) {
    var t = String(text == null ? "" : text).trim().toLowerCase().replace(",", ".");
    t = t.replace(/\s*(seconds|second|secs|sec|s)$/, "");
    if (t === "" || t === "+" || t === "-") return t === "" ? { ok: true, seconds: 0 } : { ok: false };
    if (!/^[+-]?(\d+\.?\d*|\.\d+)$/.test(t)) return { ok: false };
    var n = Number(t);
    return isFinite(n) ? { ok: true, seconds: round3(n) } : { ok: false };
  }

  // Seconds as the page shows and sends them: no trailing zeros, no plus sign.
  function formatSeconds(n) {
    var s = String(round3(n));
    return /e/i.test(s) ? Number(s).toFixed(3).replace(/\.?0+$/, "") : s;
  }

  function stepHeadroom(current, step) { return round3((Number(current) || 0) + step); }

  // ---- names ------------------------------------------------------------------------------------------------------

  // The page's own check before it sends New, Duplicate or Rename: { ok, name } or { ok: false, code }. The core
  // checks again; this only saves a round trip. `existing` is every name already taken, so renaming to the
  // current name is refused as taken, here and in the core.
  function checkName(raw, existing) {
    var name = String(raw == null ? "" : raw).trim();
    if (name === "") return { ok: false, code: "name_empty" };
    if (existing.indexOf(name) >= 0) return { ok: false, code: "name_taken" };
    return { ok: true, name: name };
  }

  // A name for a copy that is not taken: "Name copy", "Name copy 2", ...
  function copyName(name, existing) {
    var base = name + " copy", candidate = base, n = 2;
    while (existing.indexOf(candidate) >= 0) { candidate = base + " " + n; n++; }
    return candidate;
  }

  // ---- undo -------------------------------------------------------------------------------------------------------

  function indexOfEntry(entries, region) {
    for (var i = 0; i < entries.length; i++) if (entries[i].name === region) return i;
    return -1;
  }

  // The inverse of one successful edit (an `ok` outcome of dispatch): { operation, arrangement, region, steps } where
  // `steps` are ordinary edits, sent in order, or null when the edit has no inverse (Delete, or an edit that changed
  // nothing). Applying the edit and then its steps returns the same Arrangement (New and Duplicate: removes it again).
  function inverseOf(out) {
    var f = out.fields || {}, before = out.before, steps = null, arrangement = out.name, region = f.region;
    function setHeadroom(arr, name, seconds) { return { operation: "set_headroom", fields: { arrangement: arr, region: name, headroom: formatSeconds(seconds) } }; }
    var i = before && f.region != null ? indexOfEntry(before, f.region) : -1;
    switch (out.operation) {
      case "move":
        if (i >= 0) steps = [{ operation: "move", fields: { arrangement: f.arrangement, region: f.region, slot: String(i + 1) } }];
        break;
      case "set_headroom":
        if (i >= 0) steps = [setHeadroom(f.arrangement, f.region, before[i].headroom || 0)];
        break;
      case "add":
        steps = [{ operation: "remove", fields: { arrangement: f.arrangement, region: f.region } }];
        break;
      case "remove":
        if (i >= 0) {
          steps = [{ operation: "add", fields: { arrangement: f.arrangement, region: f.region, slot: String(i + 1) } }];
          if (before[i].headroom) steps.push(setHeadroom(f.arrangement, f.region, before[i].headroom));
        }
        break;
      case "clear_headroom":
        steps = (before || []).filter(function (e) { return e.headroom; }).map(function (e) { return setHeadroom(f.arrangement, e.name, e.headroom); });
        if (!steps.length) steps = null;
        break;
      case "new":
      case "duplicate":
        steps = [{ operation: "delete", fields: { arrangement: out.name } }];
        break;
      case "rename":
        steps = [{ operation: "rename", fields: { arrangement: out.name, name: f.arrangement } }];
        region = undefined;
        break;
    }
    return steps ? { operation: out.operation, arrangement: arrangement, region: region, steps: steps } : null;
  }

  var UNDO_DEPTH = 100;

  // ---- the editor -------------------------------------------------------------------------------------------------

  function copyEntries(list) { return list.map(function (e) { return { name: e.name, headroom: e.headroom || 0 }; }); }

  // `client` has `arrangements()` and `edit(base, operation, fields)` (client.js), both returning the bridge's reply
  // or rejecting with an Error carrying `code`.
  function createEditor(client) {
    var state = { loaded: false, sidecar: "unsaved", revision: "none", canonical: true, parseError: null,
      projectPath: null, arrangements: [], regions: [] };
    var listeners = [];
    var stack = []; // inverses of this session's edits, oldest first

    function find(name) {
      for (var i = 0; i < state.arrangements.length; i++) if (state.arrangements[i].name === name) return state.arrangements[i];
      return null;
    }
    function names() { return state.arrangements.map(function (a) { return a.name; }); }
    function entriesOf(name) { var a = find(name); return a ? copyEntries(a.entries) : null; }
    function subscribe(fn) { listeners.push(fn); }
    function view() { return state; } // read-only by convention

    // Read the sidecar and the project's regions. Resolves { changed }; rejects like the client.
    function load() {
      return client.arrangements().then(function (reply) {
        if (reply.status !== "ok") { var e = new Error("arrangements refused"); e.code = "refused"; e.reply = reply; throw e; }
        var was = state.loaded;
        var before = state.revision + "|" + state.sidecar + "|" + state.projectPath + "|" + state.loaded;
        state.loaded = true;
        state.sidecar = reply.sidecar;
        state.revision = reply.revision || "none";
        state.canonical = reply.canonical !== false;
        state.parseError = reply.parse_error || null;
        state.projectPath = reply.project ? reply.project.path : null;
        state.arrangements = (reply.arrangements || []).map(function (a) { return { name: a.name, entries: copyEntries(a.entries) }; });
        state.regions = reply.regions || [];
        var changed = before !== state.revision + "|" + state.sidecar + "|" + state.projectPath + "|" + true;
        if (changed && was) stack.length = 0; // the file or project moved under us: the inverses no longer apply
        return { changed: changed, reply: reply };
      });
    }

    // Fold an `ok` edit reply into the state. `fields` are what was sent.
    function fold(op, fields, reply) {
      state.revision = reply.revision;
      state.sidecar = "ok";
      state.canonical = true;
      var arrs = state.arrangements;
      if (op === "delete") arrs = arrs.filter(function (a) { return a.name !== fields.arrangement; });
      else if (op === "new") arrs = arrs.concat([{ name: reply.name, entries: [] }]);
      else if (op === "duplicate") arrs = arrs.concat([{ name: reply.name, entries: copyEntries(reply.entries) }]);
      else if (op === "rename") arrs = arrs.map(function (a) { return a.name === fields.arrangement ? { name: reply.name, entries: a.entries } : a; });
      else arrs = arrs.map(function (a) { return a.name === reply.name ? { name: a.name, entries: copyEntries(reply.entries) } : a; });
      var order = reply.names || [];
      arrs = arrs.slice().sort(function (a, b) { return order.indexOf(a.name) - order.indexOf(b.name); });
      state.arrangements = arrs;
    }

    function record(out) {
      if (out.operation === "delete") { // entries about a deleted Arrangement can no longer apply
        stack = stack.filter(function (e) { return e.arrangement !== out.fields.arrangement; });
        return;
      }
      var inv = inverseOf(out);
      if (!inv) return;
      stack.push(inv);
      if (stack.length > UNDO_DEPTH) stack.shift();
    }

    function undoDepth() { return stack.length; }
    function peekUndo() { return stack.length ? stack[stack.length - 1] : null; }

    // Undo the latest edit by sending its inverse as ordinary edits (revision-checked; never pushed back, no Redo).
    // Resolves one outcome, never rejects:
    //   { kind: "empty" }                nothing to undo
    //   { kind: "undone", entry }
    //   { kind: "stale", error }         the file moved: reloaded, and the whole stack dropped
    //   { kind: "refused", error }       the inverse no longer applies; that entry is dropped
    //   { kind: "partial", entry, error } a later step of a multi-edit inverse failed; entry dropped
    //   { kind: "failed", code }         no proper answer; entry kept (try again)
    function undo() {
      var entry = stack.pop();
      if (!entry) return Promise.resolve({ kind: "empty" });
      var i = 0;
      function next() {
        if (i >= entry.steps.length) return Promise.resolve({ kind: "undone", entry: entry });
        var step = entry.steps[i];
        return dispatch(step.operation, step.fields, { undo: true }).then(function (out) {
          if (out.kind === "ok") { i++; return next(); }
          if (out.kind === "stale") { stack.length = 0; return out; }
          var first = i === 0;
          if (out.kind === "confirm") out = { kind: "failed", code: "unreachable" }; // cannot happen: our own write made the file canonical
          if (out.kind === "failed") { if (first) stack.push(entry); return first ? out : { kind: "partial", entry: entry, error: { code: out.code } }; }
          return first ? out : { kind: "partial", entry: entry, error: out.error };
        });
      }
      return next();
    }

    // Send one operation. Resolves one outcome, never rejects:
    //   { kind: "ok", operation, fields, name, before, after, reply }   before/after: the Arrangement's entries (null when absent)
    //   { kind: "confirm", code: "rewrite" }   nothing written; ask, then dispatch again with { rewrite: true }
    //   { kind: "stale", error }               refused because the file or project moved; state has been reloaded
    //   { kind: "refused", error }             refused, nothing written
    //   { kind: "failed", code }               no proper answer (client codes: request_too_long, unreachable, no_reply, busy)
    function dispatch(operation, fields, opts) {
      fields = fields || {};
      opts = opts || {};
      var target = fields.arrangement;
      var before = target ? entriesOf(target) : null;
      var base = { project: state.projectPath, revision: state.revision, rewrite: !!opts.rewrite };
      return client.edit(base, operation, fields).then(function (reply) {
        if (reply.status === "confirm") return { kind: "confirm", code: reply.confirm.code };
        if (reply.status === "ok") {
          fold(operation, fields, reply);
          var name = operation === "new" || operation === "duplicate" || operation === "rename" ? reply.name : target;
          var out = { kind: "ok", operation: operation, fields: fields, name: name, before: before, after: entriesOf(name), reply: reply };
          if (!opts.undo) record(out);
          listeners.forEach(function (fn) { fn(out); });
          return out;
        }
        var err = reply.error || { code: "unknown" };
        if (err.code === "sidecar_changed" || err.code === "other_project") {
          return load().then(function () { return { kind: "stale", error: err }; }, function () { return { kind: "stale", error: err }; });
        }
        return { kind: "refused", error: err };
      }, function (err) {
        return { kind: "failed", code: err.code || "unreachable" };
      });
    }

    return { load: load, dispatch: dispatch, undo: undo, undoDepth: undoDepth, peekUndo: peekUndo, subscribe: subscribe, view: view, find: find, names: names, entriesOf: entriesOf };
  }

  // After an Apply: should the Run result offer "Clear the Headroom just applied"? `answer` is the Headroom answer the
  // page sent ("apply", "zero" or null when none was asked), `reply` the Apply reply. Returns { arrangement } or null.
  // No offer for a refusal, a cancel, a no-op, "zero" (Repack only), or a Headroom that is all zero.
  function clearHeadroomOffer(answer, reply) {
    if (!reply || reply.status !== "ok" || reply.noop || answer === "zero" || answer === "cancel") return null;
    var list = reply.headroom;
    if (!Array.isArray(list) || !list.some(function (r) { return r && Number(r.requested) !== 0; })) return null;
    return typeof reply.name === "string" && reply.name ? { arrangement: reply.name } : null;
  }

  return { clearHeadroomOffer: clearHeadroomOffer, splitLists: splitLists, slotForDrop: slotForDrop, slotForStep: slotForStep, gapAt: gapAt,
    parseHeadroom: parseHeadroom, formatSeconds: formatSeconds, stepHeadroom: stepHeadroom,
    checkName: checkName, copyName: copyName, inverseOf: inverseOf, createEditor: createEditor };
});
