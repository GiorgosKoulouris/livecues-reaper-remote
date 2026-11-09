// LCRR shared: press-and-hold helper (accidental-press protection).
// start() begins the hold; completing the full duration calls onComplete once.
// cancel() (release/leave/blur) aborts an unfinished hold; it is a no-op after completion.
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.shared = L.shared || {}).hold = api; }
})(this, function () {
  "use strict";

  function createHold(opts) {
    var holdMs = opts.holdMs || 800;
    var setTimer = opts.setTimer || function (cb, ms) { return setTimeout(cb, ms); };
    var clearTimer = opts.clearTimer || function (h) { clearTimeout(h); };
    var handle = null;
    var holding = false; // true from start() until cancel(), even after completion

    return {
      start: function () {
        if (holding) return; // ignore key auto-repeat / duplicate events
        holding = true;
        if (opts.onStart) opts.onStart();
        handle = setTimer(function () {
          handle = null;
          opts.onComplete();
        }, holdMs);
      },
      cancel: function () {
        if (!holding) return;
        holding = false;
        if (handle !== null) {
          clearTimer(handle);
          handle = null;
          if (opts.onCancel) opts.onCancel();
        }
      }
    };
  }

  return { createHold: createHold };
});
