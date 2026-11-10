// Arrange: bridge client. One call = write a request, then read the reply that carries its id (pure: fetch, clock and
// timers are injected, so node tests drive it). See apps/arrange/docs/bridge.md.
(function (root, factory) {
  var deps = typeof module === "object" && module.exports ? require("./wire.js") : root.LCRR.arrange.wire;
  var transport = typeof module === "object" && module.exports ? require("../../../../../../shared/www/lcrr/shared/js/bridge-client.js") : root.LCRR.shared.bridgeClient;
  var api = factory(deps, transport);
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.arrange = L.arrange || {}).client = api; }
})(this, function (wire, transport) {
  "use strict";

  // The request itself waits while REAPER's main thread is busy, so an Apply holds it open for as long as it runs
  // (spec: design for 5 to 30 s). Everything else answers in well under a second.
  var APPLY_TIMEOUT_MS = 120000;
  var CALL_TIMEOUT_MS = transport.CALL_TIMEOUT_MS;

  // opts: fetchText(url, timeoutMs) -> Promise<string>; newId(); now(); wait(ms) -> Promise
  function createClient(opts) {
    // Resolves with the bridge's reply object; rejects with an Error carrying `code` (see shared bridge-client.js).
    var call = transport.createTransport({ wire: wire, fetchText: opts.fetchText, newId: opts.newId, now: opts.now,
      wait: opts.wait }).call;

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
