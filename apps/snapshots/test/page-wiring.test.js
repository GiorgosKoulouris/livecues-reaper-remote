// The DOM files (snapshots.js, restore-ui.js, hold-key.js) are not loaded by node, so a call to a function the pure
// modules no longer export (a rename missed) would only fail in the browser. Every `<module>.<name>` they use must exist.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");

const JS = path.join(__dirname, "../www/lcrr/snapshots/js");
const MODULES = { core: "core.js", words: "words.js", restore: "restore.js" };
const DOM_FILES = ["snapshots.js", "restore-ui.js", "hold-key.js"];

test("every core, words and restore function the page calls is exported", () => {
  const missing = [];
  for (const [alias, file] of Object.entries(MODULES)) {
    const exported = require(path.join(JS, file));
    for (const page of DOM_FILES) {
      const src = fs.readFileSync(path.join(JS, page), "utf8");
      for (const m of src.matchAll(new RegExp("\\b" + alias + "\\.(\\w+)", "g"))) {
        if (m[1] === "js") continue; // a file name in a comment
        if (!(m[1] in exported)) missing.push(page + ": " + alias + "." + m[1]);
      }
    }
  }
  assert.deepStrictEqual(missing, []);
});
