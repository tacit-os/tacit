// Praxis after agent-host restarts mid-turn (modules/claude/Host.qml, Conversation.qml): the old process finishes the
// turn on its own, known only from the roster (a leftover), and its last rows were read only while one was listed.
// The handlers' own code is run under node.
import { inScope, matchBrace, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const hostSrc = read("modules/claude/Host.qml"), convSrc = read("modules/claude/Conversation.qml");

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
done();
