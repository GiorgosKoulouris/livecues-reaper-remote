// IEM Setup: pure page logic (no DOM, no network). Works in browsers and in node tests.
// Input is the bridge's `state` reply (shape in apps/iem/CONTEXT.md; recorded in test/fixtures/).
// Output is plain data; every sentence is in words.js. Write-side logic (the lock gate, name checks, the folder
// offer) is here too; later issues add cell toggles and bulk operations as further pure functions.
(function (root, factory) {
  var api = factory(root.LCRR && root.LCRR.shared && root.LCRR.shared.reaper || (typeof require === "function" ? require("../../../../../../shared/www/lcrr/shared/js/reaper.js") : null));
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.iem = L.iem || {}).core = api; }
})(this, function (reaper) {
  "use strict";

  var dbText = reaper.dbText; // shared; still exported from here

  // I_SENDMODE of the send IEM Setup creates: post-FX, pre-fader. Anything else gets the "non-standard" mark.
  var STANDARD_MODE = 3;

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
    if (!Array.isArray(reply.mixes) || !Array.isArray(reply.sources)) return null;
    return reply;
  }

  // One column header per mix, in project order. `duplicate`: another mix has the same name (Monitor cannot open
  // either). `output` is the first output (Monitor's master fader drives only that one); `extraOutputs` counts the rest.
  function mixHeaders(state) {
    var clashes = outputClashes(state);
    var count = {};
    state.mixes.forEach(function (m) { count[m.name] = (count[m.name] || 0) + 1; });
    return state.mixes.map(function (m) {
      return {
        guid: m.guid,
        name: m.name,
        stray: !m.in_folder,
        duplicate: count[m.name] > 1,
        noOutput: m.outputs.length === 0,
        output: m.outputs.length ? { channel: m.outputs[0].channel, mono: m.outputs[0].mono } : null,
        extraOutputs: Math.max(m.outputs.length - 1, 0),
        readOnlyOutput: m.outputs.length > 1,
        clashes: clashes[m.guid] || [],
        masterSend: m.master_send
      };
    });
  }

  // ---- hardware outputs ----------------------------------------------------------------------------------------------
  // The device channels an output occupies (0-based): a mono output one, a stereo output its channel and the next.
  function outputChannels(output) {
    return output.mono ? [output.channel] : [output.channel, output.channel + 1];
  }

  // Which mixes share a device channel with another mix or with the master? Sharing is allowed, only flagged. A stereo
  // output covers two channels, so a stereo pair at 2 clashes with a mono output on 3 as well as with another pair at 2
  // or 1 (overlap, not equal start channels). Every output counts, including those of a mix with several (read-only)
  // and the master track's own hardware outputs. Returns { mixGuid: [ { "with": "mix", guid, name } | { "with": "master" } ] }
  // for the mixes that clash, each partner listed once.
  function outputClashes(state) {
    var masterChannels = {};
    (state.master_outputs || []).forEach(function (o) { outputChannels(o).forEach(function (c) { masterChannels[c] = true; }); });
    var used = state.mixes.map(function (m) {
      var set = {};
      m.outputs.forEach(function (o) { outputChannels(o).forEach(function (c) { set[c] = true; }); });
      return set;
    });
    function overlaps(a, b) { return Object.keys(a).some(function (c) { return b[c]; }); }
    var found = {};
    state.mixes.forEach(function (mix, i) {
      var list = [];
      state.mixes.forEach(function (other, j) {
        if (i !== j && overlaps(used[i], used[j])) list.push({ "with": "mix", guid: other.guid, name: other.name });
      });
      if (overlaps(used[i], masterChannels)) list.push({ "with": "master" });
      if (list.length) found[mix.guid] = list;
    });
    return found;
  }

  // The picker for one mix: `readOnly` (several outputs: shown, never edited), `deviceClosed` (REAPER reports no
  // channels: the picker is disabled and the existing output is shown by number), `value` (the current choice) and
  // `options` ({ value, channel, mono }, `channel` null for "none"). Mono offers every channel, stereo each pair from an
  // even channel; an existing output the list does not offer (an odd pair, a closed device) is added so the picker
  // always shows what REAPER has.
  function outputPicker(state, mix) {
    var count = state.device && state.device.channels ? state.device.channels.length : 0;
    var current = mix.outputs.length === 1 ? mix.outputs[0] : null;
    var options = [{ value: "none", channel: null, mono: false }];
    var c;
    for (c = 0; c < count; c++) options.push({ value: "m:" + c, channel: c, mono: true });
    for (c = 0; c + 1 < count; c += 2) options.push({ value: "s:" + c, channel: c, mono: false });
    var value = current ? (current.mono ? "m:" : "s:") + current.channel : "none";
    if (!options.some(function (o) { return o.value === value; })) {
      options.push({ value: value, channel: current.channel, mono: current.mono });
    }
    return { readOnly: mix.outputs.length > 1, deviceClosed: count === 0, value: value, options: options };
  }

  // A picker value as the bridge's `output` command wants it: { none: true } or { channel, mono }; null if unreadable.
  function parseOutputChoice(value) {
    if (value === "none") return { none: true };
    var m = /^([ms]):(\d+)$/.exec(String(value));
    return m ? { channel: Number(m[2]), mono: m[1] === "m" } : null;
  }

  function matches(name, filter) {
    return !filter || name.toLowerCase().indexOf(filter) !== -1;
  }

  // The grid: a column per mix, a row per source track (every non-IEM track, in project order), each cell null (off) or
  //   { on, vol, db, muted, mode, nonStandard, sends, doubleFeed }
  // `doubleFeed` is null, or { with: "folder"|"child", name } when a folder and one of its children both feed the mix.
  // A source fed twice by the same mix (two sends) shows its first send and `sends` says how many. `filter` is the
  // name box: a case-insensitive substring; hidden rows still count for double feeds.
  function buildMatrix(state, filter) {
    var needle = String(filter || "").trim().toLowerCase();
    var columns = mixHeaders(state);
    var rowIndex = {};
    state.sources.forEach(function (s, i) { rowIndex[s.guid] = i; });

    // Each source's folder ancestors (nearest last), from the depth the bridge reports.
    var ancestors = [], chain = [];
    state.sources.forEach(function (s) {
      chain.length = Math.min(chain.length, s.depth);
      ancestors.push(chain.filter(Boolean));
      if (s.is_folder) chain[s.depth] = s;
    });

    var rows = state.sources.map(function (s) {
      return { guid: s.guid, name: s.name, depth: s.depth, isFolder: s.is_folder, cells: state.mixes.map(function () { return null; }) };
    });

    state.mixes.forEach(function (mix, col) {
      mix.sends.forEach(function (send) {
        var at = rowIndex[send.source];
        if (at === undefined) return; // a send from a track that is not a source row (another mix, the folder)
        var cell = rows[at].cells[col];
        if (cell) { cell.sends++; return; }
        rows[at].cells[col] = {
          on: true, vol: send.vol, db: dbText(send.vol), muted: !!send.muted, mode: send.mode,
          nonStandard: send.mode !== STANDARD_MODE, sends: 1, doubleFeed: null
        };
      });
      rows.forEach(function (row, at) {
        var cell = row.cells[col];
        if (!cell) return;
        ancestors[at].forEach(function (anc) {
          var up = rows[rowIndex[anc.guid]].cells[col];
          if (!up) return;
          if (!cell.doubleFeed) cell.doubleFeed = { "with": "folder", name: anc.name };
          if (!up.doubleFeed) up.doubleFeed = { "with": "child", name: row.name };
        });
      });
    });

    var shown = rows.filter(function (r) { return matches(r.name, needle); });
    return { columns: columns, rows: shown, totalRows: rows.length };
  }

  // ---- editing: the lock, and what a write may be asked --------------------------------------------------------------
  // The page opens locked and one Unlock tap enables editing (spec: "Guarding against accidents"). `canEdit` is the one
  // gate every write goes through: the buttons that change the project are enabled by it, and later issues (delete,
  // outputs, matrix cells) reuse it as it is.
  function canEdit(phase, unlocked) { return phase === "ready" && !!unlocked; }

  // The lock holds only while it is the same project on a live bridge: it closes again when the bridge goes away or
  // another project becomes the active one (an Unlock is for one project, not a standing licence).
  function stillUnlocked(unlocked, phase, projectBefore, projectNow) {
    if (!unlocked || phase !== "ready") return false;
    return projectBefore === null || projectBefore === undefined || projectBefore === projectNow;
  }

  // A mix name as typed, checked the way the bridge will check it (it checks again, and has the last word): trimmed,
  // never empty, and not the name of another mix. `ownGuid` is the mix being renamed, which may keep its own name.
  // The prefix IEM_ is never typed. Returns { ok: true, name } or { ok: false, code } (a code words.js has wording for).
  function checkMixName(state, raw, ownGuid) {
    var name = String(raw === undefined || raw === null ? "" : raw).trim();
    if (!name) return { ok: false, code: "empty_name" };
    var own = null;
    state.mixes.forEach(function (m) { if (m.guid === ownGuid) own = m; });
    if (own && own.name === name) return { ok: true, name: name, unchanged: true };
    var taken = state.mixes.some(function (m) { return m.guid !== ownGuid && m.name === name; });
    return taken ? { ok: false, code: "duplicate_name" } : { ok: true, name: name };
  }

  // What the page offers about the IEMs folder. `moveToEnd` is true only while tracks sit after it; the page never
  // moves the folder by itself. `colour` is "#rrggbb" for an <input type=color> (the project's, or the bridge's default).
  function folderOffer(state) {
    var folder = state.folder || null;
    return {
      exists: !!folder,
      guid: folder ? folder.guid : null,
      moveToEnd: !!(folder && folder.tracks_after),
      colour: "#" + (/^[0-9a-f]{6}$/i.test(state.colour || "") ? state.colour.toLowerCase() : "3b82c4")
    };
  }

  // An <input type=color> value ("#rrggbb") as the bridge wants it ("rrggbb"), or null.
  function colourField(value) {
    var m = /^#([0-9a-f]{6})$/i.exec(String(value || ""));
    return m ? m[1].toLowerCase() : null;
  }

  // What a tap on a cell asks for: an off cell is switched on, an on cell off (every send of the pair). The bridge takes
  // the desired state, not a toggle, so a stale page cannot flip a cell that changed meanwhile: it just finds it as asked.
  function cellRequest(row, col, cell) {
    return { source: row.guid, mix: col.guid, on: !cell };
  }

  // Row and column toggles: the bridge needs only the ID of the source or the mix and the wanted state.
  function rowRequest(row, on) { return { source: row.guid, on: on }; }
  function columnRequest(col, on) { return { mix: col.guid, on: on }; }

  // Rebuilding the grid replaces the buttons under a finger, so a press-and-hold in progress would lose its release
  // events. The gate defers the rebuild while any hold is active and paints once, with the latest state, when the last
  // one ends. `paint` is the page's rebuild; `request()` is what the page calls instead of painting.
  function createRenderGate(paint) {
    var holds = 0, pending = false;
    function flush() { if (!holds && pending) { pending = false; paint(); } }
    return {
      request: function () { if (holds) pending = true; else { pending = false; paint(); } },
      begin: function () { holds++; },
      end: function () { if (holds) holds--; flush(); },
      active: function () { return holds > 0; },
      pending: function () { return pending; }
    };
  }

  // One open picker holds the gate for as long as it is open, however many open/close events the browser sends for it
  // (focus, press, blur, change all report one open picker). `close()` lets the gate paint what it deferred.
  function createPickerGuard(gate) {
    var open = false;
    return {
      open: function () { if (!open) { open = true; gate.begin(); } },
      close: function () { if (open) { open = false; gate.end(); } },
      isOpen: function () { return open; }
    };
  }

  return { cellRequest: cellRequest, rowRequest: rowRequest, columnRequest: columnRequest, createRenderGate: createRenderGate, createPickerGuard: createPickerGuard, outputChannels: outputChannels, outputClashes: outputClashes,
    outputPicker: outputPicker, parseOutputChoice: parseOutputChoice, STANDARD_MODE: STANDARD_MODE, dbText: dbText, connectionPhase: connectionPhase, readState: readState,
    mixHeaders: mixHeaders, buildMatrix: buildMatrix, canEdit: canEdit, stillUnlocked: stillUnlocked,
    checkMixName: checkMixName, folderOffer: folderOffer, colourField: colourField };
});
