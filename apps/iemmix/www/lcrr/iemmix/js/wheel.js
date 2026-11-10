// IEM Mix: the mouse wheel's step on a panel fader or grid cell (pure, no DOM). Works in browsers and in node tests.
// decide() says whether the wheel acts on a fader at all and, if so, the level to write. The page prevents
// scrolling exactly when `act` is true and sends `value` through the fader's normal write path when it is not null.
(function (root, factory) {
  var api = factory(root.LCRR && root.LCRR.shared && root.LCRR.shared.faderCore || (typeof require === "function" ? require("../../../../../../shared/www/lcrr/shared/js/fader-core.js") : null));
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.iemmix = L.iemmix || {}).wheel = api; }
})(this, function (faderCore) {
  "use strict";

  var STEP_DB = 0.5;
  // The lowest audible step. The fader's law (value = pos^4 * CAP) is so steep that levels below about -60 dB sit in
  // the first fifth of the travel and are inaudible in practice, so from silence an upward step lands on -60 dB and
  // a downward step from the 0.5 dB grid below -60 dB goes to silence (0) instead of stepping on forever.
  var MIN_DB = -60;
  var MIN_VALUE = Math.pow(10, MIN_DB / 20);

  var NOTCH_PX = 100, LINES_PER_NOTCH = 3; // a page (deltaMode 2) is one notch

  function toDb(v) { return 20 * Math.log10(v); }
  function fromDb(d) { return Math.pow(10, d / 20); }

  function notches(deltaY, deltaMode) {
    if (deltaMode === 1) return deltaY / LINES_PER_NOTCH;
    if (deltaMode === 2) return deltaY;
    return deltaY / NOTCH_PX;
  }

  // One 0.5 dB step from `vol`: the next level, or null when this step writes nothing.
  function step(vol, up) {
    if (up) {
      if (vol >= faderCore.CAP) return null; // at or above the cap: left alone
      if (vol < MIN_VALUE) return MIN_VALUE; // silence or below the lowest step
      var next = fromDb(toDb(vol) + STEP_DB);
      return next >= faderCore.CAP ? faderCore.CAP : next;
    }
    if (!(vol > 0)) return null;
    var d = toDb(vol) - STEP_DB;
    return d < MIN_DB ? 0 : fromDb(d);
  }
  // `count` steps, or null if the first one writes nothing.
  function steps(vol, up, count) {
    var v = vol, moved = false;
    for (var i = 0; i < count; i++) {
      var next = step(v, up);
      if (next === null) break;
      v = next; moved = true;
    }
    return moved ? v : null;
  }

  // in: { locked, deltaY and deltaMode (the wheel event's; negative deltaY is wheel up = louder), vol (linear level on
  // screen, null if unknown), now (ms), state (what the last call returned, kept per fader) }.
  // out: { act, value, state }. act false: the wheel does nothing and the page scrolls as normal (locked, no vertical
  // movement, unknown level). act true: the wheel is on a fader, so the page must not scroll; value is the linear level
  // to write, or null when this event writes nothing (still gathering, up from above the cap, down from silence).
  // 100 px is one notch. An event of a notch or more gives one step per whole notch and drops its remainder (some wheels
  // send 120 a notch). Smaller events (a trackpad) gather until they make a notch; a change of direction or the wheel's
  // idle wait clears what was gathered.
  function decide(o) {
    var none = { act: false, value: null };
    if (!o || o.locked || typeof o.deltaY !== "number" || isNaN(o.deltaY)) return none;
    if (o.deltaY === 0) return { act: false, value: null, state: o.state };
    if (typeof o.vol !== "number" || isNaN(o.vol)) return none;
    var n = notches(o.deltaY, o.deltaMode), up = n < 0, now = o.now || 0, whole, carry = 0;
    if (Math.abs(n) >= 1) {
      whole = Math.floor(Math.abs(n));
    } else {
      var s = o.state, live = s && now - s.at < faderCore.WHEEL_IDLE_MS && (s.carry < 0) === up;
      carry = (live ? s.carry : 0) + n;
      whole = Math.floor(Math.abs(carry));
      carry -= up ? -whole : whole;
    }
    return { act: true, value: whole ? steps(o.vol, up, whole) : null, state: { carry: carry, at: now } };
  }

  // Keeps one wheel gesture on one thing, until the wheel has been idle for WHEEL_IDLE_MS. route(now, target) takes what
  // is under the pointer (null: nothing editable) and returns what this event acts on: the control the gesture began on,
  // wherever the pointer has gone since, or null while the gesture is a scroll, so rows sliding under the pointer are
  // never edited. scrolled(now) turns the gesture into a scroll (an event that could not act after all).
  function createWheelLatch() {
    var at = null, held = null;
    return {
      route: function (now, target) {
        if (at === null || now - at >= faderCore.WHEEL_IDLE_MS) held = target || null;
        at = now;
        return held;
      },
      scrolled: function (now) { at = now; held = null; }
    };
  }

  return { STEP_DB: STEP_DB, MIN_DB: MIN_DB, MIN_VALUE: MIN_VALUE, decide: decide, createWheelLatch: createWheelLatch };
});
