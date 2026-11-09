// LCRR shared: poller. One request per tick, shared by every feature:
// features add their REAPER commands with addCommand() and parse the combined response.
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.shared = L.shared || {}).poll = api; }
})(this, function () {
  "use strict";

  // Reject if the promise has not settled after ms (a paused/hung server would otherwise block polling forever).
  function withTimeout(promise, ms, setTimer, clearTimer) {
    return new Promise(function (resolve, reject) {
      var h = setTimer(function () { h = null; reject(new Error("timeout")); }, ms);
      var done = function (fn) { return function (v) { if (h !== null) clearTimer(h); fn(v); }; };
      promise.then(done(resolve), done(reject));
    });
  }

  var REQUEST_TIMEOUT_MS = 3000;

  function defaultFetchText(url) {
    var ctl = typeof AbortController === "function" ? new AbortController() : null;
    var req = fetch(url, { cache: "no-store", signal: ctl ? ctl.signal : undefined }).then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.text();
    });
    return withTimeout(req, REQUEST_TIMEOUT_MS,
      function (cb, ms) { return setTimeout(cb, ms); }, function (h) { clearTimeout(h); })
      .catch(function (err) { if (ctl) ctl.abort(); throw err; });
  }

  function createPoller(opts) {
    opts = opts || {};
    var fetchText = opts.fetchText || defaultFetchText;
    var intervalMs = opts.intervalMs || 500;
    var setTimer = opts.setTimer || function (cb, ms) { return setTimeout(cb, ms); };
    var clearTimer = opts.clearTimer || function (h) { clearTimeout(h); };
    var commands = ["TRANSPORT"];
    var listeners = [];
    var handle = null, running = false, inFlight = false;

    // One broken listener must not stop the others or the next poll: report it and carry on.
    function emit(e) {
      listeners.slice().forEach(function (fn) {
        try { fn(e); } catch (err) { if (typeof console !== "undefined") console.error("lcrr listener failed", err); }
      });
    }

    function schedule() {
      if (!running) return;
      handle = setTimer(poll, intervalMs);
    }

    function poll() {
      if (inFlight) return;
      if (handle !== null) { clearTimer(handle); handle = null; }
      inFlight = true;
      var done = function (e) { inFlight = false; emit(e); schedule(); };
      var p;
      try { p = fetchText("/_/" + commands.join(";")); } catch (err) { p = Promise.reject(err); }
      p.then(function (text) { done({ ok: true, text: text }); },
             function (err) { done({ ok: false, error: err }); });
    }

    return {
      start: function () { if (running) return; running = true; poll(); },
      stop: function () { running = false; if (handle !== null) { clearTimer(handle); handle = null; } },
      pollNow: poll,
      addCommand: function (c) { if (commands.indexOf(c) < 0) commands.push(c); },
      subscribe: function (fn) {
        listeners.push(fn);
        return function () { listeners = listeners.filter(function (l) { return l !== fn; }); };
      }
    };
  }

  // Fire-and-forget REAPER action/command, e.g. send("1007") or send("SET/POS/12.5;1007").
  function send(command, fetchText) {
    return (fetchText || defaultFetchText)("/_/" + command);
  }

  return { createPoller: createPoller, send: send, withTimeout: withTimeout };
});
