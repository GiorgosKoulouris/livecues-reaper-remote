// Podium: UI wiring (transport bar, tabs, regions, markers, offline).
(function () {
  "use strict";
  var S = LCRR.shared, reaper = S.reaper, poll = S.poll, core = LCRR.podium.core;
  var HOLD_MS = 800;
  var STOP_HOLD_MS = 500;     // hold-to-stop, playing or recording
  var CUE_HOLD_MS = 500;      // hold-to-cue while the transport is running
  var CUE_COOLDOWN_MS = 1500; // repeat cue taps inside this window are ignored
  var conn = S.guard.createConnection({ failuresToOffline: 2, settleMs: 1500 });
  var cueCooldown = S.guard.createCooldown(CUE_COOLDOWN_MS);
  var everLoaded = false;     // at least one usable reply received
  var transportActive = false; // playstate != 0: a cue now would cut a running song
  var poller = poll.createPoller({ intervalMs: 500 });
  poller.addCommand("REGION");
  poller.addCommand("MARKER");

  function sendCommand(c) { poll.send(c).then(poller.pollNow, poller.pollNow); }

  var els = {
    play: document.getElementById("podium-play"),
    stop: document.getElementById("podium-stop"),
    rec: document.getElementById("podium-rec"),
    time: document.getElementById("podium-time"),
    state: document.getElementById("podium-state"),
    stateText: document.getElementById("podium-state-text"),
    region: document.getElementById("podium-region")
  };

  function setState(name) {
    if (els.stateText.textContent === name) return;
    els.stateText.textContent = name;
    els.state.setAttribute("data-state", name);
    document.body.setAttribute("data-state", name);
  }

  // Region name in the status strip: the song that is playing, or why there isn't one. Offline keeps the last name (dimmed by CSS).
  function regionLabel(r) { return r.name || "Region " + r.id; }
  function markerLabel(m) { return m.name || "Marker " + m.id; }
  function setRegionName(text, idle) {
    if (els.region.textContent !== text) els.region.textContent = text;
    els.region.classList.toggle("idle", idle);
  }
  function showRegion(activeId, playstate) {
    if (!playstate) return setRegionName("Nothing playing", true);
    var r = currentRegions.filter(function (x) { return x.id === activeId; })[0];
    setRegionName(r ? regionLabel(r) : "No region here", !r);
  }
  // Play and Stop share one slot: exactly one is visible. Switching away from Stop abandons a half-finished hold.
  function setSlot(mode) {
    els.play.hidden = mode === "stop";
    els.stop.hidden = mode !== "stop";
    if (mode !== "stop") stopHold.cancel();
  }
  function setRecording(on) {
    els.rec.classList.toggle("recording", on);
    els.rec.textContent = on ? "REC" : "Rec";
  }

  var banner = document.getElementById("podium-banner");
  function setOffline(off) {
    document.body.classList.toggle("offline", off);
    banner.textContent = off ? "REAPER is unreachable. Showing the last known state. Retrying\u2026" : "";
  }

  poller.subscribe(function (e) {
    var t = e.ok ? reaper.parseTransport(e.text) : null;
    var live = !!t;
    conn.update(live);
    if (!live) {
      // One missed poll keeps the last state on screen but locks the cue buttons; two in a row declare offline.
      setCueEnabled(false);
      if (!conn.isOffline()) return;
      setOffline(true);
      if (!everLoaded) {
        // Never got a reply: don't leave "Loading…" up forever.
        setRegionName("Can\u2019t reach REAPER", true);
        showPanelMessage(regionsPanel, regionsView, "unreachable", "Regions can\u2019t load because REAPER isn\u2019t responding. This page keeps retrying.");
        showPanelMessage(markersPanel, markersView, "unreachable", "Markers can\u2019t load because REAPER isn\u2019t responding. This page keeps retrying.");
      }
      transportActive = false;
      els.play.disabled = els.stop.disabled = els.rec.disabled = true;
      setSlot("play"); // offline: disabled Play, same slot
      setRecording(false);
      hold.cancel();
      setState("offline");
      return;
    }
    setOffline(false);
    everLoaded = true;
    els.play.disabled = els.stop.disabled = false;
    setSlot(core.transportSlot(t.playstate));
    var recording = (t.playstate & 4) !== 0;
    els.rec.disabled = recording;
    setRecording(recording);
    if (els.rec.disabled) hold.cancel();
    transportActive = t.playstate !== 0;
    if (reaper.hasRegionList(e.text)) {
      currentRegions = reaper.parseRegions(e.text);
      renderRegions(currentRegions);
    } else showRegionsDiagnostic(e.text);
    if (reaper.hasMarkerList(e.text)) renderMarkers(reaper.parseMarkers(e.text));
    else if (reaper.hasRegionList(e.text)) renderMarkers([]); // reply format is fine but carries no marker block: treat as none
    else showPanelMessage(markersPanel, markersView, "diag", "Markers can\u2019t be shown because REAPER\u2019s reply had no marker list. Reload the page.");
    applyCueMode();
    setCueEnabled(conn.canCue());
    var activeId = core.activeRegionId(currentRegions, t.position, t.playstate);
    highlightRegion(activeId);
    showRegion(activeId, t.playstate);
    els.time.textContent = core.formatClock(t.position);
    setState(reaper.stateName(t.playstate));
  });

  // ▶ buttons: locked while offline/settling; while the transport is running they need a hold (a tap can't cut the song).
  function setCueEnabled(on) {
    document.querySelectorAll(".podium-go").forEach(function (b) { b.disabled = !on; });
  }
  function applyCueMode() {
    document.querySelectorAll(".podium-go").forEach(function (b) {
      b.classList.toggle("hold-mode", transportActive);
      b.setAttribute("aria-label", (transportActive ? "Hold to play from " : "Play from ") + b.getAttribute("data-label"));
    });
  }

  // Regions tab: one play button per row; the row itself is inert.
  var regionsPanel = document.getElementById("panel-regions");
  var currentRegions = [], highlightedId = null;
  function highlightRegion(id) {
    if (id === highlightedId) return;
    highlightedId = id;
    applyHighlight();
    if (id !== null) scrollActiveIntoView();
  }
  // Bring the playing row to the middle of the list when the song changes, unless the user is scrolling the list themselves.
  var lastUserScroll = 0;
  // Only input inside the list area counts; the sticky header, tab bar and page chrome are not list scrolling.
  var listArea = document.querySelector("main");
  ["wheel", "touchmove", "keydown"].forEach(function (n) {
    window.addEventListener(n, function (e) {
      if (e.target !== document.body && !listArea.contains(e.target)) return; // keys with nothing focused scroll the list
      lastUserScroll = Date.now();
    }, { passive: true });
  });
  function scrollActiveIntoView() {
    if (regionsPanel.hidden || Date.now() - lastUserScroll < 3000) return;
    var li = regionsPanel.querySelector("li.active");
    if (!li) return;
    var calm = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    li.scrollIntoView({ block: "center", behavior: calm ? "auto" : "smooth" });
  }
  function applyHighlight() {
    regionsPanel.querySelectorAll("li[data-id]").forEach(function (li) {
      var on = Number(li.getAttribute("data-id")) === highlightedId;
      li.classList.toggle("active", on);
      var go = li.querySelector(".podium-go"), now = li.querySelector(".podium-now");
      if (go) go.hidden = on;
      if (now) now.hidden = !on;
      if (on) li.setAttribute("aria-current", "true"); else li.removeAttribute("aria-current");
    });
  }
  // A panel message (plain text, optionally with REAPER's raw reply tucked into <details> for bug reports).
  function showPanelMessage(panel, view, key, message, raw) {
    var sig = key + ":" + message + (raw || "");
    if (sig === view.sig) return;
    view.sig = sig;
    panel.setAttribute("aria-busy", "false");
    panel.textContent = "";
    var p = document.createElement("p");
    p.className = "empty notice"; p.textContent = message;
    panel.appendChild(p);
    if (!raw) return;
    var d = document.createElement("details");
    d.className = "notice-details";
    var sum = document.createElement("summary");
    sum.textContent = "Show REAPER\u2019s reply";
    var pre = document.createElement("pre");
    pre.className = "diag"; pre.tabIndex = 0;
    pre.textContent = raw.slice(0, 1000);
    d.append(sum, pre);
    panel.appendChild(d);
  }
  // REAPER answered, but the reply has no region list: say what that means for the user, keep the raw text for bug reports.
  function showRegionsDiagnostic(text) {
    showPanelMessage(regionsPanel, regionsView, "diag",
      "Regions can\u2019t be shown. REAPER replied, but the reply had no region list. Reload the page; if it keeps happening, include the reply below when you report it.", text);
  }

  // Cue button behaviour. Stopped: one tap plays. Running: hold CUE_HOLD_MS (sweep fill) so a stray tap can't cut the song.
  // Either way a 1.5 s cooldown swallows repeat taps and the pressed button shows .pending.
  function fireCue(btn, time) {
    if (btn.disabled || !cueCooldown.tryFire()) return;
    btn.classList.add("pending");
    setTimeout(function () { btn.classList.remove("pending"); }, CUE_COOLDOWN_MS);
    sendCommand(reaper.seekPlayCommand(time));
  }
  function wireCue(btn, time) {
    var guarded = false;
    var cueHold = S.hold.createHold({
      holdMs: CUE_HOLD_MS,
      onStart: function () { btn.classList.add("holding"); },
      onCancel: function () { btn.classList.remove("holding"); },
      onComplete: function () { btn.classList.remove("holding"); fireCue(btn, time); }
    });
    btn.style.setProperty("--hold-ms", CUE_HOLD_MS + "ms");
    btn.addEventListener("pointerdown", function (e) {
      if (e.button !== 0 || btn.disabled) return;
      guarded = transportActive;
      if (guarded) cueHold.start();
    });
    ["pointerup", "pointerleave", "pointercancel", "blur"].forEach(function (n) {
      btn.addEventListener(n, function () { cueHold.cancel(); if (n !== "pointerup") guarded = false; });
    });
    btn.addEventListener("contextmenu", function (e) { e.preventDefault(); });
    btn.addEventListener("keydown", function (e) {
      if ((e.key === " " || e.key === "Enter") && transportActive) {
        e.preventDefault();
        if (!e.repeat && !btn.disabled) cueHold.start();
      }
    });
    btn.addEventListener("keyup", cueHold.cancel);
    btn.addEventListener("click", function () {
      btn.blur();
      if (guarded) { guarded = false; return; } // the press was a hold; the hold itself already fired (or was cut short)
      if (!transportActive) fireCue(btn, time);
    });
  }

  // Shared list renderer for both tabs: [play button][swatch][name][time]; the row itself is inert.
  // item = { id, name, time (seconds), color }. Skips DOM churn when nothing changed.
  function renderList(panel, view, items, emptyText) {
    var sig = JSON.stringify(items);
    if (sig === view.sig) return;
    view.sig = sig;
    panel.textContent = "";
    panel.setAttribute("aria-busy", "false");
    if (!items.length) {
      var p = document.createElement("p");
      p.className = "empty"; p.textContent = emptyText;
      panel.appendChild(p);
      return;
    }
    var ul = document.createElement("ul");
    ul.className = "podium-list";
    items.forEach(function (it) {
      var li = document.createElement("li");
      li.setAttribute("data-id", it.id);
      var btn = document.createElement("button");
      btn.type = "button"; btn.className = "podium-go"; btn.textContent = "\u25B6";
      btn.setAttribute("data-label", it.name);
      btn.setAttribute("aria-label", "Play from " + it.name);
      wireCue(btn, it.time);
      var nowEl = document.createElement("span");
      nowEl.className = "podium-now"; nowEl.hidden = true;
      nowEl.setAttribute("role", "img"); nowEl.setAttribute("aria-label", "Now playing");
      for (var b = 0; b < 3; b++) nowEl.appendChild(document.createElement("i"));
      var sw = document.createElement("span");
      sw.className = "podium-swatch";
      var css = reaper.colorToCss(it.color);
      if (css) sw.style.background = css;
      var name = document.createElement("span");
      name.className = "podium-name"; name.textContent = it.name;
      var time = document.createElement("span");
      time.className = "podium-start"; time.textContent = core.formatTime(it.time);
      li.append(btn, nowEl, sw, name, time);
      ul.appendChild(li);
    });
    panel.appendChild(ul);
  }

  var regionsView = { sig: null };
  function renderRegions(regions) {
    renderList(regionsPanel, regionsView, regions.map(function (r) {
      return { id: r.id, name: regionLabel(r), time: r.start, color: r.color };
    }), "No regions in this project. Regions you add in REAPER will appear here.");
    applyHighlight();
  }

  // Markers tab: same pattern, no highlight.
  var markersPanel = document.getElementById("panel-markers");
  var markersView = { sig: null };
  function renderMarkers(markers) {
    renderList(markersPanel, markersView, markers.map(function (m) {
      return { id: m.id, name: markerLabel(m), time: m.position, color: m.color };
    }), "No markers in this project. Markers you add in REAPER will appear here.");
  }

  // Rec: press-and-hold so a tap while scrolling/fiddling cannot start recording.
  function holdVisual(on) { els.rec.classList.toggle("holding", on); }
  var hold = S.hold.createHold({
    holdMs: HOLD_MS,
    onStart: function () { holdVisual(true); },
    onCancel: function () { holdVisual(false); },
    onComplete: function () { holdVisual(false); sendCommand("1013"); } // Transport: Record
  });
  els.rec.style.setProperty("--hold-ms", HOLD_MS + "ms");
  els.rec.addEventListener("pointerdown", function (e) { if (e.button === 0 && !els.rec.disabled) hold.start(); });
  ["pointerup", "pointerleave", "pointercancel", "blur"].forEach(function (n) { els.rec.addEventListener(n, hold.cancel); });
  els.rec.addEventListener("contextmenu", function (e) { e.preventDefault(); });
  els.rec.addEventListener("keydown", function (e) {
    if ((e.key === " " || e.key === "Enter") && !e.repeat && !els.rec.disabled) { e.preventDefault(); hold.start(); }
  });
  els.rec.addEventListener("keyup", hold.cancel);
  // No click handler on purpose: a plain click/tap must never start recording.

  function command(id) { return function () { sendCommand(id); }; }
  els.play.addEventListener("click", command("1007")); // Transport: Play
  // Stop: press-and-hold (STOP_HOLD_MS), so a stray tap can't kill a running song or take. No click handler on purpose.
  var stopHold = S.hold.createHold({
    holdMs: STOP_HOLD_MS,
    onStart: function () { els.stop.classList.add("holding"); },
    onCancel: function () { els.stop.classList.remove("holding"); },
    onComplete: function () { els.stop.classList.remove("holding"); sendCommand("1016"); } // Transport: Stop
  });
  els.stop.style.setProperty("--hold-ms", STOP_HOLD_MS + "ms");
  els.stop.addEventListener("pointerdown", function (e) { if (e.button === 0 && !els.stop.disabled) stopHold.start(); });
  ["pointerup", "pointerleave", "pointercancel", "blur"].forEach(function (n) { els.stop.addEventListener(n, stopHold.cancel); });
  els.stop.addEventListener("contextmenu", function (e) { e.preventDefault(); });
  els.stop.addEventListener("keydown", function (e) {
    if ((e.key === " " || e.key === "Enter") && !e.repeat && !els.stop.disabled) { e.preventDefault(); stopHold.start(); }
  });
  els.stop.addEventListener("keyup", stopHold.cancel);
  poller.start();

  var tabs = document.querySelectorAll("[role=tab]");
  function selectTab(tab, focus) {
    tabs.forEach(function (t) {
      var on = t === tab;
      t.setAttribute("aria-selected", String(on));
      t.tabIndex = on ? 0 : -1;
      var panel = document.getElementById(t.getAttribute("aria-controls"));
      if (panel) panel.hidden = !on;
    });
    if (focus) tab.focus();
  }
  tabs.forEach(function (tab, i) {
    tab.addEventListener("click", function () { selectTab(tab, false); });
    tab.addEventListener("keydown", function (e) {
      var n = tabs.length, to = null;
      if (e.key === "ArrowRight") to = (i + 1) % n;
      else if (e.key === "ArrowLeft") to = (i - 1 + n) % n;
      else if (e.key === "Home") to = 0;
      else if (e.key === "End") to = n - 1;
      if (to === null) return;
      e.preventDefault();
      selectTab(tabs[to], true);
    });
  });
})();
