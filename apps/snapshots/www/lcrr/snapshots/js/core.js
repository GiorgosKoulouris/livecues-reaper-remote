// Snapshots: page logic (pure, no DOM). The bridge's replies come in, plain facts go out.
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.snapshots = L.snapshots || {}).core = api; }
})(this, function () {
  "use strict";

  // Is the bridge reachable? `offline` is the connection guard's verdict, `everLive` whether any poll has worked,
  // `beat` the heartbeat state ("unknown" | "running" | "stopped").
  function connectionPhase(offline, everLive, beat) {
    if (offline) return "offline";
    if (!everLive) return "connecting";
    if (beat === "stopped") return "bridge-down";
    if (beat === "unknown") return "connecting";
    return "ready";
  }

  // The `state` reply, or null when it is not one a page can draw (a refusal, or a shape from another version).
  function readState(reply) {
    if (!reply || reply.status !== "ok" || reply.command !== "state") return null;
    var p = reply.project;
    if (!p || typeof p.name !== "string" || typeof p.path !== "string") return null;
    return reply;
  }

  // Controls exist only while the bridge is running.
  function canUse(phase) { return phase === "ready"; }

  return { connectionPhase: connectionPhase, readState: readState, canUse: canUse };
});
