// A notch question whose Claude process the out-of-memory killer ended (services/Claude.qml): agent-host says so with
// ended "oom" on the exit (main.rs), and the file's own two onExited handlers, the sheet's and the Live Activity's, run
// under node. Both must say it as Praxis does (Conversation's oomWords), not as a plain crash.
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a notch session the out-of-memory killer ended (Claude.qml)");
const src = read("services/Claude.qml");
const sheetExit = qmlFunction(src, "onExited", 0), activityExit = qmlFunction(src, "onExited", 1);
const praxis = JSON.parse(qmlProperty(read("modules/claude/Conversation.qml"), "oomWords"));

function notch() {
  const ended = [];
  const root = { sid: "s1", activityId: "s1", seenSeq: 4, watchingId: "s1", sentWatches: {}, earlier: [], items: [], liveDone: true,
    pendingQ: "summarise this log", error: "", clearLive() {}, oomWords: JSON.parse(qmlProperty(src, "oomWords") ?? "null") };
  const scope = { root, host: { request() {} }, IslandController: { endActivity: (status, text, extra) => ended.push({ status, text, extra }) } };
  const sheet = inScope(scope, sheetExit.params, sheetExit.body), activity = inScope(scope, activityExit.params, activityExit.body);
  return { root, ended, exit(reason, stderr, end) { sheet("s1", reason, stderr, end); activity("s1", reason, stderr, end); } };
}

// shell-praxis review r1 [4]: the exit's `ended` was not taken, so the notch said "Claude stopped." where Praxis said
// the session ran out of memory: a crash (killed by a signal) and a scope systemd stopped (it can exit 0)
for (const reason of ["crashed", "exited"]) {
  const n = notch();
  n.exit(reason, ["Killed"], "oom");
  check(`an out-of-memory end ("${reason}"): the sheet and the Live Activity say it in Praxis's words, in the failure tone`,
    n.root.error === praxis && n.ended.length === 1 && n.ended[0].status === "fail" && n.ended[0].text === praxis && n.root.pendingQ === "",
    `sheet ${JSON.stringify(n.root.error)}, activity ${JSON.stringify(n.ended)}, Praxis ${JSON.stringify(praxis)}`);
}
{
  const n = notch();
  n.exit("crashed", ["Error: socket hang up"], "");
  check("a crash with no out-of-memory kill still says Claude stopped and its last line",
    n.root.error === "Claude stopped: Error: socket hang up" && n.ended[0]?.text === "Claude stopped: Error: socket hang up", `${JSON.stringify(n.root.error)}, ${JSON.stringify(n.ended)}`);
}
done();
