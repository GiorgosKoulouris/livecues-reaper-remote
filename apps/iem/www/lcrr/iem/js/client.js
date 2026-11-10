// IEM Setup: bridge client. One call = write a request, then read the reply that carries its id (pure: fetch, clock
// and timers are injected, so node tests drive it). Same exchange as Arrange's (apps/arrange/docs/bridge.md).
(function (root, factory) {
  var deps = typeof module === "object" && module.exports ? require("./wire.js") : root.LCRR.iem.wire;
  var transport = typeof module === "object" && module.exports ? require("../../../../../../shared/www/lcrr/shared/js/bridge-client.js") : root.LCRR.shared.bridgeClient;
  var api = factory(deps, transport);
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.iem = L.iem || {}).client = api; }
})(this, function (wire, transport) {
  "use strict";

  var CALL_TIMEOUT_MS = transport.CALL_TIMEOUT_MS;

  // opts: fetchText(url, timeoutMs) -> Promise<string>; newId(); now(); wait(ms) -> Promise
  function createClient(opts) {
    // Resolves with the bridge's reply object; rejects with an Error carrying `code` (see shared bridge-client.js).
    var call = transport.createTransport({ wire: wire, fetchText: opts.fetchText, newId: opts.newId, now: opts.now,
      wait: opts.wait }).call;

    // The project's mixes, sources, folder and colour.
    function state() { return call("state", {}); }

    // Writes. Each names its targets by GUID and is one undo step in REAPER; the reply is `ok` or `refused` + a code.
    // One method per write command.
    // `copyFrom` (optional): the GUID of a mix whose sends the new mix starts with.
    function create(name, copyFrom) {
      return call("create", copyFrom ? { name: name, copy: copyFrom } : { name: name });
    }
    function rename(guid, name) { return call("rename", { guid: guid, name: name }); }
    function colour(hex) { return call("colour", { colour: hex }); }   // "rrggbb"
    function moveToEnd(guid) { return call("move_to_end", { guid: guid }); }
    function adopt(guid) { return call("adopt", { guid: guid }); }
    // The cue track IEM Mix listens through, and a send to it from every mix (adds only what is missing). No fields.
    function createCue() { return call("cue", {}); }
    function deleteMix(guid) { return call("delete", { guid: guid }); }
    // The wire form of a boolean: "1" or "0".
    function flag(on) { return on ? "1" : "0"; }

    // `guid` is a mix's or the cue track's. `choice` is core.parseOutputChoice's result: { none: true } clears, { channel, mono } sets or replaces.
    function setOutput(guid, choice) {
      return call("output", choice.none ? { guid: guid, channel: "none" }
        : { guid: guid, channel: String(choice.channel), mono: flag(choice.mono) });
    }

    // A matrix cell: `on` true creates the send, false deletes every send from the source to the mix.
    function cell(source, mix, on) { return call("cell", { source: source, mix: mix, on: flag(on) }); }

    // A whole row (one source, every mix) or column (one mix, every source): only the ID travels, the bridge works out
    // the rest. On adds the missing sends; off removes every send of each pair.
    function row(source, on) { return call("row", { source: source, on: flag(on) }); }
    function column(mix, on) { return call("column", { mix: mix, on: flag(on) }); }

    return { call: call, cell: cell, row: row, column: column, state: state, create: create, rename: rename, colour: colour, moveToEnd: moveToEnd,
      deleteMix: deleteMix, adopt: adopt, createCue: createCue, setOutput: setOutput };
  }

  return { createClient: createClient, CALL_TIMEOUT_MS: CALL_TIMEOUT_MS };
});
