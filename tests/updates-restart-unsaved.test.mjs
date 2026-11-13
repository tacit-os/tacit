// Restart for an update with uncommitted work (services/Updates.qml, shell.qml): restartNow(), the shell's answer and
// SessionWarnings' onChecked run under node as Settings' process and as the shell's. Settings' own IslandController has
// looked at no folder when Restart is pressed there, so it asks the shell (`qs ipc call updates unsaved`, run here under
// bash with a pretend qs) and warns "Uncommitted work" as the notch's Restart does; and outside the shell nothing is
// handed to an IslandController, which there has no notch and would start a second copy of the notch's watchers.
import { spawnSync } from "child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Restart with uncommitted work, from Settings and from the notch (services/Updates.qml, shell.qml)");
const src = read("services/Updates.qml");
const procExited = id => {
  const at = src.indexOf(`id: ${id}`);
  if (at < 0) return null;
  const open = src.lastIndexOf("Process {", at);
  const proc = src.slice(open, matchBrace(src, open + "Process ".length) + 1);
  return { proc, exited: readExpression(proc, proc.indexOf("onExited:") + "onExited:".length).expr };
};
const checkedFn = qmlFunction(src.slice(src.indexOf("target: SessionWarnings")), "onChecked");

// one process's Updates: what it asked, warned and handed to the notch
function press(says, shellSays, ownUnsaved) {
  const asked = [], notch = [];
  let refreshed = 0, went = 0;
  const root = { says, restarting: false, guarding: false, restartWarning: "", restartFailed: "", tonightFailed: "", shellUnsaved: false };
  const unsaved = procExited("unsavedProc");
  const scope = {
    root, Directories: { shellFile: "/usr/share/tacit/shell/shell.qml" },
    SessionWarnings: { refresh: () => refreshed++, agentWorking: false, agentTitles: [], packageManagerRunning: false, downloadRunning: false },
    IslandController: { workUnsaved: ownUnsaved, request: (n, d) => notch.push(d.text) },
    unsavedProc: { set running(v) { if (v) asked.push(unsaved ? inScope({ Directories: scope.Directories }, "", `return ${readExpression(unsaved.proc, unsaved.proc.indexOf("command:") + 8).expr};`)() : []); } },
    unsavedOut: { text: shellSays },
    disarmTimer: { restart() {}, stop() {} }, restartProc: { set running(v) { if (v) went++; } },
  };
  for (const f of ["restartNow", "go"]) { const fn = qmlFunction(src, f); root[f] = inScope(scope, fn.params, fn.body); }
  root.restartNow();
  if (asked.length && unsaved) inScope(scope, "", `return (${unsaved.exited});`)()(0, 0);
  if (refreshed) inScope(scope, checkedFn.params, checkedFn.body)();
  return { asked, refreshed, went, warning: root.restartWarning, notch };
}

// Settings: its own IslandController knows of nothing; the shell's has seen the work
const settings = press(false, "true\n", false);
check("Settings' Restart asks the shell whether work is uncommitted",
  settings.asked.length === 1 && settings.asked[0].join(" ") === "timeout 3 qs -p /usr/share/tacit/shell/shell.qml ipc call updates unsaved", JSON.stringify(settings.asked));
check("then reads the session's own warnings", settings.refreshed === 1, `${settings.refreshed} reads`);
check("and stops at 'Uncommitted work' instead of restarting", settings.went === 0 && settings.warning === "Uncommitted work", `restarted ${settings.went}, warning "${settings.warning}"`);
check("handing nothing to an IslandController of its own", settings.notch.length === 0, JSON.stringify(settings.notch));
const clean = press(false, "false\n", false);
check("with nothing uncommitted it restarts", clean.went === 1 && clean.warning === "", `restarted ${clean.went}, warning "${clean.warning}"`);
check("and hands its 'Getting ready to restart' to no IslandController of its own", clean.notch.length === 0, JSON.stringify(clean.notch));
const noShell = press(false, "", false);
check("with no shell answering it restarts, as before", noShell.went === 1, `restarted ${noShell.went}`);

// the shell: its own IslandController's look, and the notch says it
const shell = press(true, "", true);
check("the notch's Restart reads its own look and asks nobody", shell.asked.length === 0 && shell.refreshed === 1 && shell.warning === "Uncommitted work",
  `asked ${shell.asked.length}, warning "${shell.warning}"`);
check("and the notch says it", shell.notch.join() === "Uncommitted work", JSON.stringify(shell.notch));

// the shell answers over IPC with its IslandController's look; the command run under bash with a pretend qs
const shellSrc = read("shell.qml");
const ipcAt = shellSrc.indexOf('target: "updates"');
const ipc = ipcAt < 0 ? null : qmlFunction(shellSrc.slice(ipcAt), "unsaved");
check("the shell answers `updates unsaved` with its IslandController's look",
  !!ipc && inScope({ IslandController: { workUnsaved: true } }, "", ipc.body)() === true && inScope({ IslandController: { workUnsaved: false } }, "", ipc.body)() === false,
  ipc ? ipc.body.trim() : "shell.qml has no updates IPC");
if (settings.asked.length) {
  const bin = mkdtempSync(join(tmpdir(), "tacit-unsaved-"));
  try {
    writeFileSync(join(bin, "qs"), '#!/bin/bash\n[ "$*" = "-p /usr/share/tacit/shell/shell.qml ipc call updates unsaved" ] && echo true\n');
    chmodSync(join(bin, "qs"), 0o755);
    const [cmd, ...args] = settings.asked[0];
    const r = spawnSync(cmd, args, { encoding: "utf8", env: { PATH: `${bin}:${process.env.PATH}` } });
    check("the asking command reaches the shell's handler", r.status === 0 && r.stdout.trim() === "true", `${r.status} ${r.stdout}${r.stderr}`);
  } finally {
    rmSync(bin, { recursive: true, force: true });
  }
}
done();
