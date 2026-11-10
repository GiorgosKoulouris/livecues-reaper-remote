// LCRR shared: the suite version, shown in the footer so users and bug reports can name the installed release.
// Keep `version` equal to the root package.json (shared/test/version.test.js fails otherwise).
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else {
    var L = root.LCRR = root.LCRR || {}; (L.shared = L.shared || {}).version = api;
    if (root.document) api.mount(root.document);
  }
})(this, function () {
  "use strict";
  var version = "1.1.0-beta2";

  // Adds "v<version>" at the right of the suite footer. A page without the footer (home) is left alone.
  function mount(doc) {
    var inner = doc.querySelector(".lcrr-footer-inner");
    if (!inner) return;
    var el = doc.createElement("span");
    el.className = "lcrr-version";
    el.textContent = "v" + version;
    inner.appendChild(el);
  }

  return { version: version, mount: mount };
});
