// Arrange: UI wiring. Talks to the Lua bridge (apps/arrange/docs/bridge.md) through client.js; every sentence comes
// from words.js. DOM is built with textContent only: Region Names are user data.
(function () {
  "use strict";
  var S = LCRR.shared, A = LCRR.arrange, wire = A.wire, words = A.words, E = A.editor;
  var APPLY_COOLDOWN_MS = 1500; // repeat taps on Apply inside this window are ignored (the token is single-use anyway)

  var conn = S.guard.createConnection({ failuresToOffline: 2, settleMs: 1000 });
  var beat = wire.createHeartbeat({ staleMs: 2500 });
  var applyCooldown = S.guard.createCooldown(APPLY_COOLDOWN_MS);
  var poller = S.poll.createPoller({ intervalMs: 500 });
  poller.addCommand(wire.getCommand("heartbeat"));

  // The long fetch: an Apply holds its request open until REAPER's main thread is free again.
  function fetchText(url, ms) {
    var ctl = typeof AbortController === "function" ? new AbortController() : null;
    var req = fetch(url, { cache: "no-store", signal: ctl ? ctl.signal : undefined }).then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.text();
    });
    return S.poll.withTimeout(req, ms, function (cb, t) { return setTimeout(cb, t); }, function (h) { clearTimeout(h); })
      .catch(function (err) { if (ctl) ctl.abort(); throw err; });
  }
  var counter = 0;
  var client = A.client.createClient({
    fetchText: fetchText,
    newId: function () { counter++; return Date.now().toString(36) + "-" + counter; }
  });

  function $(id) { return document.getElementById(id); }
  var els = {
    chip: $("arrange-state"), chipText: $("arrange-state-text"), banner: $("arrange-banner"),
    project: $("arrange-project"), projectPath: $("arrange-project-path"),
    work: $("arrange-work"), name: $("arrange-name"), sidecar: $("arrange-sidecar"),
    check: $("arrange-check"), verify: $("arrange-verify"),
    captureName: $("arrange-capture-name"), capture: $("arrange-capture"),
    dup: $("arrange-dup"), timebase: $("arrange-timebase"), bars: $("arrange-bars"),
    result: $("arrange-result"), busy: $("arrange-busy"), refresh: $("arrange-refresh"),
    tabRun: $("arrange-tab-run"), tabEdit: $("arrange-tab-edit"), panelRun: $("arrange-panel-run"), panelEdit: $("arrange-panel-edit"),
    newBtn: $("arrange-new"), dupBtn: $("arrange-duplicate"), renameBtn: $("arrange-rename"), deleteBtn: $("arrange-delete"),
    prompt: $("arrange-edit-prompt"), editNote: $("arrange-edit-note"), editMsg: $("arrange-edit-msg"),
    editor: $("arrange-editor"), emptyNote: $("arrange-empty-note"), inList: $("arrange-in"), outList: $("arrange-out"),
    editCheck: $("arrange-edit-check"), undoBtn: $("arrange-undo"), undoNote: $("arrange-undo-note")
  };
  var actionButtons = [els.check, els.verify, els.capture, els.dup, els.timebase, els.bars, els.refresh];
  var editButtons = [els.newBtn, els.dupBtn, els.renameBtn, els.deleteBtn, els.editCheck];

  var ui = { phase: "connecting", everLive: false, busy: false, info: null, projectPath: null, token: null, hasArrangements: false, wantName: null, focusAfter: null };

  // Small DOM helper: h("p", "class", "text")
  function h(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }
  function clear(e) { while (e.firstChild) e.removeChild(e.firstChild); }

  // ---- connection phase -------------------------------------------------------------------------------------------
  function phase() {
    if (conn.isOffline()) return "offline";
    if (!ui.everLive) return "connecting";
    var b = beat.state();
    if (b === "stopped") return "bridge-down";
    if (b === "unknown") return "connecting";
    return "ready";
  }

  var CHIP = { connecting: "Connecting…", ready: "Bridge running", offline: "REAPER unreachable", "bridge-down": "Bridge not running" };
  var BANNER = {
    offline: "REAPER is unreachable. This page keeps retrying.",
    "bridge-down": "The Arrange bridge is not running. In REAPER, open Actions › Show action list and run “LCRR Arrange: Bridge” once. If scripts/install.ps1 has been run, restarting REAPER starts it."
  };

  function applyPhase() {
    var next = phase();
    var was = ui.phase;
    ui.phase = next;
    els.chip.setAttribute("data-state", next);
    document.body.setAttribute("data-state", next);
    if (els.chipText.textContent !== CHIP[next]) els.chipText.textContent = CHIP[next];
    els.banner.textContent = BANNER[next] || "";
    els.banner.hidden = !BANNER[next];
    syncControls();
    if (next === "ready" && was !== "ready" && !ui.busy) refreshInfo();
  }

  poller.subscribe(function (e) {
    if (ui.busy) return; // our own request is open, and REAPER may be too busy to answer polls
    var live = e.ok && !!S.reaper.parseTransport(e.text);
    conn.update(live);
    if (live) { ui.everLive = true; beat.update(wire.parseExtState(e.text, "heartbeat")); }
    applyPhase();
  });

  // ---- controls ---------------------------------------------------------------------------------------------------
  function syncControls() {
    var ready = ui.phase === "ready" && !ui.busy;
    els.work.classList.toggle("is-locked", ui.phase !== "ready");
    actionButtons.forEach(function (b) { b.disabled = !ready; });
    var needName = !ready || !ui.hasArrangements;
    els.check.disabled = els.verify.disabled = needName;
    els.name.disabled = !ready || !ui.hasArrangements;
    els.captureName.disabled = !ready;
    var apply = $("arrange-apply");
    if (apply) apply.disabled = !ready;
    document.querySelectorAll(".arrange-answer").forEach(function (b) { b.disabled = !ready; });
    syncEditControls();
  }

  var busyTimer = null, busySince = 0;
  function setBusy(on, label, showElapsed, quiet) {
    ui.busy = on;
    clearInterval(busyTimer);
    busyTimer = null;
    els.busy.hidden = !on || !!quiet;
    document.body.classList.toggle("is-busy", on);
    if (on && !quiet) {
      busySince = Date.now();
      var tick = function () {
        els.busy.textContent = label + (showElapsed ? " " + Math.floor((Date.now() - busySince) / 1000) + " s" : "");
      };
      tick();
      if (showElapsed) busyTimer = setInterval(tick, 1000);
    }
    syncControls();
  }

  // Hold the page for one bridge call: no polling and no second command while it is open. `quiet` skips the busy bar
  // (an edit takes well under a second, and the bar would make the sticky header jump). Rejects with code "busy" when
  // something else is in flight.
  function exclusive(label, long, quiet, fn) {
    if (ui.busy) { var e = new Error("busy"); e.code = "busy"; return Promise.reject(e); }
    setBusy(true, label, !!long, quiet);
    poller.stop();
    function done() {
      setBusy(false);
      beat.touch(); // nothing could beat while REAPER was busy
      poller.start();
    }
    return fn().then(function (reply) { noteProject(reply.project); done(); return reply; }, function (err) { done(); throw err; });
  }

  // Run one bridge command. Resolves with the reply, or null after showing why there is none.
  function run(cmd, fields, label, long) {
    return exclusive(label, long, false, function () {
      return client.call(cmd, fields, { timeoutMs: long ? A.client.APPLY_TIMEOUT_MS : undefined });
    }).then(null, function (err) {
      if (err.code === "busy") return null;
      showProblem("It did not go through", words.failure(err.code));
      return null;
    });
  }

  // The editor's client: the same bridge calls, held exclusively and quietly, rejecting like client.js.
  var editor = E.createEditor({
    arrangements: function () { return exclusive("", false, true, function () { return client.arrangements(); }); },
    edit: function (base, op, fields) { return exclusive("", false, true, function () { return client.edit(base, op, fields); }); }
  });

  // ---- project ----------------------------------------------------------------------------------------------------
  function noteProject(project) {
    if (!project) return;
    var changed = ui.projectPath !== null && ui.projectPath !== project.path;
    ui.projectPath = project.path;
    $("arrange-project-name").textContent = project.name || "(unsaved project)";
    els.projectPath.textContent = project.path || "";
    els.project.hidden = false;
    if (changed) {
      ui.token = null;
      clear(els.result);
      showProblem("A different project is open", "REAPER is showing another project now. Anything below from before this was about the previous one, so it has been cleared.");
    }
  }

  // Read the sidecar and the regions into the editor, refill the picker and redraw the editor. Resolves true when
  // the read worked. `keepName` keeps the picker where it is when that Arrangement still exists.
  function refreshInfo() {
    return editor.load().then(function () {
      refreshSidecarNote();
      fillNames(editor.names());
      renderEditor();
      return true;
    }, function (err) {
      if (err.code === "busy") return false;
      if (err.code === "refused") showProblem("Could not read the project", words.error(err.reply.error));
      else showProblem("It did not go through", words.failure(err.code));
      return false;
    });
  }

  // Focus, visibility, and before each Check: the file may have changed under the page. Redraws only on a change, so
  // a half-typed Headroom is not thrown away by a focus event.
  function reread() {
    if (ui.phase !== "ready" || ui.busy || !ui.everLive) return Promise.resolve(false);
    return editor.load().then(function (got) {
      if (got.changed) {
        fillNames(editor.names());
        renderEditor();
        refreshSidecarNote();
      }
      return true;
    }, function () { return false; });
  }

  function refreshSidecarNote() {
    var v = editor.view();
    var note = "";
    if (v.sidecar === "unsaved") note = words.error({ code: "sidecar_unsaved" });
    else if (v.sidecar === "missing") note = words.error({ code: "sidecar_missing" });
    else if (v.sidecar === "invalid") note = "The Arrangement sidecar exists but could not be read. Fix it in a text editor on the host.";
    else if (!v.arrangements.length) note = words.error({ code: "no_arrangements" });
    els.sidecar.textContent = note;
    els.sidecar.hidden = !note;
  }

  function fillNames(names) {
    var keep = ui.wantName || els.name.value;
    ui.wantName = null;
    clear(els.name);
    names.forEach(function (n) { var o = h("option", "", n); o.value = n; els.name.appendChild(o); });
    if (names.indexOf(keep) >= 0) els.name.value = keep;
    ui.hasArrangements = names.length > 0;
    syncControls();
  }

  // ---- result panel -----------------------------------------------------------------------------------------------
  function card(title) {
    clear(els.result);
    els.result.appendChild(h("h2", "arrange-result-title", title));
    return els.result;
  }
  function paragraphs(parent, list) { list.forEach(function (t) { parent.appendChild(h("p", "arrange-text", t)); }); }
  function showProblem(title, text) {
    var c = card(title);
    c.classList.add("is-problem");
    paragraphs(c, [text]);
  }
  function fresh(title) { var c = card(title); c.classList.remove("is-problem"); return c; }
  function showRefusal(title, err) { showProblem(title, words.error(err)); }

  function addFindings(parent, findings) {
    var current = null, group = null;
    findings.forEach(function (entry) {
      var sev = entry.severity || "refusal";
      if (sev !== current) {
        current = sev;
        group = h("section", "arrange-group");
        if (entry.severity) group.appendChild(h("h3", "arrange-group-title", words.severityHeading(sev)));
        group.setAttribute("data-severity", sev);
        parent.appendChild(group);
      }
      var p = h("p", "arrange-finding");
      p.appendChild(h("span", "arrange-code", entry.code));
      p.appendChild(document.createTextNode(words.finding(entry)));
      group.appendChild(p);
    });
  }
  function addBlindSpots(parent, codes, heading) {
    parent.appendChild(h("h3", "arrange-group-title", heading));
    var ul = h("ul", "arrange-list");
    codes.forEach(function (c) { ul.appendChild(h("li", "", words.blindSpot(c))); });
    parent.appendChild(ul);
  }

  function showCheck(reply) {
    var c = fresh("Check: " + reply.name);
    var proceeds = reply.verdict === "will proceed";
    c.appendChild(h("p", "arrange-verdict " + (proceeds ? "is-ok" : "is-bad"), words.checkVerdict(reply)));
    addFindings(c, reply.findings);
    c.appendChild(h("p", "arrange-text", words.paddingNote(reply.padding_exact)));
    addBlindSpots(c, reply.blind_spots, "What this check cannot see");
    if (reply.token) {
      ui.token = reply.token;
      var row = h("div", "arrange-apply-row");
      var apply = h("button", "arrange-primary", "Apply “" + reply.name + "”");
      apply.type = "button";
      apply.id = "arrange-apply";
      apply.addEventListener("click", function () { doApply(null); });
      row.appendChild(apply);
      row.appendChild(h("span", "arrange-hint", "Changes the project. Undo in REAPER takes it back; the run log is written beside the project."));
      c.appendChild(row);
    } else {
      ui.token = null;
    }
    syncControls();
  }

  function showVerify(reply) {
    var c = fresh("Verify: " + reply.name);
    c.appendChild(h("p", "arrange-verdict " + (reply.verdict === "pass" ? "is-ok" : "is-bad"), words.verifyVerdict(reply)));
    addFindings(c, reply.findings);
    addBlindSpots(c, reply.blind_spots, "What this check cannot see");
  }

  function showApplied(reply, answer) {
    var c = fresh("Applied");
    paragraphs(c, words.applySummary(reply));
    var offer = E.clearHeadroomOffer(answer, reply);
    if (!offer) return;
    var box = h("div", "arrange-offer");
    box.appendChild(h("p", "arrange-text", words.clearOffer.text(offer.arrangement)));
    var row = h("div", "arrange-apply-row");
    var btn = h("button", "arrange-answer", words.clearOffer.button);
    btn.type = "button";
    btn.addEventListener("click", function () { doClearHeadroom(offer.arrangement, box, false); });
    row.appendChild(btn);
    box.appendChild(row);
    c.appendChild(box);
    syncControls();
  }

  // One ordinary, undoable edit; the answer replaces the offer in the result panel. Never automatic.
  function doClearHeadroom(arrangement, box, rewrite) {
    function say(text) { clear(box); box.appendChild(h("p", "arrange-text", text)); }
    editor.dispatch("clear_headroom", { arrangement: arrangement }, { rewrite: rewrite }).then(function (out) {
      if (out.kind === "failed") { if (out.code !== "busy") say(words.failure(out.code)); return; }
      if (out.kind === "confirm") {
        clear(box);
        box.appendChild(h("p", "arrange-text", words.rewriteQuestion()));
        var row = h("div", "arrange-apply-row");
        var yes = h("button", "arrange-answer arrange-primary", "Rewrite"); yes.type = "button";
        yes.addEventListener("click", function () { doClearHeadroom(arrangement, box, true); });
        var no = h("button", "arrange-answer", "Keep the file"); no.type = "button";
        no.addEventListener("click", function () { say("Nothing was written."); });
        row.appendChild(yes); row.appendChild(no); box.appendChild(row);
        syncControls();
        return;
      }
      if (out.kind === "ok") {
        say(out.before && out.before.some(function (e) { return e.headroom; }) ? words.clearOffer.done(arrangement) : words.clearOffer.nothing(arrangement));
        syncAll();
        return;
      }
      say(words.error(out.error));
      syncAll();
    });
  }

  function showHeadroomQuestion(reply) {
    var c = fresh("Confirm Headroom");
    c.appendChild(h("p", "arrange-text arrange-pre", words.headroomQuestion(reply.confirm.headroom)));
    var row = h("div", "arrange-apply-row");
    [["Apply the Headroom", "apply", "arrange-primary"], ["Repack only", "zero", ""], ["Cancel", "cancel", ""]].forEach(function (b) {
      var btn = h("button", "arrange-answer " + b[2], b[0]);
      btn.type = "button";
      btn.addEventListener("click", function () { doApply(b[1]); });
      row.appendChild(btn);
    });
    c.appendChild(row);
    syncControls();
  }

  // ---- commands ---------------------------------------------------------------------------------------------------
  function selectedName() { return els.name.value; }

  // Re-read the file first: what the editor shows must be what Check reads.
  function doCheck() {
    var name = selectedName();
    reread().then(function () {
      if (name && editor.names().indexOf(name) < 0) {
        ui.token = null;
        return showRefusal("Check did not run", { code: "arrangement_unknown", name: name, available: editor.names() });
      }
      return run("check", { name: name }, "Checking…").then(function (reply) {
        if (!reply) return;
        if (reply.status === "ok") showCheck(reply); else { ui.token = null; showRefusal("Check did not run", reply.error); }
      });
    });
  }

  function doVerify() {
    run("verify", { name: selectedName() }, "Verifying…").then(function (reply) {
      if (!reply) return;
      if (reply.status === "ok") showVerify(reply); else showRefusal("Verify did not run", reply.error);
    });
  }

  function doApply(answer) {
    if (!ui.token) return;
    if (answer === null && !applyCooldown.tryFire()) return;
    var fields = { token: ui.token };
    if (answer) fields.headroom = answer;
    run("apply", fields, "Applying…", true).then(function (reply) {
      if (!reply) { ui.token = null; return; }
      if (reply.status === "confirm") return showHeadroomQuestion(reply);
      ui.token = null;
      if (reply.status === "cancelled") { fresh("Cancelled"); paragraphs(els.result, ["Nothing was written."]); return; }
      if (reply.status === "ok") { showApplied(reply, answer); refreshInfo(); return; }
      showRefusal("Apply did not run", reply.error);
    });
  }

  // `answers` carries the Yes answers given so far ({ replace, rewrite }): the
  // bridge asks one question at a time, and each answer is repeated with the request.
  function doCapture(answers) {
    answers = answers || {};
    var name = els.captureName.value.trim();
    run("capture", { name: name, replace: answers.replace ? "1" : undefined,
      rewrite: answers.rewrite ? "1" : undefined }, "Capturing…").then(function (reply) {
      if (!reply) return;
      if (reply.status === "ok") {
        var c = fresh("Captured");
        c.appendChild(h("p", "arrange-text arrange-pre", words.captureSummary(reply)));
        refreshInfo();
      } else if (reply.status === "confirm") {
        var code = reply.confirm.code;
        var isRewrite = code === "rewrite";
        var q = fresh(isRewrite ? "Rewrite the sidecar?" : "Replace " + reply.confirm.name + "?");
        paragraphs(q, [isRewrite ? words.rewriteQuestion() : words.replaceQuestion(reply.confirm.name)]);
        var row = h("div", "arrange-apply-row");
        var yes = h("button", "arrange-answer arrange-primary", isRewrite ? "Rewrite" : "Replace");
        yes.type = "button";
        yes.addEventListener("click", function () {
          var next = { replace: answers.replace, rewrite: answers.rewrite };
          next[code] = true;
          doCapture(next);
        });
        var no = h("button", "arrange-answer", isRewrite ? "Keep the file" : "Keep it");
        no.type = "button";
        no.addEventListener("click", function () { fresh("Kept"); paragraphs(els.result, ["Nothing was written."]); });
        row.appendChild(yes); row.appendChild(no);
        q.appendChild(row);
        syncControls();
      } else showRefusal("Capture did not run", reply.error);
    });
  }

  function table(headers, rows) {
    var t = h("table", "arrange-table");
    var head = h("tr");
    headers.forEach(function (x) { head.appendChild(h("th", "", x)); });
    t.appendChild(head);
    rows.forEach(function (r) {
      var tr = h("tr");
      r.forEach(function (x) { tr.appendChild(h("td", "", x)); });
      t.appendChild(tr);
    });
    return t;
  }

  function doDuplicates() {
    run("duplicates", {}, "Looking…").then(function (reply) {
      if (!reply) return;
      var c = fresh("Duplicate and unnamed regions");
      if (reply.verdict === "no_regions") paragraphs(c, ["This project has no regions."]);
      else if (reply.verdict === "clean") paragraphs(c, ["All " + reply.region_count + " region names are unique and non-empty.", "This project is ready for Arrangements."]);
      else {
        paragraphs(c, [reply.problems.length + " problem(s) across " + reply.region_count + " regions:"]);
        c.appendChild(h("p", "arrange-text arrange-pre", words.problems(reply.problems)));
        paragraphs(c, ["Rename them in REAPER so every region has a unique, non-empty name."]);
      }
    });
  }

  function doTimebase() {
    run("timebase", {}, "Reading tracks…").then(function (reply) {
      if (!reply) return;
      if (reply.status !== "ok") return showRefusal("Track timebase", reply.error);
      var c = fresh("Track timebase");
      c.appendChild(table(["Track", "Name", "Timebase"], reply.tracks.map(function (t) {
        return [String(t.track_index + 1), t.name, t.mode + " " + words.timebase(t.mode)];
      })));
      c.appendChild(h("h3", "arrange-group-title", "Tally"));
      c.appendChild(table(["Mode", "Timebase", "Tracks"], reply.tally.map(function (t) { return [String(t.mode), words.timebase(t.mode), String(t.count)]; })));
      paragraphs(c, ["Track timebase only. Items can override it; that is not shown here."]);
    });
  }

  function doBars() {
    run("barlines", {}, "Asking REAPER for bar lines…").then(function (reply) {
      if (!reply) return;
      if (reply.status !== "ok") return showRefusal("Bar lines and Padding", reply.error);
      var c = fresh("Bar lines and Padding");
      paragraphs(c, [reply.padded + " of " + reply.regions.length + " region(s) would be padded, adding " + reply.total_pad.toFixed(3) + "s of silence in total.",
        "Tempo at 0.0: " + reply.origin.bpm + " bpm, " + reply.origin.num + "/" + reply.origin.denom + "."]);
      c.appendChild(table(["Region", "Start", "End", "Start on a bar line", "Padding"], reply.regions.map(function (r) {
        return [r.name, r.start_time.toFixed(3), r.end_time.toFixed(3), r.on_bar ? "yes" : "a Tempo Anchor will make it so", r.pads ? "+" + r.pad.toFixed(3) + "s" : "none"];
      })));
      paragraphs(c, ["Nothing has been changed."]);
    });
  }


  // ---- tabs -------------------------------------------------------------------------------------------------------
  var TAB_KEY = "lcrr.arrange.tab";
  function setTab(which, remember) {
    var edit = which === "edit";
    els.tabRun.setAttribute("aria-selected", String(!edit));
    els.tabEdit.setAttribute("aria-selected", String(edit));
    els.tabRun.tabIndex = els.tabEdit.tabIndex = 0;
    els.panelRun.hidden = edit;
    els.panelEdit.hidden = !edit;
    if (remember) { try { localStorage.setItem(TAB_KEY, which); } catch (e) { /* storage may be blocked */ } }
  }
  els.tabRun.addEventListener("click", function () { setTab("run", true); });
  els.tabEdit.addEventListener("click", function () { setTab("edit", true); });
  [els.tabRun, els.tabEdit].forEach(function (t) {
    t.addEventListener("keydown", function (e) {
      if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return;
      var next = t === els.tabRun ? els.tabEdit : els.tabRun;
      next.click(); next.focus();
    });
  });
  try { if (localStorage.getItem(TAB_KEY) === "edit") setTab("edit", false); } catch (e) { /* storage may be blocked */ }

  // ---- editor -----------------------------------------------------------------------------------------------------
  function currentEntries() { return editor.entriesOf(selectedName()); }

  function showMsg(text) {
    els.editMsg.textContent = text || ""; els.editMsg.hidden = !text;
    els.undoNote.textContent = ""; els.undoNote.hidden = true; // the undo note is replaced by the next thing that happens
  }
  function hidePrompt() { clear(els.prompt); els.prompt.hidden = true; }
  function showPrompt(build) { clear(els.prompt); build(els.prompt); els.prompt.hidden = false; syncControls(); }

  function syncAll() { fillNames(editor.names()); refreshSidecarNote(); renderEditor(); }

  function syncEditControls() {
    var ready = ui.phase === "ready" && !ui.busy;
    var v = editor.view();
    var has = v.sidecar === "ok" && !!editor.find(selectedName());
    els.newBtn.disabled = !ready || (v.sidecar !== "ok" && v.sidecar !== "missing");
    var next = editor.peekUndo();
    els.undoBtn.disabled = !ready || !next;
    els.undoBtn.title = next ? "Undo " + words.undoLabel(next) : "Nothing to undo";
    els.dupBtn.disabled = els.renameBtn.disabled = els.deleteBtn.disabled = els.editCheck.disabled = !ready || !has;
    document.querySelectorAll("#arrange-editor .arrange-row button, #arrange-editor .arrange-row input").forEach(function (b) {
      b.disabled = !ready || b.getAttribute("data-off") === "1";
    });
  }

  function button(label, cls, onClick, aria) {
    var b = h("button", cls, label);
    b.type = "button";
    if (aria) b.setAttribute("aria-label", aria);
    b.addEventListener("click", onClick);
    return b;
  }

  // Send one operation. `focus` = { name, cls } to put the focus back on after the redraw.
  function doEdit(operation, fields, focus, rewrite) {
    showMsg("");
    return editor.dispatch(operation, fields, { rewrite: !!rewrite }).then(function (out) {
      if (out.kind === "failed") { if (out.code !== "busy") showMsg(words.failure(out.code)); return; }
      if (out.kind === "confirm") {
        return showPrompt(function (p) {
          p.appendChild(h("p", "arrange-text", words.rewriteQuestion()));
          var row = h("div", "arrange-apply-row");
          row.appendChild(button("Rewrite", "arrange-answer arrange-primary", function () { hidePrompt(); doEdit(operation, fields, focus, true); }));
          row.appendChild(button("Keep the file", "arrange-answer", function () { hidePrompt(); showMsg("Nothing was written."); }));
          p.appendChild(row);
        });
      }
      if (out.kind === "ok") {
        hidePrompt();
        if (operation === "new" || operation === "duplicate" || operation === "rename") ui.wantName = out.name;
        ui.focusAfter = focus || null;
        syncAll();
        return;
      }
      showMsg(words.error(out.error));
      syncAll();
    });
  }

  // New, Duplicate and Rename share one small form.
  function askName(title, initial, onName) {
    showPrompt(function (p) {
      var form = h("form");
      var label = h("label", "arrange-field");
      label.appendChild(h("span", "arrange-label", title));
      var input = h("input");
      input.type = "text"; input.value = initial; input.autocomplete = "off";
      label.appendChild(input);
      var problem = h("p", "arrange-hint");
      problem.hidden = true;
      var row = h("div", "arrange-apply-row");
      var ok = h("button", "arrange-answer arrange-primary", "OK"); ok.type = "submit";
      row.appendChild(ok);
      row.appendChild(button("Cancel", "arrange-answer", hidePrompt));
      form.appendChild(label); form.appendChild(problem); form.appendChild(row);
      form.addEventListener("submit", function (ev) {
        ev.preventDefault();
        var got = E.checkName(input.value, editor.names());
        if (!got.ok) { problem.textContent = words.error({ code: got.code }); problem.hidden = false; return; }
        hidePrompt();
        onName(got.name);
      });
      p.appendChild(form);
      setTimeout(function () { input.focus(); input.select(); }, 0);
    });
  }

  els.newBtn.addEventListener("click", function () {
    showMsg("");
    askName("Name of the new Arrangement", "", function (name) { doEdit("new", { name: name }); });
  });
  els.dupBtn.addEventListener("click", function () {
    var from = selectedName();
    showMsg("");
    askName("Name of the copy of " + from, E.copyName(from, editor.names()), function (name) { doEdit("duplicate", { arrangement: from, name: name }); });
  });
  els.renameBtn.addEventListener("click", function () {
    var from = selectedName();
    showMsg("");
    askName("New name for " + from, from, function (name) { if (name !== from) doEdit("rename", { arrangement: from, name: name }); });
  });
  els.deleteBtn.addEventListener("click", function () {
    var name = selectedName(), entries = currentEntries();
    if (!entries) return;
    showMsg("");
    showPrompt(function (p) {
      p.appendChild(h("p", "arrange-text", words.deleteQuestion(name, entries.length)));
      var row = h("div", "arrange-apply-row");
      row.appendChild(button("Delete", "arrange-answer arrange-primary", function () { hidePrompt(); doEdit("delete", { arrangement: name }); }));
      row.appendChild(button("Keep it", "arrange-answer", hidePrompt));
      p.appendChild(row);
    });
  });
  function doUndo() {
    showMsg("");
    hidePrompt();
    var next = editor.peekUndo();
    editor.undo().then(function (out) {
      if (out.kind === "empty") return;
      if (out.kind === "failed") { if (out.code !== "busy") showMsg(words.failure(out.code)); return syncAll(); }
      if (out.kind === "undone") els.undoNote.textContent = words.undone(out.entry);
      else if (out.kind === "stale") els.undoNote.textContent = words.undoStale();
      else if (out.kind === "partial") showMsg(words.undoPartial(out.entry));
      else showMsg(words.undoRefused(next) + " " + words.error(out.error));
      els.undoNote.hidden = !els.undoNote.textContent;
      syncAll();
    });
  }
  els.undoBtn.addEventListener("click", doUndo);
  editor.subscribe(function () { syncEditControls(); });
  els.editCheck.addEventListener("click", function () { setTab("run", true); doCheck(); });
  els.name.addEventListener("change", function () { hidePrompt(); showMsg(""); renderEditor(); });

  function renderEditor() {
    var v = editor.view();
    var name = selectedName();
    var arr = editor.find(name);
    var writable = v.sidecar === "ok" || v.sidecar === "missing";
    var note = v.sidecar === "ok" ? "" : words.noSidecarEditNote(v.sidecar, v.parseError);
    els.editNote.textContent = note;
    els.editNote.hidden = !note;
    clear(els.inList); clear(els.outList);
    els.editor.hidden = !(writable && arr);
    if (arr && writable) {
      var lists = E.splitLists(arr.entries, v.regions);
      els.emptyNote.textContent = lists.inList.length ? "" : words.emptyArrangementNote(name);
      els.emptyNote.hidden = !!lists.inList.length;
      lists.inList.forEach(function (row, i) { els.inList.appendChild(inRow(name, row, i, lists.inList.length)); });
      lists.leftOut.forEach(function (row) { els.outList.appendChild(outRow(name, row)); });
      if (!lists.leftOut.length) els.outList.appendChild(h("li", "arrange-hint", "Nothing: every region of the project is in this Arrangement."));
    }
    syncEditControls();
    if (ui.focusAfter) {
      var f = ui.focusAfter; ui.focusAfter = null;
      var rows = els.inList.children;
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].getAttribute("data-name") !== f.name) continue;
        var target = rows[i].querySelector("." + f.cls + ":not(:disabled)") || rows[i].querySelector(".arrange-handle");
        if (target) target.focus();
        break;
      }
    }
  }

  function outRow(arrangement, row) {
    var li = h("li", "arrange-row");
    li.setAttribute("data-name", row.name);
    li.appendChild(h("span", "arrange-row-name", row.name));
    li.appendChild(button("Add", "arrange-add", function () { doEdit("add", { arrangement: arrangement, region: row.name }); }, "Add " + row.name + " to the Arrangement"));
    return li;
  }

  function inRow(arrangement, row, i, n) {
    var li = h("li", "arrange-row" + (row.inProject ? "" : " is-missing"));
    li.setAttribute("data-name", row.name);
    var nameBox = h("span", "arrange-row-name", row.name);
    if (!row.inProject) nameBox.appendChild(h("span", "arrange-flag", "not in the project"));
    function step(dir, cls) {
      var slot = E.slotForStep(i, dir, n);
      return function () { if (slot) doEdit("move", { arrangement: arrangement, region: row.name, slot: String(slot) }, { name: row.name, cls: cls }); };
    }
    var remove = button("Remove", "arrange-remove", function () { doEdit("remove", { arrangement: arrangement, region: row.name }); }, "Remove " + row.name + " from the Arrangement");
    if (!row.inProject) {
      li.appendChild(nameBox);
      li.appendChild(remove);
      return li;
    }
    var handle = h("button", "arrange-handle", "⠇⠇");
    handle.type = "button";
    handle.setAttribute("aria-label", "Drag " + row.name + " to a new position");
    handle.addEventListener("pointerdown", function (e) { startDrag(e, handle, arrangement, row.name, i); });
    li.appendChild(handle);
    li.appendChild(nameBox);

    var hr = h("span", "arrange-headroom");
    var input = h("input");
    input.type = "text"; input.value = E.formatSeconds(row.headroom); input.autocomplete = "off";
    input.setAttribute("aria-label", "Headroom in seconds for " + row.name);
    var label = h("span", "arrange-headroom-label", words.headroomLabel(row.headroom));
    function setHeadroom(seconds) {
      if (seconds === row.headroom) return;
      doEdit("set_headroom", { arrangement: arrangement, region: row.name, headroom: E.formatSeconds(seconds) }, { name: row.name, cls: "arrange-hr-input" });
    }
    input.className = "arrange-hr-input";
    input.addEventListener("change", function () {
      var got = E.parseHeadroom(input.value);
      if (!got.ok) { showMsg(words.headroomInputInvalid()); input.value = E.formatSeconds(row.headroom); return; }
      showMsg("");
      input.value = E.formatSeconds(got.seconds);
      setHeadroom(got.seconds);
    });
    input.addEventListener("keydown", function (e) { if (e.key === "Enter") input.blur(); });
    hr.appendChild(button("−1 s", "arrange-hr-down", function () { setHeadroom(E.stepHeadroom(row.headroom, -1)); }, "Headroom of " + row.name + " minus one second"));
    hr.appendChild(input);
    hr.appendChild(button("+1 s", "arrange-hr-up", function () { setHeadroom(E.stepHeadroom(row.headroom, 1)); }, "Headroom of " + row.name + " plus one second"));
    hr.appendChild(label);
    li.appendChild(hr);

    var up = button("↑", "arrange-up", step(-1, "arrange-up"), "Move " + row.name + " up");
    var down = button("↓", "arrange-down", step(1, "arrange-down"), "Move " + row.name + " down");
    if (i === 0) { up.disabled = true; up.setAttribute("data-off", "1"); }
    if (i === n - 1) { down.disabled = true; down.setAttribute("data-off", "1"); }
    li.appendChild(up); li.appendChild(down); li.appendChild(remove);
    return li;
  }

  // Drag by the handle, pointer events only (mouse, pen and touch alike). The rows do not move while dragging, so
  // their midpoints are read once; a drop is one move.
  function startDrag(e, handle, arrangement, region, from) {
    if (ui.busy || ui.phase !== "ready" || (e.button !== undefined && e.button !== 0)) return;
    e.preventDefault();
    var rows = Array.prototype.slice.call(els.inList.children);
    var mids = rows.map(function (r) { var b = r.getBoundingClientRect(); return b.top + b.height / 2; });
    var n = rows.length, gap = from;
    try { handle.setPointerCapture(e.pointerId); } catch (err) { /* the drag still works while the pointer stays over the handle */ }
    rows[from].classList.add("is-dragging");
    function mark() {
      rows.forEach(function (r) { r.classList.remove("is-drop-before", "is-drop-after"); });
      if (E.slotForDrop(from, gap, n) === null) return;
      if (gap < n) rows[gap].classList.add("is-drop-before"); else rows[n - 1].classList.add("is-drop-after");
    }
    function move(ev) { gap = E.gapAt(ev.clientY, mids); mark(); }
    function finish(drop) {
      handle.removeEventListener("pointermove", move);
      handle.removeEventListener("pointerup", up);
      handle.removeEventListener("pointercancel", cancel);
      rows.forEach(function (r) { r.classList.remove("is-dragging", "is-drop-before", "is-drop-after"); });
      var slot = drop ? E.slotForDrop(from, gap, n) : null;
      if (slot) doEdit("move", { arrangement: arrangement, region: region, slot: String(slot) }, { name: region, cls: "arrange-handle" });
    }
    function up(ev) { try { handle.releasePointerCapture(ev.pointerId); } catch (err) { /* already released */ } finish(true); }
    function cancel() { finish(false); }
    handle.addEventListener("pointermove", move);
    handle.addEventListener("pointerup", up);
    handle.addEventListener("pointercancel", cancel);
  }

  window.addEventListener("focus", reread);
  document.addEventListener("visibilitychange", function () { if (!document.hidden) reread(); });

  els.check.addEventListener("click", doCheck);
  els.verify.addEventListener("click", doVerify);
  els.capture.addEventListener("click", function () { doCapture(false); });
  els.dup.addEventListener("click", doDuplicates);
  els.timebase.addEventListener("click", doTimebase);
  els.bars.addEventListener("click", doBars);
  els.refresh.addEventListener("click", refreshInfo);
  els.captureName.addEventListener("keydown", function (e) { if (e.key === "Enter" && !els.capture.disabled) doCapture(false); });

  applyPhase();
  poller.start();
})();
