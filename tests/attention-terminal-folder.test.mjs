// The focused terminal's folder as the shell reads it (services/Attention.qml cwdFor, which Files uses to open where
// your terminal is): it took the terminal process's first child as the shell, so with kitty's tabs, ghostty's windows or
// footclient's (one process, a shell each) the first shell's folder was given as the focused one's, the rule
// later-scripts-1 [3] fixed in bin/focus-folder. cwdFor's own Process command runs under bash on a pretend terminal
// started here: a process with one shell, then one with two, each in its own folder with a program running.
import { spawn, spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the focused terminal's folder for Files (Attention.qml cwdFor)");
const src = read("services/Attention.qml");
const at = src.indexOf("command:", src.indexOf("id: cwdProc"));
const command = pid => inScope({ proc: { pid } }, "", `return (${readExpression(src, at + "command:".length).expr});`)();
const tmp = realpathSync(mkdtempSync(join(tmpdir(), "tacit-attention-cwd-")));
const kids = pid => spawnSync("pgrep", ["-P", String(pid)], { encoding: "utf8" }).stdout.split("\n").filter(Boolean);
const terminals = [];
function terminal(folders) {
  const shells = folders.map(f => `(cd '${f}' && exec sh -c 'sleep 60 & wait') &`).join(" ");
  const t = spawn("sh", ["-c", `${shells} wait`], { detached: true, stdio: "ignore" });
  terminals.push(t);
  for (let i = 0; i < 200; i++) {
    const shs = kids(t.pid);
    if (shs.length === folders.length && shs.every(s => kids(s).length === 1)) break;
    spawnSync("sleep", ["0.02"]);
  }
  return t.pid;
}
try {
  const app = join(tmp, "app"), notes = join(tmp, "notes");
  for (const d of [app, notes]) mkdirSync(d);
  const folder = pid => { const [cmd, ...args] = command(pid); return spawnSync(cmd, args, { encoding: "utf8" }).stdout.trim(); };
  const one = terminal([app]);
  check("one shell: its folder", folder(one) === app, `gave "${folder(one)}"`);
  const two = terminal([app, notes]);
  check("two shells in one terminal process: no folder is guessed", folder(two) === "", `gave "${folder(two)}"`);
} finally {
  for (const t of terminals) try { process.kill(-t.pid, "SIGKILL"); } catch {}
  rmSync(tmp, { recursive: true, force: true });
}
done();
