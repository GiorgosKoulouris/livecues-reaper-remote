// Home: connection chip verdict (pure, unit-tested).
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.home = L.home || {}).status = api; }
})(this, function () {
  "use strict";

  // live = this poll got a usable TRANSPORT line; offline = the shared guard's verdict; seen = any live poll so far.
  // One missed poll keeps the previous chip (a dropped packet is not an outage).
  function chip(live, offline, seen) {
    if (live) return { state: "online", text: "REAPER connected" };
    if (offline) return { state: "offline", text: "REAPER unreachable" };
    return seen ? null : { state: "connecting", text: "Connecting…" };
  }

  return { chip: chip };
});
