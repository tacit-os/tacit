// An update started from the bar's Updates widget outlives the widget (modules/ii/bar/UpdatesCount.qml): the widget's
// Process command, read from the file, runs as Quickshell 0.3.2 runs one (process.cpp: QProcess with its argv), and is
// then killed as ~Process kills it when the Process goes, on a reload or when the bar is rebuilt (QProcess::kill, a
// SIGKILL to that one process). The pretend update is a command that takes a moment and then leaves a mark.
import { spawn } from "child_process";
import { existsSync, mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== an update started from the bar when the shell reloads (UpdatesCount.qml)");
const src = read("modules/ii/bar/UpdatesCount.qml");
const at = src.indexOf("command:", src.indexOf("id: updateProc"));
const command = update => inScope({ Config: { options: { apps: { update } } } }, "", `return (${readExpression(src, at + "command:".length).expr});`)();
const sleep = ms => new Promise(r => setTimeout(r, ms));
// the command run as a QProcess runs it: { exit, killed } once it ends (killed after killAfter ms, as on a reload)
function run(update, killAfter = null) {
  return new Promise(resolve => {
    const [cmd, ...args] = command(update);
    const p = spawn(cmd, args, { stdio: ["pipe", "pipe", "pipe"] });
    if (killAfter !== null) setTimeout(() => p.kill("SIGKILL"), killAfter);
    p.on("exit", (code, signal) => resolve({ exit: code, signal }));
  });
}

const tmp = mkdtempSync(join(tmpdir(), "tacit-update-"));
try {
  const mark = join(tmp, "updated");
  await run(`sleep 0.6; touch '${mark}'`, 200);
  await sleep(1200);
  check("the update goes on to its end when the widget's Process is killed", existsSync(mark), "it was killed with the widget");
  const missing = await run("tacit-no-such-terminal --hold pacman -Syu");
  check("a command that is not there still ends with 127, which the widget reports as not started", missing.exit === 127, `exit ${missing.exit}`);
  const ran = await run("exit 0");
  check("one that ran ends with its own exit, which the widget follows with the count", ran.exit === 0, `exit ${ran.exit}`);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
