// The moment an install or a removal in Apps (store.qml) has ended, before the lists are read again: the app's capsule
// and the words beside it say what the work left (Open and "On this computer" for an app just got, Get once it is removed),
// not what the old lists say. A window closed on its work ends only once its front page, kept for the next open, has been
// read again. The window's own result and exit handlers, stateOf, costWords and endHidden, and the front page's exit
// handler, run under node on the backend's {"result": "ok"}.
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("store.qml");
const proc = src.indexOf("id: workProc");
const body = key => { const open = src.indexOf("{", src.indexOf(key, proc)); return src.slice(open + 1, matchBrace(src, open)); };
const homeAt = src.indexOf("onExited:", src.indexOf("id: homeProc"));
const homeExited = readExpression(src, homeAt + "onExited:".length).expr;

// Krita got (or removed) where its page is open; the lists, not read again yet, still say what they said before
function work(kind, visible) {
  let quits = 0;
  const root = { visible, work: { pkg: "krita", kind, progress: 0.9, phase: "Installing", from: "app:krita" }, outcome: {}, askUpdate: null,
    justGot: "", settled: {}, restartNeeded: false, appInfo: null, refresh() { homeProc.running = true; },
    appOf: pkg => ({ krita: { name: "Krita" } })[pkg] ?? null, failedInstall() {}, notice() {} };
  const homeProc = { running: false, again: false, quitAfter: false };
  const Qt = { quit() { quits++; } };
  const scope = Object.assign(root, { root, homeProc, tickTimer: { restart() {} }, Quickshell: { execDetached() {} }, Qt });
  for (const name of ["stateOf", "costWords", "endHidden", "sayRestart"]) {
    const f = qmlFunction(src, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  inScope(scope, "line", body("onRead: line =>"))(JSON.stringify({ result: "ok" }));
  inScope(scope, "", body("onExited:"))();
  const before = { a: { pkg: "krita", installed: kind === "remove", available: true, free: true, download: 120 } };
  return { root, state: root.stateOf(before.a), words: root.costWords(before.a), quits: () => quits,
    homeDone: () => { homeProc.running = false; inScope(Object.assign(homeProc, { root, Qt }), "", homeExited)(); } };
}

console.log("== the capsule once an app is got or removed, before the lists are read again (store.qml)");
const got = work("install", true);
check("just got: its capsule says Open, not Get, so a press opens it rather than getting it again", got.state === "installed", got.state);
check("and the words beside it say it is on this computer", got.words === "On this computer", got.words);
const gone = work("remove", true);
check("just removed: Get, not Open on an app that is not there", gone.state === "get", gone.state);

console.log("== a window closed on its work ends once its front page is read again (store.qml)");
const hidden = work("install", false);
check("the work ends: the window waits for the front page", hidden.quits() === 0, `${hidden.quits()} quits`);
hidden.homeDone();
check("the front page is read again (and kept for next time): then it ends", hidden.quits() === 1, `${hidden.quits()} quits`);
const back = work("install", false);
back.root.visible = true;
back.homeDone();
check("opened again before that: it stays", back.quits() === 0, `${back.quits()} quits`);
done();
