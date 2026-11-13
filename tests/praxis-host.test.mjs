// Praxis after agent-host restarts mid-turn (modules/claude/Host.qml, Conversation.qml): the old process finishes the
// turn on its own, known only from the roster (a leftover), and its last rows were read only while one was listed.
// The handlers' own code is run under node.
import { inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const hostSrc = read("modules/claude/Host.qml"), convSrc = read("modules/claude/Conversation.qml"), appSrc = read("claude.qml");

console.log("Praxis after agent-host restarts (modules/claude/Host.qml, Conversation.qml)");

// the socket's onConnectedChanged, as the new host answers: does it read the roster at once?
{
  const at = hostSrc.indexOf("onConnectedChanged: {"), open = hostSrc.indexOf("{", at);
  const body = hostSrc.slice(open + 1, matchBrace(hostSrc, open));
  const connect = rosterOn => {
    const runs = [];
    const scope = { connected: true, retry: { tries: 4, stop() {}, start() {} }, host: { roster: rosterOn, sayHello() {} },
      roster: { set running(v) { runs.push(v); }, get running() { return runs[runs.length - 1] ?? false; } } };
    inScope(scope, "", body)();
    return runs;
  };
  const app = connect(true), notch = connect(false);
  check("the socket answering starts the roster at once, in the app (the notch reads no roster)",
    app[app.length - 1] === true && app.includes(false) && !notch.includes(true),
    `the app's roster was set ${JSON.stringify(app)}, the notch's ${JSON.stringify(notch)}`);
}

// the leftover going: the open session is read once more, as followSoon does after the host's own exit
{
  const m = /\bonLeftoverChanged:\s*/.exec(convSrc);
  const expr = m ? readExpression(convSrc, m.index + m[0].length).expr : "";
  const follows = leftover => {
    let n = 0;
    if (expr) inScope({ conv: { leftover }, followSoon: { restart() { n++; } } }, "", expr.startsWith("{") ? expr.slice(1, -1) : `${expr};`)();
    return n;
  };
  check("the open session's leftover gone, its transcript is followed once more; while it runs, the follow timer does it",
    follows(null) === 1 && follows({ status: "busy", pid: 790 }) === 0,
    expr ? `followed ${follows(null)} times when it went, ${follows({ status: "busy", pid: 790 })} while busy` : "no onLeftoverChanged");
}

// [7] a message queued behind the turn when the socket drops: the drop ends the turn as Praxis sees it, and the queue
// handed its head to a connection that was gone, which refused it, and forgot it
const sendQueued = qmlFunction(convSrc, "sendQueued");
function queue({ connected, answered, accepts }) {
  const sent = [];
  const conv = { turnOpen: false, locked: false, sendingNow: false, testLog() {},
    queued: [{ text: "and run the tests", images: [], files: [] }, { text: "then commit", images: [], files: [] }],
    host: { connected, rosterAnswered: answered },
    send(text) { sent.push(text); return accepts; } };
  inScope({ conv }, sendQueued.params, sendQueued.body)();
  return { sent, left: conv.queued.map(q => q.text) };
}
{
  const dropped = queue({ connected: false, answered: false, accepts: false });
  const refused = queue({ connected: true, answered: true, accepts: false });
  check("with the socket gone the queue keeps its messages, and one send() refuses goes back first in line",
    dropped.left.length === 2 && !dropped.sent.length && JSON.stringify(refused.left) === JSON.stringify(["and run the tests", "then commit"]),
    `dropped: sent ${JSON.stringify(dropped.sent)}, left ${JSON.stringify(dropped.left)}; refused: left ${JSON.stringify(refused.left)}`);
  const early = queue({ connected: true, answered: false, accepts: true });
  const ready = queue({ connected: true, answered: true, accepts: true });
  check("back, the queue waits for the roster's answer, then sends its first message",
    !early.sent.length && JSON.stringify(ready.sent) === '["and run the tests"]' && JSON.stringify(ready.left) === '["then commit"]',
    `before the roster sent ${JSON.stringify(early.sent)}, after ${JSON.stringify(ready.sent)} leaving ${JSON.stringify(ready.left)}`);
}

// the roster's answer: whole (the script got to its end) it is known what runs, leftovers included; cut short it is not
{
  const at = hostSrc.indexOf("onStreamFinished: {"), open = hostSrc.indexOf("{", at);
  const body = hostSrc.slice(open + 1, matchBrace(hostSrc, open)).replace(/\bthis\.text\b/g, "__text");
  const answer = text => {
    const host = { live: {}, terminals: {}, leftovers: {}, rosterFails: 2, request() {}, leftoversWhenAnswered: null };
    let answered = false;
    Object.defineProperty(host, "rosterAnswered", { get: () => answered, set: v => { answered = v; host.leftoversWhenAnswered = host.leftovers; } });
    inScope({ host, __text: text }, "", body)();
    return host;
  };
  const whole = answer('[{"kind":"interactive","sessionId":"s1","pid":790,"status":"busy"}]\n@@scoped@@\n790 \n@@host@@\n4100 ');
  const noClaude = answer("\n@@scoped@@\n\n@@host@@\n4100 ");
  const cut = answer('[{"kind":"interactive","sessionId":"s1"');
  check("a whole roster answers once its leftovers are set; one cut short does not, one with no Claude Code still does",
    whole.rosterAnswered && whole.leftoversWhenAnswered?.s1?.status === "busy" && noClaude.rosterAnswered && !cut.rosterAnswered,
    `whole ${whole.rosterAnswered} (leftovers then ${JSON.stringify(whole.leftoversWhenAnswered)}), no Claude ${noClaude.rosterAnswered}, cut ${cut.rosterAnswered}`);

  const c = hostSrc.indexOf("onConnectedChanged: {"), o = hostSrc.indexOf("{", c);
  const connectBody = hostSrc.slice(o + 1, matchBrace(hostSrc, o));
  let waits = 0;
  const host = { roster: true, rosterAnswered: true, sayHello() {}, failPending() {}, live: {} };
  inScope({ connected: true, host, retry: { tries: 0, stop() {}, start() {} }, roster: {}, rosterWait: { restart() { waits++; }, stop() {} } }, "", connectBody)();
  const answeredOn = qmlFunction(convSrc, "onRosterAnsweredChanged");
  let drained = 0;
  if (answeredOn) inScope({ conv: { host: { rosterAnswered: true }, sendQueued() { drained++; } } }, answeredOn.params, answeredOn.body)();
  check("a connect starts over as not known (5 s at most), and the roster's answer sends what was queued",
    host.rosterAnswered === false && waits === 1 && drained === 1, `answered ${host.rosterAnswered} after the connect, ${waits} wait, ${drained} send`);
}

// closed with a message queued (it stays to send it), the roster is still read: the queue waits on what it says
{
  const m = /\broster:\s*/.exec(appSrc);
  const expr = m ? readExpression(appSrc, m.index + m[0].length).expr : "false";
  const reads = (visible, queued) => inScope({ root: { visible }, conv: { queued } }, "", `return !!(${expr});`)();
  check("hidden, Praxis reads the roster while a message waits in the queue, and not otherwise",
    reads(false, [{ text: "x" }]) && !reads(false, []) && reads(true, []), `hidden with a queue: ${reads(false, [{ text: "x" }])}`);
}

// [9] a message typed in the second after the connect, before the roster has answered: the session looked idle, and
// send() resumed it in a new process while the previous host's was still finishing the turn on the same conversation
{
  // the conversation's own send(), not the test probe's send(text: string) above it
  const send = [0, 1, 2].map(n => qmlFunction(convSrc, "send", n)).find(f => f && /fromQueue/.test(f.params));
  const typed = ({ answered, live = null, turnOpen = false }) => {
    const requests = [];
    let stops = 0;
    const conv = { session: { id: "s1", cwd: "/home/a/dev/app", fresh: false }, reading: false, turnOpen, live, leftover: null,
      pendingUser: "", pendingImages: [], queued: [], oldHost: false, acc: null, agent: "claude", agentName: "Claude Code",
      chosenMode: "manual", chosenModel: "", chosenEffort: "", chosenAccount: "", desktopContext: "", offset: 0,
      host: { connected: true, rosterAnswered: answered, features: ["catalog"], request(op) { requests.push(op.op + (op.resume ? " resume" : "")); } },
      testLog() {}, interruptTurn() { stops++; }, setCrash() {}, giveBack() {}, watch() {}, started() {} };
    const ok = inScope({ conv, composer: { agentBlock: () => "" }, errorFade: { restart() {} }, toEnd: { restart() {} } }, send.params, send.body)(
      "and run the tests", [], [], false);
    return { ok, requests, stops, queued: conv.queued.map(q => q.text), echo: conv.pendingUser };
  };
  const gap = typed({ answered: false }), after = typed({ answered: true });
  check("sent before the roster has answered, a message waits in the queue as sent, starting nothing and stopping nothing",
    gap.ok && !gap.requests.length && !gap.stops && JSON.stringify(gap.queued) === '["and run the tests"]' && gap.echo === "and run the tests",
    `sent ${JSON.stringify(gap.requests)}, queued ${JSON.stringify(gap.queued)}, ${gap.stops} stops`);
  check("once it has answered and nothing runs, the same message resumes the session at once",
    after.ok && JSON.stringify(after.requests) === '["start resume"]' && !after.queued.length, `sent ${JSON.stringify(after.requests)}`);
}

// [6] the box's choices after a restart: load() read the mode from the host's sessions, which a restarted host has none
// of, so Ask first became Auto and the level the default, and the next message resumed the session with them
{
  const fn = (name, test = () => true) => [0, 1, 2].map(n => qmlFunction(convSrc, name, n)).find(f => f && test(f));
  const [load, modeOf, connectedOn] = [fn("load"), fn("modeOf"), fn("onConnectedChanged")];
  const send = fn("send", f => /fromQueue/.test(f.params));
  const requests = [];
  const ran = { id: "s1", mode: "default", effort: "high", model: "claude-opus-4-7[1m]", account: "work", alive: true, state: "idle" };
  const conv = { session: { id: "s1", cwd: "/home/a/dev/app", fresh: false }, starting: "", watching: "", queued: [], cuts: {}, loadGen: 0,
    chosenMode: "auto", chosenModel: "", chosenEffort: "", chosenAccount: "", reported: {}, live: ran, leftover: null, turnOpen: false,
    reading: false, pendingUser: "", pendingImages: [], oldHost: false, acc: null, agent: "claude", agentName: "Claude Code",
    desktopContext: "", offset: 0,
    host: { connected: true, rosterAnswered: true, features: ["catalog", "effort"], live: { s1: ran }, request(op) { requests.push(op); } },
    testLog() {}, emptyReplay: () => ({}), resolveRun() {}, swapIn() {}, loadChanges() {}, watch() {}, interruptTurn() {}, setCrash() {},
    giveBack() {}, started() {} };
  const timer = { restart() {}, stop() {} };
  const scope = { conv, composer: { dismiss() {}, agentBlock: () => "" }, slowRead: timer, loadTimeout: timer, errorFade: timer, toEnd: timer };
  for (const [name, f] of [["load", load], ["modeOf", modeOf], ["send", send]]) conv[name] = inScope(scope, f.params, f.body);
  conv.load();                                           // opened while the host runs it, in Ask first at a high level
  const before = [conv.chosenMode, conv.chosenEffort || ran.effort];
  conv.host.live = {};                                   // agent-host restarts: it holds nothing
  conv.live = null;
  inScope(scope, connectedOn.params, connectedOn.body)();
  const after = { mode: conv.chosenMode, model: conv.chosenModel, effort: conv.chosenEffort, account: conv.chosenAccount };
  requests.length = 0;
  conv.send("and run the tests", [], [], false);
  const resume = requests.find(r => r.op === "start") ?? {};
  check("after a host restart the box keeps Ask first, the level, the model and the account, and the next message resumes with them",
    before[0] === "manual" && after.mode === "manual" && after.effort === "high" && after.model === ran.model && after.account === "work"
      && resume.resume === "s1" && resume.mode === "manual" && resume.effort === "high",
    `before ${JSON.stringify(before)}, after ${JSON.stringify(after)}, resumed with ${JSON.stringify({ mode: resume.mode, effort: resume.effort })}`);
  conv.session = { id: "s2", cwd: "/home/a/dev/app", fresh: false };   // another session: its own choices
  conv.load();
  check("another session opened after it starts from its own (Auto, no level), not the restarted one's",
    conv.chosenMode === "auto" && conv.chosenEffort === "", `${conv.chosenMode}, "${conv.chosenEffort}"`);
}

// should-notch-other [o0], the owner's call (decisions2-praxis [4]): signed out and in mid-turn, agent-host stopped with
// the agents it ran, and the conversation ended on the last step or on an unanswered message with nothing said
{
  const expr = qmlProperty(convSrc, "cutOff");
  const ask = ({ last, live = null, terminal = null, leftover = null, elsewhere = false, connected = true, answered = true, more = {} }) => {
    if (!expr) return false;
    const session = { id: "s1", cwd: "/home/a/dev/app", fresh: false };
    const conv = { session, shownSession: session, offset: 900, live, terminal, leftover, elsewhere, pendingUser: "", sendingNow: false,
      queued: [], host: { connected, rosterAnswered: answered },
      items: [{ role: "user", kind: "text", text: "fix the login" }, { role: "assistant", kind: "text", text: "On it." }, last,
        { role: "system", kind: "queue", op: "remove", text: "" }],
      ...more };
    conv.running = (live !== null && (live.alive || live.state !== "idle")) || terminal !== null || leftover !== null;
    return inScope({ conv }, "", expr.startsWith("{") ? expr.slice(1, -1) : `return (${expr});`)();
  };
  const yours = { role: "user", kind: "text", text: "and run the tests" }, step = { role: "assistant", kind: "tool", tool: "Bash", id: "t1" };
  const thought = { role: "assistant", kind: "thinking", text: "…" };
  check("a session no process holds, ending on your message, a step with no result or a thought, was cut off",
    ask({ last: yours }) && ask({ last: step }) && ask({ last: thought }) && ask({ last: { role: "user", kind: "image", images: [] } }),
    `message ${ask({ last: yours })}, step ${ask({ last: step })}, thought ${ask({ last: thought })}`);
  const ended = [{ role: "assistant", kind: "text", text: "Done." }, { ...step, result: "ok" }, { role: "system", kind: "note", text: "Interrupted" },
    { role: "user", kind: "command", text: "/model" }];
  check("a turn that ended (a reply, a step's result, Stop, a slash command) is not",
    ended.every(last => !ask({ last })), ended.map(last => ask({ last })).join(", "));
  const held = [ask({ last: step, live: { state: "idle", alive: false } }), ask({ last: step, live: { state: "working", alive: true } }),
    ask({ last: step, terminal: { status: "busy" } }), ask({ last: step, leftover: { status: "busy", pid: 790 } }), ask({ last: step, elsewhere: true })];
  check("nor one the host knows, one in a terminal, the previous host's still finishing, or an agent open in a terminal", !held.some(x => x),
    held.join(", "));
  const early = [ask({ last: yours, connected: false }), ask({ last: yours, answered: false }), ask({ last: yours, more: { pendingUser: "go on" } }),
    ask({ last: yours, more: { sendingNow: true } }), ask({ last: yours, more: { queued: [{ text: "go on" }] } }), ask({ last: yours, more: { offset: -1 } })];
  check("and nothing is said before the host is back with its roster's answer, nor with a message on its way, nor before the read",
    !early.some(x => x), early.join(", "));
  const at = convSrc.indexOf("visible: conv.cutOff");
  const text = at < 0 ? "" : readExpression(convSrc, convSrc.indexOf("text:", at) + 5).expr;
  check("the note under it says what happened and how to go on",
    text === '"This turn was cut off when the service stopped. Send a message to carry on."', text || "no note");
  const m = /\belsewhere:\s*/.exec(appSrc);
  const where = m ? readExpression(appSrc, m.index + m[0].length).expr : "false";
  const open = (agents, id = "s1") => inScope({ root: { selected: { id } }, presence: { agents } }, "", `return !!(${where});`)();
  check("Praxis tells the conversation of a Codex, pi or opencode session open in a terminal window",
    open([{ session: "s1", window: "0x55" }]) && !open([{ session: "s2", window: "0x55" }]) && !open([{ session: "s1", window: "" }]));
}
done();
