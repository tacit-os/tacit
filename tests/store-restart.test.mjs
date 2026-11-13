// "Get X and the updates" (store.qml): the system is brought up to date under the running desktop (pacman -Syu with the
// app), and a restart finishes it. The window's own result and exit handlers and the functions they call, run under node
// on the backend's {"result": "ok", "restart": true}: the person is told in a notification, which stays in the list once
// Apps is closed, whether the window is open or was closed on the work, and once.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("store.qml");
const proc = src.indexOf("id: workProc");
const body = key => { const open = src.indexOf("{", src.indexOf(key, proc)); return src.slice(open + 1, matchBrace(src, open)); };

// Get pressed on a Discover spread, the sheet accepted: Krita and the updates, then the backend's answer and its exit
function getEverything(visible) {
  const sent = [];
  const root = { visible, work: { pkg: "krita", kind: "install", progress: 0.9, phase: "Installing", everything: true, from: "discover:" },
    outcome: {}, askUpdate: null, justGot: "", restartNeeded: false, appInfo: null, refresh() {},
    appOf: pkg => ({ krita: { name: "Krita" } })[pkg] ?? null, failedInstall() {} };
  // the window's own names are in scope in its functions and handlers, as in QML, with its ids
  const scope = Object.assign(root, { root, tickTimer: { restart() {} }, Quickshell: { execDetached: a => sent.push(a) }, Qt: { quit() {} } });
  for (const name of ["endHidden", "notice", "sayRestart"]) {
    const f = qmlFunction(src, name);
    if (f) root[name] = inScope(scope, f.params, f.body);
  }
  inScope(scope, "line", body("onRead: line =>"))(JSON.stringify({ result: "ok", restart: true }));
  inScope(scope, "", body("onExited:"))();
  return { sent: sent.filter(a => a[0] === "notify-send"), restartNeeded: root.restartNeeded };
}

console.log("== a restart to finish the updates got with an app (store.qml)");
{
  const r = getEverything(true);
  check("the window open on Discover: a notification says to restart", r.sent.length === 1 && r.sent[0].includes("Restart to finish the updates."),
    JSON.stringify(r.sent));
  check("and the app's page still offers Restart", r.restartNeeded);
}
{
  const r = getEverything(false);
  check("the window closed on it: one notification, as before", r.sent.length === 1 && r.sent[0].includes("Restart to finish the updates."),
    JSON.stringify(r.sent));
}
done();
