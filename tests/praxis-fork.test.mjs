// A Claude Code fork before its first message (modules/claude/Conversation.qml): Claude Code writes the fork's
// transcript under its own id only then, so its conversation opened empty under the original's title. It now shows
// the original's history, read-only, until the fork's own transcript comes. The file's own code is run under node.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const convSrc = read("modules/claude/Conversation.qml");
const fn = name => [0, 1, 2].map(n => qmlFunction(convSrc, name, n)).find(f => f && !/text: string/.test(f.params));

console.log("A fork before its first message (modules/claude/Conversation.qml)");

const history = [{ role: "user", kind: "text", text: "fix the login", rec: "u1" }, { role: "assistant", kind: "text", text: "Fixed." }];
function opened(live) {
  const asked = [];
  const replies = [];
  const conv = { session: { id: "fork1", cwd: "/home/a/dev/app", fresh: false }, starting: "", watching: "", queued: [], loadGen: 0,
    live, pendingUser: "", findOnLoad: "", shownSession: null, items: [], start: 0, offset: -1, borrowedFrom: "", following: false,
    followGen: 0, followAgain: false, partialText: "", partialThinking: "", busy: false, paging: false, byteCursor: false,
    host: { live: { fork1: live }, request(op, cb) { asked.push(op); replies.push(cb); } },
    testLog() {}, emptyReplay: () => ({}), loadChanges() {}, applyQueue: () => [], applyCut() {}, modeOf: () => "auto", holdFooter() {},
    swapIn(items, start) { conv.shownSession = conv.session; conv.items = items; conv.start = start; },
    merge(fresh) { conv.items = conv.items.concat(fresh); }, sync() {}, watch() {} };
  const timer = { restart() {}, stop() {} };
  const scope = { conv, composer: { dismiss() {} }, slowRead: timer, loadTimeout: timer, errorFade: timer, followTimeout: timer, followSoon: timer,
    toEnd: timer, toEndAgain: timer, blockModel: { count: 0, clear() {} }, list: { positionViewAtIndex() {} }, ListView: {} };
  for (const name of ["load", "follow", "earlier"]) { const f = fn(name); if (f) conv[name] = inScope(scope, f.params, f.body); }
  conv.load();
  const reply = replies.pop();
  if (reply) reply({ ev: "transcript", items: history, offset: 5120, startByte: 2048 });
  return { conv, asked, replies };
}

// the host's summary names the original (`from`) until the fork's first message is sent
const fork = opened({ id: "fork1", alive: true, state: "idle", from: "orig1" });
const plain = opened({ id: "fork1", alive: true, state: "idle" });
{
  const read1 = fork.asked.find(r => r.op === "transcript") ?? {};
  check("opened before its first message, the fork shows the original's conversation",
    read1.id === "orig1" && fork.conv.items === history && fork.conv.borrowedFrom === "orig1",
    `read ${read1.id}, ${fork.conv.items.length} items, borrowed "${fork.conv.borrowedFrom}"`);
  check("and follows its own transcript from its start, where Claude Code will write it",
    fork.conv.offset === 0 && fork.conv.start === 2048, `offset ${fork.conv.offset}`);
  const read2 = plain.asked.find(r => r.op === "transcript") ?? {};
  check("any other session reads its own, as before", read2.id === "fork1" && plain.conv.borrowedFrom === "" && plain.conv.offset === 5120);
}

// "Earlier" while it is borrowed reads the original too
{
  fork.asked.length = 0;
  fork.conv.earlier?.();
  const req = fork.asked.find(r => r.op === "transcript") ?? {};
  check("Earlier reads the original's earlier part while its history is shown", req.id === "orig1" && req.beforeByte === 2048, JSON.stringify(req));
  fork.conv.paging = false;
}

// the first message sent: the fork's own transcript, with the history it carries, takes the borrowed one's place
{
  fork.conv.follow?.();
  const own = history.concat([{ role: "user", kind: "text", text: "now do the signup", rec: "u9" }]);
  fork.replies.pop()?.({ ev: "transcript", items: own, offset: 6000 });
  check("its own transcript replaces the borrowed one, nothing shown twice",
    fork.conv.borrowedFrom === "" && fork.conv.items.length === 3 && fork.conv.items[2].rec === "u9" && fork.conv.offset === 6000,
    `${fork.conv.items.length} items, borrowed "${fork.conv.borrowedFrom}"`);
}

// read-only: the original's messages are not gone back to, nor its last turn's changes undone, from the fork
{
  const at = convSrc.indexOf('tip: "Go back to here"');
  const hide = at < 0 ? "false" : readExpression(convSrc, convSrc.indexOf("hide:", at) + 5).expr;
  const u = convSrc.indexOf("canUndo:", convSrc.indexOf("id: changesC"));
  const canUndo = readExpression(convSrc, u + 8).expr;
  const shown = borrowedFrom => {
    const conv = { locked: false, busy: false, rewinding: false, caps: { rewind: true, rewindFiles: true }, borrowedFrom };
    const d = { b: { rec: "u1", latest: true } };
    return { back: !inScope({ conv, d }, "", `return (${hide});`)(), undo: !!inScope({ conv, d }, "", `return (${canUndo});`)() };
  };
  const borrowed = shown("orig1"), own = shown("");
  check("its history offers no Go back and no Undo; the fork's own does", !borrowed.back && !borrowed.undo && own.back && own.undo,
    `borrowed ${JSON.stringify(borrowed)}, own ${JSON.stringify(own)}`);
}
done();
