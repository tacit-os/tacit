// The focused terminal's folder and command for a question asked from the notch (bin/focus-folder, bin/claude-context),
// run under sh with a pretend hyprctl whose focused window is a pretend terminal started here: a process with one
// shell, then one with two (kitty's tabs, ghostty's or footclient's windows: one process, a shell per tab or window),
// each shell in its own folder and running a program.
import { spawn, spawnSync } from "child_process";
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== the focused terminal's folder and command (bin/focus-folder, bin/claude-context)");
const tmp = realpathSync(mkdtempSync(join(tmpdir(), "tacit-focus-folder-")));
const kids = pid => spawnSync("pgrep", ["-P", String(pid)], { encoding: "utf8" }).stdout.split("\n").filter(Boolean);
const terminals = [];
// a terminal process whose shells run in these folders, each with a program in front; back once all of them run
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
  const bin = join(tmp, "bin"), home = join(tmp, "home"), app = join(tmp, "app"), notes = join(tmp, "notes");
  for (const d of [bin, home, app, notes]) mkdirSync(d);
  writeFileSync(join(bin, "hyprctl"), '#!/bin/sh\nprintf \'{"class":"kitty","title":"kitty","pid":%s}\' "$TERMINAL"\n');
  chmodSync(join(bin, "hyprctl"), 0o755);
  copyFileSync(join(tree, "bin/focus-folder"), join(bin, "focus-folder"));   // claude-context asks it for the folder
  chmodSync(join(bin, "focus-folder"), 0o755);
  const env = t => ({ PATH: `${bin}:${process.env.PATH}`, HOME: home, TACIT_BIN: bin, TACIT_SHELL: tmp, XDG_DATA_DIRS: join(tmp, "none"),
    TERMINAL: String(t) });
  const folder = t => spawnSync("sh", [join(tree, "bin/focus-folder")], { encoding: "utf8", env: env(t) }).stdout.trim();
  const context = t => { try { return JSON.parse(spawnSync("sh", [join(tree, "bin/claude-context")], { encoding: "utf8", env: env(t) }).stdout); } catch { return {}; } };

  const one = terminal([app]);
  check("one shell: its folder", folder(one) === app, folder(one));
  check("one shell: what it runs", context(one).cmd === "sleep", JSON.stringify(context(one)));

  const two = terminal([app, notes]);
  check("two shells in one terminal process: no folder is guessed (home)", folder(two) === home, `gave ${folder(two)}`);
  const c = context(two);
  check("two shells in one terminal process: no command or folder of the first shell goes to Claude", c.cmd === "" && c.cwd === home,
    JSON.stringify(c));
} finally {
  for (const t of terminals) try { process.kill(-t.pid, "SIGKILL"); } catch {}
  rmSync(tmp, { recursive: true, force: true });
}
done();
