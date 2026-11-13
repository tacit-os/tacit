// The notch's conversation after agent-host restarts mid-turn (services/Claude.qml): the new host holds no session, and
// the old Claude Code finishes the answer in the transcript on its own. attach(), load(), the follow timer and took() are
// the file's own, run under node with a pretend host and clock; the answer written after the reconnect must come up.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the notch's conversation after agent-host restarts (Claude.qml)");
const src = read("services/Claude.qml");

// the follow timer: the Timer whose trigger reads the transcript again, if the file has one
const timerAt = src.indexOf("onTriggered: root.reread()");
const timerBody = timerAt < 0 ? "" : (open => src.slice(open + 1, matchBrace(src, open)))(src.indexOf("{", src.lastIndexOf("Timer {", timerAt)));
const timerRunning = (timerBody.match(/\brunning:\s*([^\n]+)/) ?? [])[1];

const QUESTION = "why is the build red?", ANSWER = "The linker test fails on a stale object; fixed and rebuilt.";
function notch() {
  const clock = { now: 1_800_000_000_000 };
  const transcript = [
    { role: "user", kind: "text", text: QUESTION, ts: 1 },
    { role: "assistant", kind: "text", text: "Let me look at the log.", ts: 2 },
    { role: "assistant", kind: "tool", tool: "Bash", summary: "make check", ts: 3 },
  ];
  const host = { connected: true, live: {}, request(obj, cb) {   // restarted: it runs nothing, the transcript is on disk
    if (obj.op === "list") cb({ ev: "sessions", sessions: [] });
    else if (obj.op === "transcript") cb({ ev: "transcript", items: transcript.map(i => ({ ...i })) });
  } };
  const root = { home: "/home/a", cwd: "/home/a", current: { id: "s1", cwd: "/home/a" }, continuing: true, pendingQ: QUESTION,
    earlier: [], items: [], liveText: "", liveDone: false, shown: 0, budget: 0, error: "", note: "", seenSeq: -1, replaying: false,
    watchingId: "", sentWatches: {}, loadingId: "", loadGen: 0, loadRetried: false, followUntil: 0, chips: [], reading: true,
    holdChoice: true, pendingText: "", browsers: {}, starting: false, loaded() {}, decide() {}, send() {} };
  Object.defineProperty(root, "sid", { get: () => (root.continuing && root.current ? root.current.id ?? "" : "") });
  Object.defineProperty(root, "session", { get: () => (root.sid.length ? host.live[root.sid] ?? null : null) });
  const scope = { root, host, Date: { now: () => clock.now }, loadTimeout: { restart() {}, stop() {} }, GlobalStates: { screenLocked: false } };
  for (const name of ["attach", "load", "echoed", "strip", "clearLive", "unwatchAll", "turnOpen", "followTranscript", "reread", "took"]) {
    const f = qmlFunction(src, name);
    if (f) root[name] = inScope(scope, f.params, f.body);
  }
  const running = () => !!timerRunning && inScope(scope, "", `return (${timerRunning});`)() === true;
  // the follow timer's ticks, 3 s apart, for `seconds`
  const wait = seconds => {
    for (let t = 0; t < seconds; t += 3) {
      if (running()) root.reread();
      clock.now += 3000;
    }
  };
  const answered = () => root.earlier.some(i => i.role === "assistant" && i.text === ANSWER);
  return { root, transcript, wait, running, answered };
}

{
  const n = notch();
  n.root.attach();                                       // the socket answers again: onConnectedChanged
  n.wait(6);
  n.transcript.push({ role: "assistant", kind: "text", text: ANSWER, ts: 4 });   // the old process finishes
  n.wait(6);
  check("the answer the old process writes after the reconnect comes up in the notch", n.answered(),
    `the conversation ends with ${JSON.stringify(n.root.earlier.at(-1))}`);
  check("the question is drawn from the transcript, not left pending", n.root.pendingQ === "", JSON.stringify(n.root.pendingQ));
  check("and once answered it is no longer read again", !n.running());
}
{
  const n = notch();
  n.root.attach();
  n.wait(90);                                            // a long turn: the minute runs out with nothing new
  n.transcript.push({ role: "assistant", kind: "text", text: ANSWER, ts: 4 });
  check("after a minute with nothing new the transcript is left alone", !n.running());
  n.root.took("{}");                                     // the sheet opens again
  check("and opening the sheet reads it again, answer and all", n.answered(), `the conversation ends with ${JSON.stringify(n.root.earlier.at(-1))}`);
}
{
  const n = notch();
  n.transcript.push({ role: "assistant", kind: "text", text: ANSWER, ts: 4 });   // finished before the reconnect
  n.root.attach();
  check("a conversation whose last turn is answered is read once, not followed", n.answered() && !n.running());
}
done();
