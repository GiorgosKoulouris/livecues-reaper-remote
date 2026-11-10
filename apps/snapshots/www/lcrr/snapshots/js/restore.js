// Snapshots: the restore's ticks and reply (pure, no DOM). The bridge takes the ticks as one compact field.
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.snapshots = L.snapshots || {}).restore = api; }
})(this, function () {
  "use strict";

  // The ticks the page offers, in display order, each with the letter the bridge knows it by and its default.
  var TICKS = [
    { key: "levels", letter: "L", on: true },
    { key: "pans", letter: "P", on: true },
    { key: "mutes", letter: "M", on: true },
    { key: "solos", letter: "S", on: true },
    { key: "polarity", letter: "R", on: true },
    { key: "sends", letter: "E", on: true },
    { key: "fx", letter: "F", on: false }
  ];

  // A fresh set of ticks at their defaults: { levels: true, ..., fx: false }.
  function defaults() {
    var out = {};
    TICKS.forEach(function (t) { out[t.key] = t.on; });
    return out;
  }

  // The bridge's `ticks` field for a set of ticks ("" when none is on).
  function field(ticks) {
    return TICKS.filter(function (t) { return ticks && ticks[t.key]; }).map(function (t) { return t.letter; }).join("");
  }

  // The `snapshot_restore` reply as plain counts, or null when it is not one a page can draw.
  function readResult(reply) {
    if (!reply || reply.status !== "ok" || reply.command !== "snapshot_restore") return null;
    if (typeof reply.tracks !== "number" || typeof reply.sends !== "number" || typeof reply.skipped !== "number") return null;
    return { name: String(reply.name), tracks: reply.tracks, sends: reply.sends, skipped: reply.skipped };
  }

  return { TICKS: TICKS, defaults: defaults, field: field, readResult: readResult };
});
