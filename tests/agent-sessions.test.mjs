// Terminal Claude sessions in the notch (services/AgentSessions.qml): the hooks' update() and activity() and the
// roster's own handler run under node, on a clock the test moves. A permission prompt that was answered, and a turn
// stopped with Esc, must not stay "Needs you" or "working" until the next prompt.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== terminal sessions' state in the notch (AgentSessions.qml)");
const src = read("services/AgentSessions.qml");

function sessions() {
  const t = { now: 1_000_000 };
  const root = { all: [], justDone: false, focused: () => false, inStage: () => false };
  const scope = { root, Date: { now: () => t.now }, doneTimer: { restart() {} },
    IslandController: { refreshDirty() {}, request() {} }, Claude: { owns: () => false } };
  for (const name of ["update", "activity"]) {
    const f = qmlFunction(src, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  const at = src.indexOf("onStreamFinished:", src.indexOf("id: rosterProc"));
  const block = readExpression(src, at + "onStreamFinished:".length).expr;
  const roster = inScope(scope, "text", block.slice(1, -1));
  const state = id => root.all.find(s => s.id === id)?.state;
  return { t, root, roster: rows => roster(JSON.stringify(rows)), state };
}
const row = (id, status) => ({ kind: "interactive", sessionId: id, status, name: "" });

{
  const s = sessions();
  s.root.update("a", "working", "0x1", "/p");
  s.root.activity("a", "running make");          // PreToolUse of the tool that asks
  s.t.now += 200; s.root.update("a", "waiting", "", "");
  s.t.now += 100; s.root.activity("a", "running make");   // that tool's line landing late
  check("a prompt on screen stays \"Needs you\" when its tool's line lands after it", s.state("a") === "waiting");
  s.t.now += 6000; s.root.activity("a", "editing Island.qml");   // answered: the next tool runs
  check("after the prompt is answered, the next tool call shows the session working", s.state("a") === "working");
}
// shell-praxis review r1 [3]: a background or parallel agent's tool call comes under the parent's session id while the
// session's own prompt waits in the terminal, and it took the "Needs you" away
{
  const s = sessions();
  s.root.update("f", "working", "0x6", "/p");
  s.root.activity("f", "running rm -rf build");
  s.t.now += 200; s.root.update("f", "waiting", "", "");
  s.t.now += 3000; s.root.activity("f", "reading notes.md", "a7f3c2");   // a sub-agent reads on
  const sub = s.state("f"), line = s.root.all[0].activity;
  s.t.now += 3000; s.root.activity("f", "running rm -rf build", "");      // answered: the main thread's tool runs
  const f = /function agentActivity\(([^)]*)\)[^{]*\{([^}]*)\}/.exec(src);
  const passed = [];
  if (f) inScope({ root: { activity: (...a) => passed.push(a) } }, f[1].replace(/:\s*\w+/g, ""), f[2])("f", "a7f3c2", "reading notes.md");
  check("a sub-agent's tool call keeps a waiting session \"Needs you\" (its line still shows); the main thread's next call ends the wait",
    sub === "waiting" && line === "reading notes.md" && s.state("f") === "working" && JSON.stringify(passed) === '[["f","reading notes.md","a7f3c2"]]',
    `after the sub-agent's call ${sub} (line "${line}"), after the main thread's ${s.state("f")}, the IPC passed ${JSON.stringify(passed)}`);
}
{
  const s = sessions();
  s.root.update("b", "working", "0x2", "/p");
  s.root.activity("b", "running make");
  s.t.now += 5000; s.roster([row("b", "idle")]);   // a poll from before the prompt, or a pause
  check("a session not busy for a moment keeps working", s.state("b") === "working");
  s.t.now += 20000; s.roster([row("b", "idle")]); // Esc: no Stop hook, the roster says idle
  check("a turn stopped with Esc reads idle once the roster says so", s.state("b") === "idle");
}
{
  const s = sessions();
  s.root.update("c", "waiting", "0x3", "/p");
  s.t.now += 60000; s.roster([row("c", "idle")]);
  s.root.update("d", "done", "0x4", "/p");
  s.t.now += 60000; s.roster([row("c", "idle"), row("d", "idle")]);
  check("the roster leaves \"Needs you\" and \"Done\" as the hooks said", s.state("c") === "waiting" && s.state("d") === "done");
  s.root.update("e", "working", "0x5", "/p");
  s.t.now += 60000; s.roster([row("c", "idle"), row("d", "idle"), row("e", "busy")]);
  check("a busy session keeps working however long since its last tool", s.state("e") === "working");
}
done();
