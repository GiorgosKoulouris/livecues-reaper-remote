// Home: connection chip wiring. The app buttons are plain links in lcrr.html.
(function () {
  "use strict";
  var S = LCRR.shared, status = LCRR.home.status;
  var conn = S.guard.createConnection({ failuresToOffline: 2, settleMs: 0 });
  var poller = S.poll.createPoller({ intervalMs: 2000 });
  var el = document.getElementById("home-conn");
  var text = document.getElementById("home-conn-text");
  var seen = false;

  poller.subscribe(function (e) {
    var live = e.ok && !!S.reaper.parseTransport(e.text);
    conn.update(live);
    if (live) seen = true;
    var c = status.chip(live, conn.isOffline(), seen);
    if (!c || el.getAttribute("data-state") === c.state) return;
    el.setAttribute("data-state", c.state);
    text.textContent = c.text;
  });
  poller.start();
})();
