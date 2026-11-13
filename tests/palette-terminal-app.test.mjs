// A Terminal=true app opened from the palette (services/PaletteSearch.qml appEntries): the row's own execute, and its
// action's, run under node, and the command they hand Quickshell run by bash with a pretend terminal that prints the
// words it was given. Each of the entry's Exec words should reach the terminal as its own word after -e.
import { execFileSync } from "child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("services/PaletteSearch.qml");
const quote = qmlFunction(read("modules/common/functions/StringUtils.qml"), "shellSingleQuoteEscape");

console.log("== a terminal app from the palette (services/PaletteSearch.qml)");
const bin = mkdtempSync(join(tmpdir(), "tacit-term-"));
try {
  writeFileSync(join(bin, "term"), "#!/bin/bash\nprintf '%s\\n' \"$@\"\n");
  chmodSync(join(bin, "term"), 0o755);
  const ran = [];
  const root = { sectionTitles: { apps: "Applications" } };
  const scope = { root, resultComp: { createObject: (parent, props) => props }, PaletteFrecency: { record() {} },
    AppScope: { launch() { ran.push("unconfined launch"); } }, Quickshell: { execDetached: argv => ran.push(argv) },
    Config: { options: { apps: { terminal: join(bin, "term") } } }, Translation: { tr: s => s },
    StringUtils: { shellSingleQuoteEscape: inScope({}, quote.params, quote.body) } };
  const helper = qmlFunction(src, "inTerminal");
  if (helper) root.inTerminal = inScope(scope, helper.params, helper.body);
  const entry = { id: "htop", name: "Htop", runInTerminal: true, command: ["htop", "--tree"],
    actions: [{ name: "Files", runInTerminal: true, command: ["sh", "-c", "cd ~ && ranger"] }] };
  root.appMatchesOnce = [entry];
  const row = inScope(scope, "", qmlProperty(src, "appEntries").slice(1, -1))()[0];
  row.execute();
  row.actions[0].execute();
  const words = ran.map(argv => (Array.isArray(argv) ? execFileSync(argv[0], argv.slice(1), { encoding: "utf8" }).split("\n").slice(0, -1) : argv));
  check("Exec=htop --tree: the terminal is given -e htop --tree", JSON.stringify(words[0]) === JSON.stringify(["-e", "htop", "--tree"]),
    JSON.stringify(words[0]));
  check("an action's Exec=sh -c 'cd ~ && ranger': -e sh -c 'cd ~ && ranger'",
    JSON.stringify(words[1]) === JSON.stringify(["-e", "sh", "-c", "cd ~ && ranger"]), JSON.stringify(words[1]));
} finally {
  rmSync(bin, { recursive: true, force: true });
}
done();
