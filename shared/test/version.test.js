const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const ver = require("../www/lcrr/shared/js/version.js");

const repo = path.join(__dirname, "..", "..");

function fakeDoc(hasFooter) {
  const inner = { children: [], appendChild(c) { this.children.push(c); } };
  return {
    inner,
    querySelector: (sel) => (sel === ".lcrr-footer-inner" && hasFooter ? inner : null),
    createElement: () => ({ className: "", textContent: "" })
  };
}

test("version.js carries the suite version from the root package.json", () => {
  const pkg = JSON.parse(fs.readFileSync(path.join(repo, "package.json"), "utf8"));
  assert.strictEqual(ver.version, pkg.version,
    "bump shared/www/lcrr/shared/js/version.js together with package.json");
});

test("mount puts 'v<version>' in the footer", () => {
  const d = fakeDoc(true);
  ver.mount(d);
  assert.strictEqual(d.inner.children.length, 1);
  assert.strictEqual(d.inner.children[0].className, "lcrr-version");
  assert.strictEqual(d.inner.children[0].textContent, "v" + ver.version);
});

test("mount is a no-op on a page without the footer (home)", () => {
  const d = fakeDoc(false);
  assert.doesNotThrow(() => ver.mount(d));
  assert.strictEqual(d.inner.children.length, 0);
});

test("every app page with the suite footer loads version.js", () => {
  const apps = path.join(repo, "apps");
  let pages = 0;
  fs.readdirSync(apps).forEach((a) => {
    const www = path.join(apps, a, "www");
    if (!fs.existsSync(www)) return;
    fs.readdirSync(www).filter((f) => /^lcrr-.*\.html$/.test(f)).forEach((f) => {
      const html = fs.readFileSync(path.join(www, f), "utf8");
      if (!html.includes('class="lcrr-footer"')) return;
      pages++;
      assert.ok(html.includes('src="lcrr/shared/js/version.js"'), f + " does not load version.js");
    });
  });
  assert.ok(pages >= 5, "expected the app pages, found " + pages);
});

test("IEM Mix and IEM Setup link to each other from their bars", () => {
  const www = (a, f) => fs.readFileSync(path.join(repo, "apps", a, "www", f), "utf8");
  const bar = (html) => html.slice(html.indexOf("<header"), html.indexOf("</header>"));
  assert.ok(/class="lcrr-sibling" href="lcrr-iem\.html"/.test(bar(www("iemmix", "lcrr-iemmix.html"))));
  assert.ok(/class="lcrr-sibling" href="lcrr-iemmix\.html"/.test(bar(www("iem", "lcrr-iem.html"))));
});
