// The tree's QML and JavaScript run in Qt's own script engine, not node: a built-in that Qt lacks throws there while
// every node test of the same code passes. 1.2.15 shipped two (Array.flatMap: Super+/ listed no keys, Settings' screen
// changes wrote nothing), so the methods this Qt lacks are asked of Qt itself and none may be called in the tree.
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync, existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== built-ins Qt's script engine lacks are not called (QML and JS)");
const wanted = {
  "Array.prototype": ["flatMap", "flat", "at", "findLast", "findLastIndex", "toSorted", "toReversed", "toSpliced", "with"],
  "String.prototype": ["replaceAll", "at", "matchAll", "trimStart", "trimEnd"],
  "Object": ["fromEntries", "hasOwn", "groupBy"],
  "Promise": ["allSettled", "any"],
};
const qml = ["/usr/lib/qt6/bin/qml", "qml6", "qml"].find(q => q.startsWith("/") ? existsSync(q) : spawnSync("which", [q]).status === 0);
const dir = mkdtempSync(join(tmpdir(), "qt-builtins-"));
writeFileSync(join(dir, "probe.qml"), `import QtQuick
Item { Component.onCompleted: {
    const wanted = ${JSON.stringify(wanted)};
    const missing = [];
    for (const owner in wanted) {
        const o = owner === "Array.prototype" ? Array.prototype : owner === "String.prototype" ? String.prototype : owner === "Object" ? Object : Promise;
        for (const n of wanted[owner]) if (typeof o[n] !== "function") missing.push(owner + "." + n);
    }
    if (typeof structuredClone !== "function") missing.push("structuredClone");
    console.warn("MISSING " + JSON.stringify(missing));
    Qt.quit();
} }
`);
const run = spawnSync(qml, [join(dir, "probe.qml")], { encoding: "utf8", timeout: 20000,
  env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_FORCE_STDERR_LOGGING: "1" } });
rmSync(dir, { recursive: true, force: true });
const line = `${run.stdout}${run.stderr}`.match(/MISSING (\[.*\])/);
const missing = line ? JSON.parse(line[1]) : null;
check("Qt says which built-ins it lacks", missing !== null, `${run.error ?? ""}${run.stderr ?? ""}`.slice(0, 300));

// the tree's own functions of the same names (a Code document's replaceAll, Scrim's at()), by file and receiver
const own = [/\b(cur|doc)\.replaceAll\(/, /\bsc\.at\(/, /function replaceAll\(/];
// the tree's files by git, or by find in a plain copy (TACIT_TREE pointed at a git archive)
const listed = spawnSync("git", ["-C", tree, "ls-files", "*.qml", "*.js"], { encoding: "utf8" });
const files = (listed.status === 0 ? listed.stdout
  : spawnSync("find", [".", "-path", "./.git", "-prune", "-o", "-type", "f", "(", "-name", "*.qml", "-o", "-name", "*.js", ")", "-print"],
    { cwd: tree, encoding: "utf8" }).stdout.replace(/^\.\//gm, ""))
  .split("\n").filter(f => f && !f.startsWith("tests/"));
const found = [];
for (const f of files) {
  const text = readFileSync(join(tree, f), "utf8");
  text.split("\n").forEach((l, i) => {
    if (/^\s*(\/\/|\*)/.test(l) || own.some(r => r.test(l))) return;
    for (const m of missing ?? []) {
      const name = m.split(".").pop();
      const call = m.startsWith("Object.") || m.startsWith("Promise.") ? new RegExp(`\\b${m.replace(".", "\\.")}\\(`)
        : m === "structuredClone" ? /\bstructuredClone\(/ : new RegExp(`\\.${name}\\(`);
      if (call.test(l)) found.push(`${f}:${i + 1}: ${m}: ${l.trim().slice(0, 90)}`);
    }
  });
}
check(`no QML or JS calls one (${(missing ?? []).length} missing in this Qt)`, missing !== null && found.length === 0, "\n" + found.join("\n"));
done();
