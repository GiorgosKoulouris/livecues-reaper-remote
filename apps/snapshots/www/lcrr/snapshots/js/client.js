// Snapshots: bridge client. One call = write a request, then read the reply that carries its id (pure: fetch, clock
// and timers are injected, so node tests drive it). Same exchange as IEM Setup's (apps/arrange/docs/bridge.md).
(function (root, factory) {
  var deps = typeof module === "object" && module.exports ? require("./wire.js") : root.LCRR.snapshots.wire;
  var transport = typeof module === "object" && module.exports ? require("../../../../../../shared/www/lcrr/shared/js/bridge-client.js") : root.LCRR.shared.bridgeClient;
  var api = factory(deps, transport);
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.snapshots = L.snapshots || {}).client = api; }
})(this, function (wire, transport) {
  "use strict";

  var CALL_TIMEOUT_MS = transport.CALL_TIMEOUT_MS;

  // opts: fetchText(url, timeoutMs) -> Promise<string>; newId(); now(); wait(ms) -> Promise
  function createClient(opts) {
    // Resolves with the bridge's reply object; rejects with an Error carrying `code` (see shared bridge-client.js).
    var call = transport.createTransport({ wire: wire, fetchText: opts.fetchText, newId: opts.newId, now: opts.now,
      wait: opts.wait }).call;

    // The active project's name and path.
    function state() { return call("state", {}); }

    return { call: call, state: state };
  }

  return { createClient: createClient, CALL_TIMEOUT_MS: CALL_TIMEOUT_MS };
});
