// A Thyris still running after tacit-thyris was updated under it: Updates.qml's check (its own command under bash, against
// a process of this test's own named browser whose program was then deleted, as pacman replaces it) says "Thyris was
// updated · reopen it to finish" once in the notch and holds the quiet mark at rest (IslandController's ambientGlyph
// binding) until that Thyris is gone.
import { spawn, spawnSync } from "child_process";
import { chmodSync, copyFileSync, mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Thyris was updated · reopen it to finish (Updates.qml, IslandController.qml)");
const updates = read("services/Updates.qml");
const at = updates.indexOf("id: thyrisStaleProc");
const start = at < 0 ? -1 : updates.lastIndexOf("Process {", at);
const proc = start < 0 ? "" : updates.slice(start, matchBrace(updates, start + "Process ".length) + 1);
check("the shell has a check for it", proc !== "");

const tmp = mkdtempSync(join(tmpdir(), "tacit-thyris-stale-"));
const program = join(tmp, "browser");
let child = null;
const sleep = ms => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
try {
  // the check's own command, for a Thyris at `path`
  const cmd = proc ? inScope({}, "", `return (${readExpression(proc, proc.indexOf("command:") + "command:".length).expr});`)() : [];
  check("it looks for Thyris's own program", cmd[cmd.length - 1] === "/usr/lib/tacit/thyris/browser", cmd[cmd.length - 1]);
  const stale = path => proc ? spawnSync(cmd[0], cmd.slice(1, -1).concat([path])).status === 0 : null;
  copyFileSync("/usr/bin/sleep", program);
  chmodSync(program, 0o755);
  check("no Thyris running from it: nothing to finish", stale(program) === false);
  child = spawn(program, ["60"], { stdio: "ignore" });
  sleep(300);
  check("a Thyris running from the program on disk: nothing to finish", stale(program) === false);
  rmSync(program);
  check("its program replaced under it (deleted): reopening it finishes the update", stale(program) === true);

  // its answer: the line once, the mark while it holds
  const said = [];
  const root = { thyrisStale: false, say: (name, data) => said.push([name, data]) };
  const exited = proc ? inScope({ root }, "", `return (${readExpression(proc, proc.indexOf("onExited:") + "onExited:".length).expr});`)() : () => {};
  exited(0, 0);
  exited(0, 0);
  check("the notch says it once, in the owner's words", said.length === 1 && said[0][1].text === "Thyris was updated · reopen it to finish"
    && said[0][1].icon === "restart_alt" && root.thyrisStale === true, JSON.stringify(said));
  child.kill();
  child = null;
  sleep(200);
  check("once that Thyris has gone it is over", stale(program) === false);
  exited(1, 0);
  check("(and the mark goes)", root.thyrisStale === false);
  exited(0, 0);
  check("a later update under a Thyris says it again", said.length === 2);
} finally {
  if (child)
    child.kill();
  rmSync(tmp, { recursive: true, force: true });
}
check("it is read with every look of Updates (and so after every pacman transaction)", /function refresh\(\)\s*\{[^}]*thyrisStaleProc\.running = true/.test(updates));
check("and every 15 s while it holds, so the mark goes soon after Thyris is reopened",
  /Timer\s*\{\s*interval: 15000\s*repeat: true\s*running: root\.thyrisStale\s*onTriggered: thyrisStaleProc\.running = true/.test(updates));

// ---- the notch at rest
const ambient = qmlProperty(read("services/IslandController.qml"), "ambientGlyph");
const glyph = (restartDue, thyrisStale) => inScope({
  root: { chargerFault: false, micLive: false, prReviews: [], activityAmbient: false, diskPct: 10, memoryFull: false, workUnsaved: false },
  AgentSessions: { waiting: false, justDone: false, sessions: [] }, Claude: { waiting: false }, Notifications: { silent: false, unread: 0 },
  Battery: { available: false, isCharging: false }, Vpn: { connected: false }, Idle: { inhibit: false }, Audio: { sink: { name: "alsa" }, source: null },
  DropShelf: { items: [] }, Hyprsunset: { temperatureActive: false }, Updates: { restartDue, thyrisStale }, Camera: { live: false },
}, "", ambient.replace(/^\{|\}$/g, ""))();
check("the notch keeps the restart's quiet mark at rest until then", glyph(false, true) === "restart_alt" && glyph(false, false) === "",
  `${JSON.stringify(glyph(false, true))}, without it ${JSON.stringify(glyph(false, false))}`);
done();
