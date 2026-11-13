// A Files job whose runner dies while the shell runs (services/Jobs.qml): the check that turns a report still saying
// "running" into a failure when its job.sh is gone, run under bash on a scratch jobs folder, as the startup sweep runs it
// and as the timer that runs while a job is running does. A live runner and a finished report are left alone.
import { execFileSync, spawn, spawnSync } from "child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a Files job whose runner died (Jobs.qml)");
const src = read("services/Jobs.qml");
const sq = qmlFunction(read("modules/common/functions/StringUtils.qml"), "shellSingleQuoteEscape");
const StringUtils = { shellSingleQuoteEscape: inScope({}, sq.params, sq.body) };

const dir = mkdtempSync(join(tmpdir(), "jobs-dead-runner-"));
const report = (id, state, pid) => writeFileSync(join(dir, `${id}.json`), JSON.stringify({ id, op: "copy", dest: "/home/a/Stick", state, total: 10,
  done: 4, bytes: 1e9, bytesDone: 4e8, pid, current: "film.mkv", error: "", started: 1, ended: null, results: [], undo: null }));
const stateOf = id => JSON.parse(readFileSync(join(dir, `${id}.json`), "utf8"));
const deadPid = () => spawnSync("true").pid;   // ran and exited: nothing has that pid now
// a runner still at it: a bash whose command line names job.sh and its job, as setsid bash job.sh <id> <op> has
const live = spawn("bash", ["-c", "sleep 30; :", "job.sh", "live1", "copy"], { stdio: "ignore" });
const reset = () => { report("dead1", "running", deadPid()); report("live1", "running", live.pid); report("done1", "done", deadPid()); };

const root = { jobsDir: dir, activeJobs: [] };
const scope = { root, StringUtils };
const reapExpr = qmlProperty(src, "reapScript");
if (reapExpr !== null) root.reapScript = inScope(scope, "", `return (${reapExpr});`)();

// the timer whose trigger runs the check while jobs run, if there is one
const timerAt = src.indexOf("reaper.running = true");
const timer = timerAt < 0 ? null : src.slice(src.lastIndexOf("Timer {", timerAt), matchBrace(src, src.lastIndexOf("Timer {", timerAt) + 6) + 1);
function tick(jobs) {
  root.activeJobs = jobs.map(id => ({ id, kind: "job" }));
  const running = inScope(scope, "", `return (${readExpression(timer, timer.indexOf("running:") + 8).expr});`)();
  if (!running) return false;
  const reaper = {};
  const on = timer.indexOf("onTriggered:") + "onTriggered:".length;
  const open = timer.indexOf("{", on);
  inScope({ ...scope, reaper }, "", timer.slice(open + 1, matchBrace(timer, open)))();
  execFileSync(reaper.command[0], reaper.command.slice(1), { stdio: "pipe" });
  return true;
}

{
  reset();
  const ran = timer !== null && tick(["dead1", "live1"]);
  check("while jobs run, a check runs on a timer", ran, timer ? "its timer does not run with jobs running" : "there is no such timer");
  const d = stateOf("dead1");
  check("and a copy whose runner died turns failed, with why", d.state === "failed" && d.error === "Files stopped before it finished" && d.current === "",
    `it still says ${d.state}`);
  check("a copy whose runner is at it stays running", stateOf("live1").state === "running", stateOf("live1").state);
  check("with no job running the timer is still", timer !== null && !tick([]));
}
{
  reset();
  const at = src.indexOf("id: sweep");
  const cmd = inScope(scope, "", `return (${readExpression(src, src.indexOf("command:", at) + 8).expr});`)();
  const listed = execFileSync(cmd[0], cmd.slice(1), { encoding: "utf8" }).trim().split("\n").sort();
  check("the startup sweep still turns the dead one failed and leaves the others",
    stateOf("dead1").state === "failed" && stateOf("live1").state === "running" && stateOf("done1").state === "done",
    `dead1 ${stateOf("dead1").state}, live1 ${stateOf("live1").state}, done1 ${stateOf("done1").state}`);
  check("and lists every report to watch", JSON.stringify(listed) === JSON.stringify(["dead1", "done1", "live1"]), JSON.stringify(listed));
  const before = readFileSync(join(dir, "done1.json"), "utf8");
  if (timer) tick(["done1"]);
  check("a report that already ended is not written again", readFileSync(join(dir, "done1.json"), "utf8") === before);
}
live.kill();
rmSync(dir, { recursive: true, force: true });
done();
