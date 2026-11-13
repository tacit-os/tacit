// Open in terminal and Ctrl+Shift+T in Pinax start the terminal chosen in Settings > Default apps, in the folder
// (modules/ii/files/FilesWindow.qml): the window's own terminalHere() runs under node with apps.terminal set to kitty,
// and what it hands Quickshell.execDetached runs under bash with a pretend kitty that writes where it started, in a
// folder whose name has a space, a quote and a '$'. No terminal is started.
import { spawnSync } from "child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Pinax opens the chosen terminal in the folder (FilesWindow.qml)");
const src = read("modules/ii/files/FilesWindow.qml");
check("no action starts foot by name", !/execDetached\(\["foot"/.test(src), (src.match(/.*execDetached\(\["foot".*/g) ?? []).map(l => l.trim()).join(" | "));

const dir = mkdtempSync(join(tmpdir(), "tacit-terminal-"));
try {
  const bin = join(dir, "bin"), folder = join(dir, `it's a "dir" $HOME`);
  mkdirSync(bin);
  mkdirSync(folder);
  for (const name of ["kitty", "foot"]) {
    // as foot does, -D <folder> starts it there
    writeFileSync(join(bin, name), `#!/bin/sh\n[ "$1" = -D ] && cd "$2"\nprintf '%s\\n%s\\n' "${name}" "$PWD" > "${join(dir, "started")}"\n`);
    chmodSync(join(bin, name), 0o755);
  }
  const ran = [];
  const win = { folder };
  const scope = { win, Quickshell: { execDetached: argv => ran.push(argv) }, Config: { options: { apps: { terminal: "kitty" } } } };
  for (const name of ["terminalHere", "terminalAt"]) {
    const f = qmlFunction(src, name);
    if (f) win[name] = inScope(scope, f.params, f.body);
  }
  win.terminalHere();
  const r = ran.length ? spawnSync(ran[0][0], ran[0].slice(1), { encoding: "utf8", env: { PATH: `${bin}:/usr/bin:/bin`, HOME: dir } }) : null;
  let started = "";
  try { started = readFileSync(join(dir, "started"), "utf8"); } catch (e) {}
  check("Ctrl+Shift+T starts kitty, the terminal chosen", started.split("\n")[0] === "kitty", started ? `started ${started.split("\n")[0]}` : `nothing started (${r?.stderr ?? "no command"})`);
  check("in the folder shown", started.split("\n")[1] === folder, `in ${JSON.stringify(started.split("\n")[1])}`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}
done();
