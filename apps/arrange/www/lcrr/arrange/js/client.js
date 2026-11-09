// Arrange: bridge client. One call = write a request, then read the reply that carries its id (pure: fetch, clock and
// timers are injected, so node tests drive it). See apps/arrange/docs/bridge.md.
(function (root, factory) {
  var deps = typeof module === "object" && module.exports ? require("./wire.js") : root.LCRR.arrange.wire;
  var api = factory(deps);
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.arrange = L.arrange || {}).client = api; }
})(this, function (wire) {
  "use strict";

  // The request itself waits while REAPER's main thread is busy, so an Apply holds it open for as long as it runs
  // (spec: design for 5 to 30 s). Everything else answers in well under a second.
  var APPLY_TIMEOUT_MS = 120000;
  var CALL_TIMEOUT_MS = 20000;
  var REPLY_WAIT_MS = 8000;   // after the request returned, how long to look for the reply
  var REPLY_POLL_MS = 100;

  function failure(code, message) {
    var e = new Error(message || code);
    e.code = code;
    return e;
  }

  // opts: fetchText(url, timeoutMs) -> Promise<string>; newId(); now(); wait(ms) -> Promise
  function createClient(opts) {
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

      function readReply(deadline) {
        return fetchText("/_/" + wire.getCommand("res"), 3000).then(function (text) {
          var got = wire.parseResult(wire.parseExtState(text, "res"));
          if (got && got.id === id) return got.reply;
          if (now() >= deadline) throw failure("no_reply", "The bridge did not answer.");
          return wait(REPLY_POLL_MS).then(function () { return readReply(deadline); });
        }, function (err) {
          if (now() >= deadline) throw failure("no_reply", "The bridge did not answer.");
          return wait(REPLY_POLL_MS).then(function () { return readReply(deadline); });
        });
      }

      return fetchText("/_/" + command, callOpts.timeoutMs || CALL_TIMEOUT_MS).then(function () {
        return readReply(now() + REPLY_WAIT_MS);
      }, function () {
        throw failure("unreachable", "REAPER did not take the request.");
      });
    }

    // The editor's two commands over `call`.
    //   arrangements()  the sidecar's state, revision, Arrangements and the project's regions
    //   edit(base, operation, fields)  one operation. `base` is what the page last read:
    //     { project: the project path, revision, rewrite: true once the rewrite question was answered Yes }.
    //     `fields` are the operation's own (arrangement, region, slot, headroom, name; docs/bridge.md).
    //   Both reject with request_too_long, without sending, when the URL would be cut.
    function arrangements() { return call("arrangements", {}); }

    function edit(base, operation, fields) {
      var all = { operation: operation, project: base.project, revision: base.revision };
      if (base.rewrite) all.rewrite = "1";
      Object.keys(fields || {}).forEach(function (k) { all[k] = fields[k]; });
      return call("edit", all);
    }

    return { call: call, arrangements: arrangements, edit: edit };
  }

  return { createClient: createClient, APPLY_TIMEOUT_MS: APPLY_TIMEOUT_MS, CALL_TIMEOUT_MS: CALL_TIMEOUT_MS };
});
