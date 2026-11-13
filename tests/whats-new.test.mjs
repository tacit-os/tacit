// The notch's "What's new" (services/Updates.qml openNotes()) opens Settings > About at its Updates group, where the
// notes are, below the machine's rows. openNotes() runs under node and its command under bash with a pretend
// settings-open; then tacit-settings.qml's showPage() and the About page's own anchor handling, with the page laid out
// as a 780 px window has it.
import { execFileSync } from "child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== What's new opens About at its notes (services/Updates.qml, tacit-settings.qml)");
const bin = mkdtempSync(join(tmpdir(), "tacit-whats-new-"));
let asked = "";
try {
  writeFileSync(join(bin, "settings-open"), `#!/bin/bash\nprintf '%s' "$*" > "${join(bin, "asked")}"\n`);
  chmodSync(join(bin, "settings-open"), 0o755);
  const f = qmlFunction(read("services/Updates.qml"), "openNotes");
  let argv = null;
  inScope({ Quickshell: { execDetached: a => { argv = a; } } }, f.params, f.body)();
  execFileSync(argv[0], argv.slice(1), { env: { ...process.env, TACIT_BIN: bin } });
  asked = readFileSync(join(bin, "asked"), "utf8");
} finally {
  rmSync(bin, { recursive: true, force: true });
}
check("What's new asks for About's updates", asked === "about:updates", `settings-open ${asked}`);
{
  const app = read("tacit-settings.qml");
  const aboutSrc = app.slice(app.indexOf("id: aboutPage"));
  const take = qmlFunction(aboutSrc, "takeAnchor"), show = qmlFunction(aboutSrc, "showUpdates");
  const root = { categories: [{ key: "look" }, { key: "about" }], current: 0, pageAnchor: "", anchorAsked() {} };
  const pageScroll = { contentY: 0, contentHeight: 1800, height: 740 };
  const about = {};
  const scope = { root, about, pageScroll, pageColumn: { y: 0 }, updatesGroup: { mapToItem: () => ({ y: 820 }) },
    toUpdatesEnd: { restart() {} }, Qt: { callLater: fn => fn() } };
  if (take) about.takeAnchor = inScope(scope, take.params, take.body);
  if (show) about.showUpdates = inScope(scope, show.params, show.body);
  const sp = qmlFunction(app, "showPage");
  inScope({ root, SettingsApp: { keyFor: k => k } }, sp.params, sp.body)(asked);
  about.takeAnchor?.(root.pageAnchor);
  check("About opens with its Updates group at the top of the page, and the link is spent",
    root.current === 1 && pageScroll.contentY === 800 && root.pageAnchor === "", `page ${root.categories[root.current].key}, scrolled to ${pageScroll.contentY}, anchor "${root.pageAnchor}"`);
}
done();
