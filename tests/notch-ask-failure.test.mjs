// A question from the notch that agent-host refuses (services/Claude.qml): send(), dispatch() and what they give back,
// the file's own, run under node with a pretend host. What was typed and attached must come back as it was.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a notch question that could not be sent (Claude.qml)");
const src = read("services/Claude.qml");

const shot = { kind: "image", glyph: "image", label: "Screenshot.png", path: "/home/a/Pictures/Screenshot.png" };
const notes = { kind: "file", glyph: "description", label: "notes.txt", path: "/home/a/notes.txt" };
const page = { kind: "context", glyph: "language", label: "Docs", text: 'The user is looking at the web page "Docs".' };

// answer: what the host says to start or send
function notch(chips, { running = false, answer = { ev: "error", message: "That folder is gone." } } = {}) {
  const asked = [];
  const host = { connected: true, live: running ? { s1: { alive: true, state: "idle" } } : {}, request(obj, cb) { asked.push(obj); cb(answer); } };
  const root = { home: "/home/a", cwd: "/home/a", chips: chips.slice(), draftText: "", sentContext: {}, queue: [], starting: false,
    busy: false, error: "", note: "", pendingQ: "", followUntil: 0, continuing: running, current: running ? { id: "s1", cwd: "/home/a" } : null,
    watchingId: running ? "s1" : "", clearLive() {}, markShell() {}, setCurrent() {}, shorten: q => q, sendNext() {}, touch() {}, watch() {} };
  Object.defineProperty(root, "sid", { get: () => (root.continuing && root.current ? root.current.id : "") });
  Object.defineProperty(root, "session", { get: () => (root.sid ? host.live[root.sid] ?? null : null) });
  const scope = { root, host, Qt: { callLater: f => f() } };
  for (const name of ["send", "dispatch", "giveBack"]) {
    const f = qmlFunction(src, name);
    if (f) root[name] = inScope(scope, f.params, f.body);
  }
  return { root, asked };
}
const paths = chips => chips.filter(c => c.kind !== "context").map(c => c.label).join(", ") || "nothing";

{
  const n = notch([page, shot]);
  n.root.send("");                     // a screenshot dropped on the notch, nothing written, Send
  check("a picture sent alone that the host refuses comes back as a chip", n.root.chips.some(c => c.path === shot.path), `attached now: ${paths(n.root.chips)}`);
  check("and the draft stays empty, not the stand-in question", n.root.draftText === "", JSON.stringify(n.root.draftText));
  check("what the host was asked still carried the picture and the stand-in question",
    n.asked[0]?.images?.[0] === shot.path && /^What is this\?/.test(n.asked[0]?.text ?? ""), JSON.stringify(n.asked[0]));
}
{
  const n = notch([page, notes], { running: true });
  n.root.send("sum this up");
  check("a refused send to a running chat gives back the words as typed, without the file's @path",
    n.root.draftText === "sum this up", JSON.stringify(n.root.draftText));
  check("and the file as its chip, once", n.root.chips.filter(c => c.path === notes.path).length === 1, `attached now: ${paths(n.root.chips)}`);
  check("the page the person was on is kept as it was", n.root.chips.filter(c => c.kind === "context").length === 1);
}
{
  const n = notch([page, notes], { running: true, answer: { ev: "error", disconnected: true, message: "Lost the connection." } });
  n.root.send("sum this up");
  check("a send cut off by the socket gives back the words and the file too", n.root.draftText === "sum this up" && n.root.chips.some(c => c.path === notes.path),
    `${JSON.stringify(n.root.draftText)}, attached: ${paths(n.root.chips)}`);
}
{
  const n = notch([page, shot], { answer: { ev: "started", id: "s9" } });
  n.root.send("what is this error?");
  check("a question that went leaves the draft empty and the picture sent", n.root.draftText === "" && !n.root.chips.some(c => c.path === shot.path),
    `${JSON.stringify(n.root.draftText)}, attached: ${paths(n.root.chips)}`);
}
done();
