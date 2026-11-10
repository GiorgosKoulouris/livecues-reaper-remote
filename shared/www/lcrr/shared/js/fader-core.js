// LCRR shared: the fader's pure logic (no DOM, no network): the level law, the level and mute write commands,
// the drag controller and the mute writer. Used by Monitor and IEM Mix. What decides whether a write may go out
// (the app's state shape) stays in the app and is passed in as `check(target)`. Works in browsers and in node tests.
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.shared = L.shared || {}).faderCore = api; }
})(this, function () {
  "use strict";

  // ---- Faders ----
  var CAP = Math.pow(10, 6 / 20); // +6 dB, the highest level any drag can write
  var WHEEL_IDLE_MS = 400;        // a wheel burst has ended after this long with no step

  // value = pos^4 * CAP. pos is the thumb position from 0 (silence) to 1 (+6 dB); 0 dB sits at about 0.84.
  function faderValue(pos) {
    if (!(pos > 0)) return 0;
    return pos >= 1 ? CAP : Math.pow(pos, 4) * CAP;
  }
  // Inverse. A level above the cap parks at 1 (the thumb's end); the dB readout still shows the true level.
  function faderPos(value) {
    if (!(value > 0)) return 0;
    return value >= CAP ? 1 : Math.pow(value / CAP, 0.25);
  }

  // SET/TRACK/<t>/SEND/<y>/VOL/<v>; with `end` the "e" suffix, which only ends the move (and adds the undo entry).
  function setVolCommand(track, y, value, end) {
    var v = value.toFixed(6).replace(/\.?0+$/, "");
    return "SET/TRACK/" + track + "/SEND/" + y + "/VOL/" + (v === "" ? "0" : v) + (end ? "e" : "");
  }

  // SET/TRACK/<t>/SEND/<y>/MUTE/<0|1>: the state to set, never a toggle, never a level.
  function setMuteCommand(track, y, muted) {
    return "SET/TRACK/" + track + "/SEND/" + y + "/MUTE/" + (muted ? 1 : 0);
  }

  // One row's mute writes. press() works out the new state from the on-screen state and sends it, unless the
  // stale check fails or the previous mute write is still outstanding (a double tap). Whether the write worked
  // or not, a read must have begun after it settled before it can change the screen (readToken/canApply).
  // opts: check(target) -> bool, send(cmd) -> Promise.
  function createMuteWriter(opts) {
    var inflight = false, seq = 0;
    return {
      press: function (target, mutedOnScreen) {
        if (inflight || !opts.check(target)) return false;
        inflight = true;
        var done = function () { inflight = false; seq++; };
        var p;
        try { p = opts.send(setMuteCommand(target.track, target.y, !mutedOnScreen)); } catch (err) { p = Promise.reject(err); }
        p.then(done, done);
        return true;
      },
      busy: function () { return inflight; },
      readToken: function () { return inflight ? -1 : seq; },
      canApply: function (token) { return token === seq && !inflight; }
    };
  }

  // One drag-controlled value's write state: the level fader (source rows and master) and the send pan share it.
  // opts: now(), setTimer(fn, ms), clearTimer(h), send(cmd) -> Promise, check(target) -> bool (the stale check,
  // run at the moment each request would go out), gateMs (50), slopPx (3), travelPx (thumb travel in px),
  // wheelIdleMs (400): how long the wheel must be idle before its `e` goes out (see nudge).
  // The write and the mapping are injected; the defaults are the level fader's:
  //   command(track, y, value, end) -> string (setVolCommand), toValue(pos) -> value (faderValue),
  //   toPos(value) -> pos (faderPos); pos runs 0..1 along the control.
  // Movement is relative: move(dx) takes the distance from the press, positive toward louder.
  function createFaderDrag(opts) {
    var now = opts.now, gateMs = opts.gateMs === undefined ? 50 : opts.gateMs, slopPx = opts.slopPx === undefined ? 3 : opts.slopPx;
    var travel = opts.travelPx || 1;
    var command = opts.command || setVolCommand, toValue = opts.toValue || faderValue, toPos = opts.toPos || faderPos;
    var active = false, target = null, startVol = 0, offset = 0, anchor = null, pos = 0, value = 0, wrote = false;
    var pending = null;    // { target, value }: latest level not yet sent
    var endReq = null;     // { target, value }: the move was released and still needs its e
    var inflight = false, lastSent = -Infinity, timer = null, seq = 0;
    var wheelIdleMs = opts.wheelIdleMs === undefined ? WHEEL_IDLE_MS : opts.wheelIdleMs;
    var wheelOn = false, wheelTimer = null; // a wheel burst: values go out as they come, one `e` after the idle wait

    function wheelEnd() {
      wheelTimer = null;
      if (!wheelOn) return;
      wheelOn = false; seq++;
      if (wrote || pending) endReq = { target: target, value: value };
      pump();
    }
    function fire(cmd) {
      inflight = true; lastSent = now();
      var done = function () { inflight = false; seq++; pump(); };
      var p;
      try { p = opts.send(cmd); } catch (err) { p = Promise.reject(err); }
      p.then(done, done);
    }
    function pump() {
      if (inflight) return;
      if (endReq) {
        var e = endReq, p = pending; endReq = null; pending = null;
        if (!opts.check(e.target)) return;
        var set = command(e.target.track, e.target.y, e.value, false);
        fire((p ? set + ";" : "") + command(e.target.track, e.target.y, e.value, true));
        return;
      }
      if (!pending) return;
      var wait = lastSent + gateMs - now();
      if (wait > 0) {
        if (timer === null) timer = opts.setTimer(function () { timer = null; pump(); }, wait);
        return;
      }
      var w = pending; pending = null;
      if (!opts.check(w.target)) return;
      wrote = true;
      fire(command(w.target.track, w.target.y, w.value, false));
    }

    return {
      // Starts a drag at the thumb (`vol` is the current value, whatever the control sets). Refused while the previous drag's final request has not gone out.
      begin: function (t, vol, travelPx) {
        if (active || endReq || wheelOn) return false;
        if (travelPx) travel = travelPx;
        active = true; target = t; startVol = vol; value = vol; pos = toPos(vol); offset = pos; anchor = null; wrote = false; seq++;
        return true;
      },
      // Returns { pos, value } when the level changed (and queues the write), null when nothing changes.
      move: function (dx) {
        if (!active) return null;
        if (anchor === null) { // inside the slop nothing moves; the drag then continues from the slop's edge
          if (Math.abs(dx) < slopPx) return null;
          anchor = dx > 0 ? slopPx : -slopPx;
        }
        var raw = offset + (dx - anchor) / travel;
        // Past an end the offset follows the finger, so the way back starts at once (no dead zone).
        if (raw > 1) { offset = 1 - (dx - anchor) / travel; raw = 1; }
        else if (raw < 0) { offset = -(dx - anchor) / travel; raw = 0; }
        if (raw === pos) return null;
        pos = raw; value = toValue(pos);
        pending = { target: target, value: value };
        pump();
        return { pos: pos, value: value };
      },
      // A wheel step: writes `v` (already worked out by the caller from the value on screen) through the same gated
      // path as a drag. A burst of steps is one move: each value goes out like a drag's, and the `e` (the one undo
      // entry) goes out once, wheelIdleMs after the last step. The wait counts as busy, so a read cannot move the
      // control between steps. Refused (false) during a drag, while the previous move's `e` is still to go out, for
      // another target mid-burst, or when the stale check fails. If the check fails or cancel() runs during the wait, no `e` goes out.
      nudge: function (t, v) {
        if (active || endReq) return false;
        if (wheelOn && (target.track !== t.track || target.y !== t.y)) return false;
        if (!opts.check(t)) return false;
        if (!wheelOn) { wheelOn = true; target = t; wrote = false; seq++; }
        value = v; pos = toPos(v);
        pending = { target: target, value: v };
        if (wheelTimer !== null) opts.clearTimer(wheelTimer);
        wheelTimer = opts.setTimer(wheelEnd, wheelIdleMs);
        pump();
        return true;
      },
      // Release: the latest value (if not yet sent) and the e in one request, only if a level was written.
      end: function () {
        if (!active) return;
        active = false; seq++;
        if (wrote || pending) endReq = { target: target, value: value };
        pump();
      },
      // The drag ends with no final write: mix closed, offline, row gone.
      cancel: function () {
        active = false; pending = null; endReq = null; wrote = false; wheelOn = false; seq++;
        if (timer !== null) { opts.clearTimer(timer); timer = null; }
        if (wheelTimer !== null) { opts.clearTimer(wheelTimer); wheelTimer = null; }
      },
      active: function () { return active; },
      pos: function () { return pos; },
      busy: function () { return active || wheelOn || inflight || !!pending || !!endReq; },
      // A read may be applied only if it began while this fader was idle and nothing has happened since.
      readToken: function () { return (active || wheelOn || inflight || pending || endReq) ? -1 : seq; },
      canApply: function (token) { return token === seq && !active && !wheelOn && !inflight && !pending && !endReq; }
    };
  }

  return { CAP: CAP, WHEEL_IDLE_MS: WHEEL_IDLE_MS, faderValue: faderValue, faderPos: faderPos, setVolCommand: setVolCommand, setMuteCommand: setMuteCommand,
    createMuteWriter: createMuteWriter, createFaderDrag: createFaderDrag };
});
