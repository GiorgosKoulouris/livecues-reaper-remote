// Snapshots: page logic (pure, no DOM). The bridge's replies come in, plain facts go out.
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.snapshots = L.snapshots || {}).core = api; }
})(this, function () {
  "use strict";

  // Is the bridge reachable? `offline` is the connection guard's verdict, `everLive` whether any poll has worked,
  // `beat` the heartbeat state ("unknown" | "running" | "stopped").
  function connectionPhase(offline, everLive, beat) {
    if (offline) return "offline";
    if (!everLive) return "connecting";
    if (beat === "stopped") return "bridge-down";
    if (beat === "unknown") return "connecting";
    return "ready";
  }

  // The `state` reply, or null when it is not one a page can draw (a refusal, or a shape from another version).
  function readState(reply) {
    if (!reply || reply.status !== "ok" || reply.command !== "state") return null;
    var p = reply.project;
    if (!p || typeof p.name !== "string" || typeof p.path !== "string") return null;
    return reply;
  }

  // Controls exist only while the bridge is running.
  function canUse(phase) { return phase === "ready"; }

  // Did the bridge do what was asked? (A successful write clears the restore note; a refused or failed one leaves it.)
  function succeeded(reply) { return !!reply && reply.status === "ok"; }

  var MAX_NAME = 40; // characters; the bridge's own limit (shared.snapshot.text)

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

  // The `snapshots` reply's list, or null when it is not one the page can draw.
  function readList(reply) {
    if (!reply || reply.status !== "ok" || reply.command !== "snapshots" || !Array.isArray(reply.snapshots)) return null;
    return reply.snapshots.map(function (s) {
      return { name: String(s.name), saved: s.saved, tracks: s.tracks, sends: s.sends, solo: !!s.solo, masterMuted: !!s.master_muted };
    });
  }

  // Do two lists draw the same? An identical reply leaves the rows untouched.
  function sameList(a, b) { return JSON.stringify(a) === JSON.stringify(b); }

  // The list is not rebuilt while a press-and-hold is down (the rebuild would replace the key under the finger and
  // lose its release). `request()` paints now, or once when the last hold ends; `paint` reads the latest list itself.
  function createGate(paint) {
    var holds = 0, pending = false;
    function flush() { if (!holds && pending) { pending = false; paint(); } }
    return {
      request: function () { if (holds) pending = true; else { pending = false; paint(); } },
      begin: function () { holds++; },
      end: function () { if (holds) holds--; flush(); },
      active: function () { return holds > 0; }
    };
  }

  // One press-and-hold key's logic over LCRR.shared.hold (`createHold` is injected). down() starts a hold and tells
  // the gate; up() is any release, leave, blur or cancel. Only a hold that runs its full time calls `onComplete`,
  // once, after the gate has ended (so a deferred rebuild has run); an early release sends nothing.
  function createPress(opts) {
    var down = false;
    function finish() {
      if (!down) return false;
      down = false;
      opts.gate.end();
      return true;
    }
    var hold = opts.createHold({
      holdMs: opts.holdMs,
      onCancel: function () { finish(); },
      onComplete: function () { if (finish()) opts.onComplete(); }
    });
    return {
      down: function () { if (down) return; down = true; opts.gate.begin(); hold.start(); },
      up: function () { hold.cancel(); finish(); },
      isDown: function () { return down; }
    };
  }

  return { createGate: createGate, createPress: createPress, checkName: checkName, readList: readList, sameList: sameList, connectionPhase: connectionPhase, readState: readState, canUse: canUse, succeeded: succeeded };
});
