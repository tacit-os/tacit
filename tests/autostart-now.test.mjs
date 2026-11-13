// Startup apps (scripts/hyprland/autostart.py): the login run (shell.qml's autostartProc) and Settings' run button
// (modules/common/widgets/AutostartApps.qml) with the argv each file gives, in a session folder of its own and a
// pretend hyprctl first on PATH that notes each app it is asked to start (no Hyprland is reached: the environment has no
// instance signature).
import { execFileSync } from "child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== startup apps at login and from Settings' run button (autostart.py)");
const scope = { Directories: { scriptPath: join(tree, "scripts") } };
const argv = (src, from, key) => inScope(scope, "", `return (${readExpression(src, src.indexOf(key, src.indexOf(from)) + key.length).expr});`)();
const login = argv(read("shell.qml"), "id: autostartProc", "command:");
const button = (() => {
  const src = read("modules/common/widgets/AutostartApps.qml");
  const open = src.lastIndexOf("[", src.indexOf("hyprland/autostart.py"));   // the run button's execDetached argv
  return inScope(scope, "", `return (${src.slice(open, matchBrace(src, open) + 1)});`)();
})();

const dir = mkdtempSync(join(tmpdir(), "tacit-autostart-"));
try {
  const bin = join(dir, "bin"), run = join(dir, "run"), log = join(dir, "started");
  mkdirSync(bin); mkdirSync(run); mkdirSync(join(dir, ".config", "illogical-impulse"), { recursive: true });
  writeFileSync(join(dir, ".config", "illogical-impulse", "config.json"), JSON.stringify({
    hyprland: { autostartApps: { enable: true, apps: [{ cmd: "foot", workspace: 2, delay: 0 }] } } }));
  writeFileSync(join(bin, "hyprctl"), `#!/bin/bash\necho "$*" >> "${log}"\n`);
  chmodSync(join(bin, "hyprctl"), 0o755);
  writeFileSync(log, "");
  const env = { PATH: `${bin}:${process.env.PATH}`, HOME: dir, XDG_RUNTIME_DIR: run };
  const started = () => readFileSync(log, "utf8").split("\n").filter(Boolean).length;
  const go = a => execFileSync(a[0], a.slice(1), { env });

  go(login);
  check("the login run starts the app", started() === 1, `${started()} started`);
  go(login);
  check("a second login run (a shell reload) starts nothing more", started() === 1, `${started()} started`);
  go(button);
  check("Settings' run button starts it again after the login run", started() === 2, `${started()} started`);
  go(button);
  check("and again at the next press", started() === 3, `${started()} started`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}

done();
