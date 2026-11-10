// Bridge transport shared by the apps that talk to a Lua bridge: write a request, then read the reply that carries its
// id (pure: fetch, clock and timers are injected, so node tests drive it). An app builds its named methods on `call`.
// See apps/arrange/docs/bridge.md.
(function (root, factory) {
  var poll = typeof module === "object" && module.exports ? require("./poll.js") : root.LCRR.shared.poll;
  var api = factory(poll);
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.shared = L.shared || {}).bridgeClient = api; }
})(this, function (poll) {
  "use strict";

  var CALL_TIMEOUT_MS = 20000;
  var REPLY_WAIT_MS = 8000;   // after the request returned, how long to look for the reply
  var REPLY_POLL_MS = 100;

  function failure(code, message) {
    var e = new Error(message || code);
    e.code = code;
    return e;
  }

  // The page's own `fetchText(url, timeoutMs)` and `newId()` for `createTransport`: a fetch that gives up after the
  // timeout and aborts the request, and ids that differ within a millisecond. `env` (all optional, for tests) replaces
  // the browser's fetch, setTimeout, clearTimeout, AbortController and Date.now. Needs `LCRR.shared.poll` loaded first.
  function createBrowserIo(env) {
    env = env || {};
    var doFetch = env.fetch || function (url, init) { return fetch(url, init); };
    var setTimer = env.setTimeout || function (cb, ms) { return setTimeout(cb, ms); };
    var clearTimer = env.clearTimeout || function (h) { clearTimeout(h); };
    // `env.AbortController: null` says there is none (a test of the browser without one).
    var Abort = "AbortController" in env ? env.AbortController : typeof AbortController === "function" ? AbortController : null;
    var clock = env.now || function () { return Date.now(); };
    var counter = 0;
    return {
      fetchText: function (url, ms) {
        var ctl = Abort ? new Abort() : null;
        var req = doFetch(url, { cache: "no-store", signal: ctl ? ctl.signal : undefined }).then(function (r) {
          if (!r.ok) throw new Error("HTTP " + r.status);
          return r.text();
        });
        return poll.withTimeout(req, ms, setTimer, clearTimer).catch(function (err) { if (ctl) ctl.abort(); throw err; });
      },
      newId: function () { counter++; return clock().toString(36) + "-" + counter; }
    };
  }

  // opts: wire (an app's wire, from bridge-wire's create(section)); fetchText(url, timeoutMs) -> Promise<string>;
  // newId(); now(); wait(ms) -> Promise. Returns { call }.
  function createTransport(opts) {
    var wire = opts.wire;
    var fetchText = opts.fetchText;
    var newId = opts.newId;
    var now = opts.now || function () { return Date.now(); };
    var wait = opts.wait || function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };

    // Resolves with the bridge's reply object; rejects with an Error carrying `code`:
    //   request_too_long (never sent), unreachable (REAPER did not take the request), no_reply (it did, the bridge did not answer).
    function call(cmd, fields, callOpts) {
      callOpts = callOpts || {};
      var id = newId();
      var all = { cmd: cmd };
      Object.keys(fields || {}).forEach(function (k) { all[k] = fields[k]; });
      var command = wire.setRequestCommand(wire.buildRequest(id, all));
      if (wire.tooLong(command)) return Promise.reject(failure("request_too_long", "The request is too long to send."));

      function again(deadline) {
        if (now() >= deadline) throw failure("no_reply", "The bridge did not answer.");
        return wait(REPLY_POLL_MS).then(function () { return readReply(deadline); });
      }
      function readReply(deadline) {
        return fetchText("/_/" + wire.getCommand("res"), 3000).then(function (text) {
          var got = wire.parseResult(wire.parseExtState(text, "res"));
          if (got && got.id === id) return got.reply;
          return again(deadline);
        }, function () { return again(deadline); });
      }

      return fetchText("/_/" + command, callOpts.timeoutMs || CALL_TIMEOUT_MS).then(function () {
        return readReply(now() + REPLY_WAIT_MS);
      }, function () {
        throw failure("unreachable", "REAPER did not take the request.");
      });
    }

    return { call: call };
  }

  return { createTransport: createTransport, createBrowserIo: createBrowserIo, CALL_TIMEOUT_MS: CALL_TIMEOUT_MS };
});
