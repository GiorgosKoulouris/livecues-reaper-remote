// IEM Mix: the client of IEM Setup's bridge, for snapshots only. IEM Mix has no bridge of its own: it speaks to
// `LCRR_IEM` (IEM Setup's ExtState section) through the shared wire and transport. Pure: fetch, clock and timers are
// injected, so node tests drive it. The commands are documented in apps/iem/CONTEXT.md.
(function (root, factory) {
  var node = typeof module === "object" && module.exports;
  var wireLib = node ? require("../../../../../../shared/www/lcrr/shared/js/bridge-wire.js") : root.LCRR.shared.bridgeWire;
  var clientLib = node ? require("../../../../../../shared/www/lcrr/shared/js/bridge-client.js") : root.LCRR.shared.bridgeClient;
  var api = factory(wireLib, clientLib);
  if (node) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.iemmix = L.iemmix || {}).bridge = api; }
})(this, function (bridgeWire, bridgeClient) {
  "use strict";

  var SECTION = "LCRR_IEM";
  var wire = bridgeWire.create(SECTION);

  // The request a command would send, for the length check (`fits`) the page makes before it sends.
  function requestCommand(cmd, fields) {
    var all = { cmd: cmd };
    Object.keys(fields).forEach(function (k) { all[k] = fields[k]; });
    return wire.setRequestCommand(wire.buildRequest("xxxxxxxxxxxx-xxxx", all));
  }

  // Would a save or delete under this name stay under the URL limit? (A name of wide characters can be long once encoded.)
  // (A one-mix recall adds a GUID to the name; a name of the widest characters can still be too long for that one, and
  // the transport refuses it as `request_too_long` before sending.)
  function nameFits(name) {
    return !wire.tooLong(requestCommand("snapshot_save", { name: name, overwrite: "1" }));
  }

  // opts: fetchText(url, timeoutMs) -> Promise<string>; newId(); now(); wait(ms) -> Promise.
  function createClient(opts) {
    var call = bridgeClient.createTransport({ wire: wire, fetchText: opts.fetchText, newId: opts.newId, now: opts.now,
      wait: opts.wait }).call;
    return {
      call: call,
      // The saved snapshots: { snapshots: [ { name, saved, mixes, sends } ] }.
      snapshots: function () { return call("snapshots", {}); },
      // Save under a name; `overwrite` replaces the snapshot of that name. Only the name travels: the bridge reads the
      // levels, pans and mutes itself.
      save: function (name, overwrite) {
        return call("snapshot_save", overwrite ? { name: name, overwrite: "1" } : { name: name });
      },
      remove: function (name) { return call("snapshot_delete", { name: name }); },
      // Recall a snapshot: the whole band, or one mix by GUID. One undo step in REAPER.
      recall: function (name, mixGuid) {
        return call("snapshot_recall", mixGuid ? { name: name, mix: mixGuid } : { name: name });
      },
      // The project's mixes with their GUIDs (the web API does not expose them), to find one mix's GUID by its name.
      state: function () { return call("state", {}); }
    };
  }

  return { SECTION: SECTION, wire: wire, createClient: createClient, nameFits: nameFits };
});
