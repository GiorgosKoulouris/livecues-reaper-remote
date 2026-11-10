// Snapshots: the bridge's wire format, bound to this app's ExtState section. The format itself is shared
// (shared/www/lcrr/shared/js/bridge-wire.js); the contract is apps/arrange/docs/bridge.md.
(function (root, factory) {
  var deps = typeof module === "object" && module.exports ? require("../../../../../../shared/www/lcrr/shared/js/bridge-wire.js") : root.LCRR.shared.bridgeWire;
  var api = factory(deps);
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.snapshots = L.snapshots || {}).wire = api; }
})(this, function (bridgeWire) {
  "use strict";
  return bridgeWire.create("LCRR_SNAPSHOTS");
});
