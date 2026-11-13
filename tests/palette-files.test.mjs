// The palette's file search (services/PaletteFiles.qml): the pattern fd is given for a typed word, from the file's own
// fold(), kin and patternFor(), against names with accents. The word typed exactly, or without its accents, must find the
// file; fd does the finding, so it is asked too, over a folder of those names.
import { spawnSync } from "child_process";
import { mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the palette's file search (PaletteFiles.qml)");
const src = read("services/PaletteFiles.qml");
const root = {};
const scope = { root };
for (const name of ["fold", "patternFor"]) {
  const f = qmlFunction(src, name);
  root[name] = inScope(scope, f.params, f.body);
}
const kin = qmlProperty(src, "kin");
if (kin) root.kin = inScope(scope, "", kin.startsWith("{") ? kin.slice(1, -1) : `return (${kin});`)();

// [name on disk, what is typed]: exactly, and without the accents
const names = [["česky", "česky"], ["zażółć", "zażółć"], ["şeker", "şeker"], ["ışık", "ışık"], ["mặt", "mặt"], ["tiếng", "tiếng"],
  ["Отчёт", "отчёт"], ["česky", "cesky"], ["tiếng", "tieng"], ["Affärsplan", "affarsplan"]];
const dir = mkdtempSync(join(tmpdir(), "palette-files-"));
const fdPattern = typed => "^" + dir.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "/.*" + root.patternFor(root.fold(typed));
const missed = names.filter(([name, typed]) => !new RegExp(fdPattern(typed), "iu").test(`${dir}/${name}.pdf`));
check("a name with accents is matched by the pattern for the word typed exactly, and without its accents",
  missed.length === 0, `no match for ${JSON.stringify(missed)}`);
check("a name the word is not in still is not", !new RegExp(fdPattern("cesky"), "iu").test(`${dir}/czech.pdf`));

if (spawnSync("fd", ["--version"]).status === 0) {
  for (const [name] of names) writeFileSync(join(dir, `${name}.pdf`), "");
  const unfound = names.filter(([name, typed]) => {
    const r = spawnSync("fd", ["--type", "f", "--color", "never", "--ignore-case", "--full-path", "--", fdPattern(typed), dir], { encoding: "utf8" });
    return !r.stdout.split("\n").includes(join(dir, `${name}.pdf`));
  });
  check("fd finds each of them", unfound.length === 0, `fd found nothing for ${JSON.stringify(unfound)}`);
} else {
  console.log("  (fd is not installed here: the patterns were checked with node's regular expressions only)");
}
rmSync(dir, { recursive: true });
done();
