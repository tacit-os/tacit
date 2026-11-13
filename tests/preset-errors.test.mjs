// A preset save, overwrite or import that fails (services/Presets.qml, the Presets rows of Settings' Profile page):
// presets.sh exits 1 with its reason on stderr, and Settings showed nothing, so a failed Save or Import looked like one
// that did nothing. presets.sh runs under bash in a home of its own (a config that is not valid JSON, a zip whose JSON
// is cut short); what it said is handed to Presets' own onExited handlers, and the page's line is read with its bindings.
import { execFileSync, spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== a failed preset save or import is said under the preset rows (Presets.qml, Profile.qml)");
const src = read("services/Presets.qml");
const exited = id => { const at = src.indexOf("onExited:", src.indexOf(`id: ${id}`)); return readExpression(src, at + "onExited:".length).expr; };
const report = qmlFunction(src, "report");
function presets() {
  const root = { error: "", refresh() {}, refreshOnline() {}, refreshImported() {} };
  if (report) root.report = inScope({ root }, report.params, report.body);
  return root;
}
// a process's end as Presets hears it: its exit and what it said on stderr
function end(root, id, said, code) {
  const scope = { root, Translation: { tr: s => s }, saveSaid: { text: said }, overwriteSaid: { text: said }, importSaid: { text: said } };
  // "(code, status) => { ... }" is called with the exit; a plain statement or block runs as it is
  const e = exited(id);
  if (/^\(?[\w\s,]*\)?\s*=>/.test(e)) inScope(scope, "", `return (${e});`)()(code, 0);
  else inScope(scope, "", e.replace(/^\{|\}$/g, ""))();
}
const prof = read("modules/ii/settings/pages/Profile.qml");
const lineAt = prof.indexOf("visible: Presets.error");
const shown = root => {
  if (lineAt < 0) return "";
  const visible = inScope({ Presets: root }, "", `return (${readExpression(prof, lineAt + "visible:".length).expr});`)();
  const textAt = prof.indexOf("text:", lineAt);
  return visible ? String(inScope({ Presets: root }, "", `return (${readExpression(prof, textAt + "text:".length).expr});`)()) : "";
};

const home = mkdtempSync(join(tmpdir(), "tacit-preset-errors-"));
try {
  const dir = join(home, ".config/illogical-impulse");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "config.json"), '{"appearance": {"transparency": ');
  const sh = (...args) => spawnSync("bash", [join(tree, "scripts/presets.sh"), ...args], { encoding: "utf8", env: { PATH: process.env.PATH, HOME: home } });
  const saved = sh("--save", "mine", "my look");
  const p = presets();
  end(p, "saveProc", saved.stderr, saved.status);
  check("a Save that could not read the config says so under the rows", saved.status !== 0 && /^Could not read .*config\.json$/.test(shown(p)),
    `exit ${saved.status}, the page shows "${shown(p)}"`);

  const q = presets();
  end(q, "overwriteProc", saved.stderr, saved.status);
  check("so does an Overwrite", /^Could not read/.test(shown(q)), `"${shown(q)}"`);

  const zip = join(home, "bad.zip");
  execFileSync("python3", ["-I", "-c", "import sys, zipfile; z = zipfile.ZipFile(sys.argv[1], 'w'); z.writestr('mine/mine.json', sys.argv[2]); z.close()", zip, '{"a": ']);
  const imported = sh("--import-zip", zip);
  const r = presets();
  end(r, "importZipProc", imported.stderr, imported.status);
  check("an Import of a zip whose JSON is cut short says so", imported.status !== 0 && /^The preset in the zip is not valid JSON/.test(shown(r)), `"${shown(r)}"`);

  writeFileSync(join(dir, "config.json"), JSON.stringify({ appearance: { transparency: { enable: true } } }));
  const ok = sh("--save", "mine");
  end(p, "saveProc", ok.stderr, ok.status);
  check("and the line goes once a save goes through", ok.status === 0 && shown(p) === "", `exit ${ok.status}, "${shown(p)}"`);
} finally {
  rmSync(home, { recursive: true, force: true });
}
done();
