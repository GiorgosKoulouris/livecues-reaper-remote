// Arrange: the bridge's wire format (pure: no DOM, no network). Works in browsers and in node tests.
// The other end is lib/bridge/ in the Lua slice; the contract is apps/arrange/docs/bridge.md.
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.arrange = L.arrange || {}).wire = api; }
})(this, function () {
  "use strict";

  var SECTION = "LCRR_ARRANGE";
  // REAPER silently cuts a request URL at about 1026 characters (spike, run 2); stay well under it.
  var MAX_URL = 900;

  // id|length|key=value&key=value, each value percent-encoded so any Region Name survives. The declared length is how
  // the bridge notices a request that REAPER cut short.
  function buildRequest(id, fields) {
    var body = Object.keys(fields).filter(function (k) { return fields[k] !== undefined && fields[k] !== null; })
      .map(function (k) { return k + "=" + encodeURIComponent(String(fields[k])); }).join("&");
    return id + "|" + body.length + "|" + body;
  }

  // The command that writes a raw request to ExtState. Without the leading "/_/".
  function setRequestCommand(raw) {
    return "SET/EXTSTATE/" + SECTION + "/req/" + encodeURIComponent(raw);
  }

  function getCommand(key) { return "GET/EXTSTATE/" + SECTION + "/" + key; }

  // Would the request URL (with "/_/") be cut?
  function tooLong(command) { return ("/_/" + command).length > MAX_URL; }

  // REAPER escapes \t, \n and \\ inside an ExtState value it replies with.
  function unescapeValue(s) {
    return String(s).replace(/\\(t|n|\\)/g, function (_, c) { return c === "t" ? "\t" : c === "n" ? "\n" : "\\"; });
  }

  // EXTSTATE\t<section>\t<key>\t<value>, anywhere in a combined reply. null when the line is absent. A key that was
  // never set comes back as "" (it cannot be told from an empty value).
  function parseExtState(text, key) {
    var prefix = "EXTSTATE\t" + SECTION + "\t" + key + "\t";
    var lines = String(text).split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].indexOf(prefix) === 0) return unescapeValue(lines[i].slice(prefix.length));
      if (lines[i] === prefix.slice(0, -1)) return "";
    }
    return null;
  }

  // "<id>|<json>" -> { id, reply }, or null when it is not that (an empty value, a half-written one).
  function parseResult(value) {
    if (!value) return null;
    var cut = value.indexOf("|");
    if (cut < 1) return null;
    try { return { id: value.slice(0, cut), reply: JSON.parse(value.slice(cut + 1)) }; }
    catch (e) { return null; }
  }

  // Is the bridge running? Only a heartbeat that keeps changing says so. `touch()` restarts the clock: used when a
  // long action ends, because nothing could beat while REAPER was busy.
  function createHeartbeat(opts) {
    opts = opts || {};
    var staleMs = opts.staleMs || 2500;
    var now = opts.now || function () { return Date.now(); };
    var seen = false, last = "", changedAt = 0;
    return {
      update: function (value) {
        if (value === null || value === undefined) return;
        if (!seen || value !== last) changedAt = now();
        seen = true; last = value;
      },
      touch: function () { changedAt = now(); },
      // "unknown" until a reply has carried the key; "stopped" for an empty or unchanging heartbeat.
      state: function () {
        if (!seen) return "unknown";
        if (last === "") return "stopped";
        return now() - changedAt <= staleMs ? "running" : "stopped";
      }
    };
  }

  return { SECTION: SECTION, MAX_URL: MAX_URL, buildRequest: buildRequest, setRequestCommand: setRequestCommand,
    getCommand: getCommand, tooLong: tooLong, unescapeValue: unescapeValue, parseExtState: parseExtState,
    parseResult: parseResult, createHeartbeat: createHeartbeat };
});
