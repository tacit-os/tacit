// Pinax's deep search (FilesWindow.qml, fdProc): the window's own fd command, run by bash on a project folder in a home
// of its own, with a .gitignore, an .ignore and a ~/.fdignore that each leave something out. Every file whose name
// matches is found; node_modules and .git, which the search leaves out on purpose, stay out.
import { execFileSync } from "child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Pinax's deep search finds files a .gitignore leaves out (FilesWindow.qml)");
const src = read("modules/ii/files/FilesWindow.qml");
const esc = qmlFunction(read("modules/common/functions/StringUtils.qml"), "shellSingleQuoteEscape");
const StringUtils = { shellSingleQuoteEscape: inScope({}, esc.params, esc.body) };
const at = src.indexOf("command: {", src.indexOf("id: fdProc")) + "command: ".length;
const command = folder => inScope({ win: { searchPlan: null, searchQuery: "report", folder }, StringUtils }, "", src.slice(at + 1, matchBrace(src, at)))();

const tmp = mkdtempSync(join(tmpdir(), "tacit-search-"));
try {
  const home = join(tmp, "home"), project = join(home, "project");
  const put = (path, text = "") => { mkdirSync(join(path, ".."), { recursive: true }); writeFileSync(path, text); };
  put(join(project, "src/report.md"));
  put(join(project, "reports/report.pdf"));               // *.pdf in .gitignore: generated reports
  put(join(project, "dist/report.js"));                   // dist/ in .gitignore
  put(join(project, "drafts/report.odt"));                // drafts/ in .ignore
  put(join(project, "old/report.txt"));                   // old/ in ~/.fdignore
  put(join(project, "node_modules/report/index.js"));     // left out on purpose
  put(join(project, ".gitignore"), "*.pdf\ndist/\n");
  put(join(project, ".ignore"), "drafts/\n");
  put(join(home, ".fdignore"), "old/\n");
  execFileSync("git", ["init", "-q", project]);
  const [cmd, ...args] = command(project);
  const out = execFileSync(cmd, args, { env: { PATH: process.env.PATH, HOME: home, XDG_CONFIG_HOME: join(home, ".config") }, encoding: "utf8" });
  const found = out.split("\n").map(l => l.trim().replace(/^\.\//, "").replace(/\/$/, "")).filter(Boolean).sort();
  const want = ["dist/report.js", "drafts/report.odt", "old/report.txt", "reports/report.pdf", "src/report.md"];
  for (const f of want)
    check(`"report" finds ${f}`, found.includes(f), `found ${JSON.stringify(found)}`);
  check("node_modules stays out", !found.some(f => f.startsWith("node_modules")), `found ${JSON.stringify(found)}`);
} catch (e) {
  check("fd ran", false, String(e.message ?? e).split("\n")[0]);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
