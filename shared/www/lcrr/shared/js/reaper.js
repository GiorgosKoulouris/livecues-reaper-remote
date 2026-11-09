// LCRR shared: REAPER web API protocol (pure: no DOM, no network). Works in browsers and in node tests.
// Reply formats are verified on real REAPER; see the root CONTEXT.md.
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.shared = L.shared || {}).reaper = api; }
})(this, function () {
  "use strict";

  // TRANSPORT\t<playstate>\t<position_s>\t...
  function parseTransport(text) {
    var lines = String(text).split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].indexOf("TRANSPORT\t") !== 0) continue;
      var f = lines[i].split("\t");
      var playstate = parseInt(f[1], 10);
      var position = parseFloat(f[2]);
      if (isNaN(playstate) || isNaN(position)) return null;
      return { playstate: playstate, position: position };
    }
    return null;
  }

  // playstate bitfield: 1 play, 2 pause, 4 record.
  function stateName(playstate) {
    if (playstate & 2) return "paused";
    if (playstate & 4) return "recording";
    if (playstate & 1) return "playing";
    return "stopped";
  }

  // Lines between REGION_LIST and REGION_LIST_END: REGION\t<name>\t<id>\t<start>\t<end>\t<color>.
  // Sorted by start (REAPER does not guarantee order).
  function hasRegionList(text) { return /(^|\n)REGION_LIST\r?(\n|$)/.test(String(text)); }

  function parseRegions(text) {
    var out = [], inList = false;
    String(text).split(/\r?\n/).forEach(function (line) {
      if (line === "REGION_LIST") { inList = true; return; }
      if (line === "REGION_LIST_END") { inList = false; return; }
      if (!inList || line.indexOf("REGION\t") !== 0) return;
      var f = line.split("\t");
      var id = parseInt(f[2], 10), start = parseFloat(f[3]), end = parseFloat(f[4]);
      if (isNaN(id) || isNaN(start) || isNaN(end)) return;
      out.push({ name: f[1], id: id, start: start, end: end, color: parseInt(f[5], 10) || 0 });
    });
    return out.sort(function (a, b) { return a.start - b.start; });
  }

  // Lines between MARKER_LIST and MARKER_LIST_END: MARKER\t<name>\t<id>\t<position>\t<color>.
  // Region markers are not in this block.
  function hasMarkerList(text) { return /(^|\n)MARKER_LIST\r?(\n|$)/.test(String(text)); }

  function parseMarkers(text) {
    var out = [], inList = false;
    String(text).split(/\r?\n/).forEach(function (line) {
      if (line === "MARKER_LIST") { inList = true; return; }
      if (line === "MARKER_LIST_END") { inList = false; return; }
      if (!inList || line.indexOf("MARKER\t") !== 0) return;
      var f = line.split("\t");
      var id = parseInt(f[2], 10), position = parseFloat(f[3]);
      if (isNaN(id) || isNaN(position)) return;
      out.push({ name: f[1], id: id, position: position, color: parseInt(f[4], 10) || 0 });
    });
    return out.sort(function (a, b) { return a.position - b.position; });
  }

  // Color as sent by REAPER's web interface: flag 0x1000000, low 24 bits RGB (blue in the low byte,
  // verified: 0x10000FF is blue in REAPER's ruler). 0 = no color.
  function colorToCss(c) {
    if (!c || !(c & 0x1000000)) return null;
    return "rgb(" + ((c >> 16) & 255) + "," + ((c >> 8) & 255) + "," + (c & 255) + ")";
  }

  function seekPlayCommand(seconds) { return "SET/POS/" + seconds + ";1007"; }

  return { parseTransport: parseTransport, stateName: stateName, hasRegionList: hasRegionList, parseRegions: parseRegions,
    hasMarkerList: hasMarkerList, parseMarkers: parseMarkers, colorToCss: colorToCss, seekPlayCommand: seekPlayCommand };
});
