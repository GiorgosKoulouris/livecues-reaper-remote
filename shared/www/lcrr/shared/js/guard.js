// LCRR shared: connection and repeat-tap guards (pure, clock injectable, unit-tested).
//  createConnection: debounces flaky polls into one stable online/offline verdict.
//    - offline only after `failuresToOffline` consecutive failed polls (one dropped packet is not an outage);
//    - after coming back from offline, actions stay locked for `settleMs` so the rows can't be hit while the layout is catching up.
//  createCooldown: ignores repeat triggers for `ms` after one fires (double-tap protection).
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.shared = L.shared || {}).guard = api; }
})(this, function () {
  "use strict";

  function createConnection(opts) {
    opts = opts || {};
    var failuresToOffline = opts.failuresToOffline || 2;
    var settleMs = opts.settleMs === undefined ? 1500 : opts.settleMs;
    var now = opts.now || function () { return Date.now(); };
    var failures = 0, offline = false, settleUntil = 0;

    return {
      // ok = this poll returned a usable TRANSPORT line.
      update: function (ok) {
        if (ok) {
          if (offline) settleUntil = now() + settleMs;
          offline = false; failures = 0;
        } else {
          failures++;
          if (failures >= failuresToOffline) offline = true;
        }
      },
      isOffline: function () { return offline; },
      // True when this poll succeeded and we are not still settling after a reconnect.
      canCue: function () { return !offline && failures === 0 && now() >= settleUntil; }
    };
  }

  function createCooldown(ms, now) {
    now = now || function () { return Date.now(); };
    var until = 0;
    return {
      // Returns true (and starts the cooldown) if the trigger is allowed, false if it falls inside the cooldown.
      tryFire: function () {
        var t = now();
        if (t < until) return false;
        until = t + ms;
        return true;
      },
      active: function () { return now() < until; }
    };
  }

  return { createConnection: createConnection, createCooldown: createCooldown };
});
