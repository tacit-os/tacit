// Esc while the notch asks about an app that is not answering (services/IslandController.qml): the compositor's Esc
// (the islandCollapse shortcut's onPressed) and the prompt's own answerNotAnswering(), clearNotAnswering() and queue,
// under node. The prompt takes no keys and ignores a click beside its buttons, so Esc is its way out by key: Wait,
// which ends nothing.
import { adapterDefaults, inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Esc and the not-answering prompt (IslandController.qml)");
const src = read("services/IslandController.qml");
const options = adapterDefaults(read("modules/common/Config.qml"));
const at = src.indexOf("onPressed:", src.indexOf('name: "islandCollapse"'));
const brace = src.slice(at + "onPressed:".length).match(/^\s*\{/);
const pressed = brace ? (o => src.slice(o + 1, matchBrace(src, o)))(at + "onPressed:".length + brace[0].length - 1)
  : src.slice(at + "onPressed:".length, src.indexOf("\n", at));

function notch() {
  const ran = [], folded = [];
  const root = { enabled: true, suppressed: false, warmedUp: true, transientState: "", transientPriority: -1, payload: {}, queue: [],
    signinHolding: false, notAnswering: null, collapseExpansion: () => folded.push(true) };
  Object.defineProperty(root, "transientShowing", { get: () => root.transientState !== "" });
  const scope = { root, Config: { options }, holdTimer: { interval: 0, restart() {}, stop() {} }, Quickshell: { execDetached: c => ran.push(c) } };
  for (const name of ["request", "enqueue", "activate", "dismiss", "holdFor", "signinHeldBack", "cancelState", "answerNotAnswering", "clearNotAnswering"]) {
    const f = qmlFunction(src, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  const esc = inScope(scope, "", pressed);
  // what Hyprland's dialog wrapper hears on its fifo
  const answered = () => ran.filter(c => c[0] === "sh" && /printf/.test(c[2] ?? "")).map(c => c.at(-1));
  return { root, esc, answered, folded, ran };
}

{
  const n = notch();
  n.root.notAnswering = { id: "0x5a1", name: "Krita", pid: 4242, fifo: "/run/user/1000/anr.fifo", buttons: ["Terminate", "Wait"] };
  n.root.activate("notAnswering", n.root.notAnswering, 95);
  n.esc();
  check("Esc answers the prompt Wait", JSON.stringify(n.answered()) === '["Wait"]', `the wrapper heard ${JSON.stringify(n.answered())}`);
  check("and the prompt goes", n.root.notAnswering === null && n.root.transientState === "", `the notch shows ${n.root.transientState || "nothing"}`);
  check("and nothing is ended: no Terminate, no kill", !n.ran.some(c => /kill|Terminate/.test(c.join(" "))), JSON.stringify(n.ran));
  check("and Esc still folds a sheet as before", n.folded.length === 1);
}
{
  const n = notch();
  n.root.request("battery", { text: "10% left" }, 92);
  n.esc();
  check("Esc with another line showing answers nothing and leaves it", n.answered().length === 0 && n.root.transientState === "battery",
    `${JSON.stringify(n.answered())}, the notch shows ${n.root.transientState}`);
}
done();
