// A live update of the shell's own files (services/ShellUpdate.qml, shell.qml, session/pacman): Quickshell 0.3.2
// reloads at the first watched file that changed, at once, so pacman's extraction reloaded the shell halfway through,
// on a tree half old and half new. tacit-shell's pacman hooks mark the transaction and the shell waits for its end.
// The hooks' script runs under sh with its mark in a scratch folder; the hooks are read as pacman reads them; and
// ShellUpdate's own handlers run under node with shell.qml's binding of Quickshell.watchFiles, a pretend pacman lock and
// a Quickshell that counts its reloads, through an update, one that fails, and a start after one that failed.
import { spawnSync } from "child_process";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the shell reloads once after pacman, not halfway through (ShellUpdate.qml, session/pacman)");
// a file this tree may not have (the hooks and the service are new): "" then, so its checks fail rather than the test
const maybe = path => { try { return read(path); } catch { return ""; } };
// the hooks' script, with its mark in a scratch folder and a sleep that does not wait
const tmp = mkdtempSync(join(tmpdir(), "tacit-shell-update-"));
let marks = [];
try {
  const script = join(tmp, "tacit-shell-update"), mark = join(tmp, "mark");
  writeFileSync(script, maybe("session/pacman/tacit-shell-update").replaceAll("/run/tacit-shell-update", mark));
  writeFileSync(join(tmp, "sleep"), '#!/bin/sh\necho "slept $1" >> "$LOG"\n');
  chmodSync(join(tmp, "sleep"), 0o755);
  const log = join(tmp, "log");
  for (const step of ["start", "end"]) {
    const r = spawnSync("sh", [script, step], { env: { PATH: `${tmp}:/usr/bin:/bin`, LOG: log }, encoding: "utf8" });
    marks.push({ step, rc: r.status, mark: existsSync(mark) ? readFileSync(mark, "utf8").trim() : "", waited: existsSync(log) ? readFileSync(log, "utf8").trim() : "" });
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
check("start marks \"installing\" and gives the shell a moment before pacman goes on", marks[0]?.rc === 0 && marks[0].mark === "installing" && /^slept [1-9]/.test(marks[0].waited),
  JSON.stringify(marks[0]));
check("end marks \"done\"", marks[1]?.rc === 0 && marks[1].mark === "done", JSON.stringify(marks[1]));

// the hooks, as pacman reads them: a transaction that changes the shell's files, before it and after it
const hook = name => {
  const text = maybe(`session/pacman/${name}`);
  const all = key => [...text.matchAll(new RegExp(`^${key}\\s*=\\s*(.+)$`, "gm"))].map(m => m[1].trim());
  return { type: all("Type"), ops: all("Operation"), target: all("Target"), when: all("When"), exec: all("Exec") };
};
for (const [name, when, step] of [["tacit-shell-update-start.hook", "PreTransaction", "start"], ["tacit-shell-update-end.hook", "PostTransaction", "end"]]) {
  const h = hook(name);
  check(`${name}: ${when}, on an install or upgrade of the shell's files, runs the script's ${step}`,
    h.type.join() === "Path" && h.ops.includes("Install") && h.ops.includes("Upgrade") && h.target.join() === "usr/share/tacit/shell/*"
      && h.when.join() === when && h.exec.join() === `/usr/share/libalpm/scripts/tacit-shell-update ${step}`, JSON.stringify(h));
}

// the shell: ShellUpdate's handlers, and the watch shell.qml binds to it
const src = maybe("services/ShellUpdate.qml");
const shell = read("shell.qml");
const watchAt = shell.search(/property:\s*"watchFiles";\s*value:/);
const watchExpr = watchAt < 0 ? "true" : readExpression(shell, shell.indexOf("value:", watchAt) + "value:".length).expr.replace(/\s*\}\s*$/, "");
const exitedAt = src.indexOf("onExited:", src.indexOf("id: lockProc"));
const loadedAt = src.indexOf("onLoaded:", src.indexOf("id: mark"));
function shellWith(lock) {
  const state = { lock, reloads: 0, files: "old" };
  const root = { holding: false };
  const lockProc = {};
  const scope = { root, lockProc, Quickshell: { reload: () => { state.reloads++; } } };
  for (const name of ["heard", "release"]) {
    const f = qmlFunction(src, name);
    root[name] = f ? inScope(scope, f.params.replace(/:\s*\w+/g, ""), f.body) : () => {};
  }
  const exited = exitedAt < 0 ? () => {} : inScope(scope, "", `return (${readExpression(src, exitedAt + "onExited:".length).expr});`)();
  // the lock check runs at once here: test -e on pacman's lock
  Object.defineProperty(lockProc, "running", { set: v => { if (v) exited(state.lock ? 0 : 1, 0); }, get: () => false });
  const markText = { text: "" };
  const loaded = loadedAt < 0 ? () => {} : () => inScope({ ...scope, mark: { text: () => markText.text } }, "", readExpression(src, loadedAt + "onLoaded:".length).expr)();
  const watching = () => inScope({ ShellUpdate: root }, "", `return (${watchExpr});`)();
  // what Quickshell does with a watched file that changed: a reload at once, while it is watching
  const fileChanged = () => { if (watching()) state.reloads++; };
  return { state, root, mark: t => { markText.text = t; loaded(); }, watching, fileChanged, timer: () => { if (root.holding) lockProc.running = true; } };
}
{
  const s = shellWith(true);
  s.mark("installing");
  check("pacman starts on the shell's files: the shell stops watching them", s.root.holding === true && s.watching() === false, `holding ${s.root.holding}, watching ${s.watching()}`);
  for (let i = 0; i < 40; i++) s.fileChanged();         // the extraction, file after file
  check("so no file reloads it halfway through", s.state.reloads === 0, `${s.state.reloads} reloads`);
  s.timer();                                            // a lock check while pacman still runs
  s.mark("done");
  check("once pacman is done, it reloads once, with every file in, and watches again", s.state.reloads === 1 && s.watching() === true,
    `${s.state.reloads} reloads, watching ${s.watching()}`);
  s.mark("done");
  check("and not again", s.state.reloads === 1, `${s.state.reloads} reloads`);
}
{
  const s = shellWith(true);
  s.mark("installing");
  s.fileChanged();
  s.state.lock = false;                                 // the transaction failed: no end hook, pacman let go of its lock
  s.timer();
  check("a transaction that fails without its end still ends the wait, with one reload", s.state.reloads === 1 && s.watching() === true,
    `${s.state.reloads} reloads, watching ${s.watching()}`);
}
{
  const s = shellWith(false);
  s.mark("installing");                                 // the start after it: the mark of the failed one is still there
  check("a mark left by a transaction that failed holds nothing and reloads nothing", s.state.reloads === 0 && s.watching() === true,
    `${s.state.reloads} reloads, watching ${s.watching()}`);
}
done();
