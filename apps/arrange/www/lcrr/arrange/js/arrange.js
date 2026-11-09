// Arrange: UI wiring. Talks to the Lua bridge (apps/arrange/docs/bridge.md) through client.js; every sentence comes
// from words.js. DOM is built with textContent only: Region Names are user data.
(function () {
  "use strict";
  var S = LCRR.shared, A = LCRR.arrange, wire = A.wire, words = A.words;
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
    result: $("arrange-result"), busy: $("arrange-busy"), refresh: $("arrange-refresh")
  };
  var actionButtons = [els.check, els.verify, els.capture, els.dup, els.timebase, els.bars, els.refresh];

  var ui = { phase: "connecting", everLive: false, busy: false, info: null, projectPath: null, token: null, hasArrangements: false };

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
  }

  var busyTimer = null, busySince = 0;
  function setBusy(on, label, showElapsed) {
    ui.busy = on;
    clearInterval(busyTimer);
    busyTimer = null;
    els.busy.hidden = !on;
    document.body.classList.toggle("is-busy", on);
    if (on) {
      busySince = Date.now();
      var tick = function () {
        els.busy.textContent = label + (showElapsed ? " " + Math.floor((Date.now() - busySince) / 1000) + " s" : "");
      };
      tick();
      if (showElapsed) busyTimer = setInterval(tick, 1000);
    }
    syncControls();
  }

  // Run one bridge command. Resolves with the reply, or null after showing why there is none.
  function run(cmd, fields, label, long) {
    if (ui.busy) return Promise.resolve(null);
    setBusy(true, label, !!long);
    poller.stop();
    return client.call(cmd, fields, { timeoutMs: long ? A.client.APPLY_TIMEOUT_MS : undefined }).then(function (reply) {
      noteProject(reply.project);
      return reply;
    }, function (err) {
      showProblem("It did not go through", words.failure(err.code));
      return null;
    }).then(function (reply) {
      setBusy(false);
      beat.touch(); // nothing could beat while REAPER was busy
      poller.start();
      return reply;
    });
  }

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

  function refreshInfo() {
    return run("info", {}, "Reading the project…").then(function (reply) {
      if (!reply) return;
      if (reply.status !== "ok") { showProblem("Could not read the project", words.error(reply.error)); return; }
      ui.info = reply;
      fillNames(reply.arrangements);
      var note = "";
      if (reply.sidecar === "unsaved") note = words.error({ code: "sidecar_unsaved" });
      else if (reply.sidecar === "missing") note = words.error({ code: "sidecar_missing" });
      else if (reply.sidecar === "invalid") note = "The Arrangement sidecar exists but could not be read. Fix it in a text editor on the host.";
      else if (!reply.arrangements.length) note = words.error({ code: "no_arrangements" });
      els.sidecar.textContent = note;
      els.sidecar.hidden = !note;
    });
  }

  function fillNames(names) {
    var keep = els.name.value;
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

  function showApplied(reply) {
    var c = fresh("Applied");
    paragraphs(c, words.applySummary(reply));
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

  function doCheck() {
    var name = selectedName();
    run("check", { name: name }, "Checking…").then(function (reply) {
      if (!reply) return;
      if (reply.status === "ok") showCheck(reply); else { ui.token = null; showRefusal("Check did not run", reply.error); }
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
      if (reply.status === "ok") { showApplied(reply); refreshInfo(); return; }
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
