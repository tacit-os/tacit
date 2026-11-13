// A notch question whose session agent-host ends for want of a sign-in (services/Claude.qml): the exit reasons the host
// sends then ("signedOut", "expired"; agent-host main.rs) through the file's own two onExited handlers, the sheet's and
// the Live Activity's, under node. Both must say it, as Praxis does, and not end in a silent check.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a notch session ended for want of a sign-in (Claude.qml)");
const src = read("services/Claude.qml");
const sheetExit = qmlFunction(src, "onExited", 0), activityExit = qmlFunction(src, "onExited", 1);

function notch() {
  const ended = [];
  const root = { sid: "s1", activityId: "s1", seenSeq: 4, watchingId: "s1", sentWatches: {}, earlier: [], items: [], liveDone: true,
    pendingQ: "what does this error mean?", error: "", clearLive() {} };
  const scope = { root, host: { request() {} }, IslandController: { endActivity: (status, text, extra) => ended.push({ status, text, extra }) } };
  const f = qmlFunction(src, "signInWords");
  if (f) root.signInWords = inScope(scope, f.params, f.body);
  const sheet = inScope(scope, sheetExit.params, sheetExit.body), activity = inScope(scope, activityExit.params, activityExit.body);
  return { root, ended, exit(reason) { sheet("s1", reason, []); activity("s1", reason, []); } };
}

for (const [reason, words] of [["signedOut", /isn't signed in/], ["expired", /sign-in has expired/]]) {
  const n = notch();
  n.exit(reason);
  check(`a session the host ends as "${reason}": the sheet says it and where to sign in`, words.test(n.root.error) && /Open in app/.test(n.root.error),
    JSON.stringify(n.root.error));
  check(`and the Live Activity ends in the failure tone with the same words, not a silent check`,
    n.ended.length === 1 && n.ended[0].status === "fail" && words.test(n.ended[0].text ?? ""), JSON.stringify(n.ended));
  check("the question is no longer shown as waiting", n.root.pendingQ === "", JSON.stringify(n.root.pendingQ));
}
{
  const n = notch();
  n.root.pendingQ = "";
  n.exit("idle");
  check("a session that idles out after its answer still ends quietly", n.root.error === "" && n.ended[0]?.status === "ok" && n.ended[0]?.extra?.silent === true,
    `${JSON.stringify(n.root.error)}, ${JSON.stringify(n.ended)}`);
}
done();
