// Podium: pure helpers (no DOM, no network). Works in browsers and in node tests.
// REAPER reply parsing lives in the shared library (LCRR.shared.reaper).
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.podium = L.podium || {}).core = api; }
})(this, function () {
  "use strict";

  // Which button the shared Play/Stop slot shows. Paused shows Play so it can resume.
  function transportSlot(playstate) {
    return !(playstate & 2) && (playstate & 5) ? "stop" : "play";
  }

  function formatTime(seconds) {
    var ms = Math.round(Math.max(0, seconds) * 1000);
    var m = Math.floor(ms / 60000);
    var s = Math.floor((ms % 60000) / 1000);
    var r = ms % 1000;
    return m + ":" + (s < 10 ? "0" : "") + s + "." + ("00" + r).slice(-3);
  }

  // Transport clock: m:ss (whole seconds, floored so it never runs ahead), h:mm:ss from one hour.
  function formatClock(seconds) {
    var total = Math.floor(Math.max(0, seconds) + 1e-9);
    var h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60), sec = total % 60;
    var ss = (sec < 10 ? "0" : "") + sec;
    return h ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss;
  }

  // Region to highlight: only while the transport is active (play/pause/record; stopped = none).
  // start <= position < end. With overlapping regions the latest-starting one wins (the innermost).
  function activeRegionId(regions, position, playstate) {
    if (!playstate) return null;
    var best = null;
    regions.forEach(function (r) {
      if (position >= r.start && position < r.end && (best === null || r.start >= best.start)) best = r;
    });
    return best ? best.id : null;
  }

  return { transportSlot: transportSlot, formatTime: formatTime, formatClock: formatClock, activeRegionId: activeRegionId };
});
