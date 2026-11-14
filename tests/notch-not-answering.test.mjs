// Esc while the notch asks about an app that is not answering (services/IslandController.qml): the compositor's Esc
// (the islandCollapse shortcut's onPressed) and the prompt's own answerNotAnswering(), clearNotAnswering() and queue,
// under node. The prompt takes no keys and ignores a click beside its buttons, so Esc is its way out by key: Wait,
// which ends nothing. Then which asks showNotAnswering() shows: one offered again is left as it is, while Thyris's
// next ask after Wait, under the same id with a since of its own, is a new prompt.
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
    signinHolding: false, notAnswering: null, notAnsweringFor: 0, notAnsweringDone: "", collapseExpansion: () => folded.push(true),
    closeRequested() {} };
  Object.defineProperty(root, "transientShowing", { get: () => root.transientState !== "" });
  const scope = { root, Config: { options }, holdTimer: { interval: 0, restart() {}, stop() {} }, Quickshell: { execDetached: c => ran.push(c) },
    DesktopEntries: { heuristicLookup: () => null } };
  for (const name of ["request", "enqueue", "activate", "dismiss", "holdFor", "signinHeldBack", "cancelState", "showNotAnswering",
                      "answerNotAnswering", "clearNotAnswering"]) {
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
// Thyris's ask (src/instance.cpp Prompt::ask): its id is the waiting start's pid, the same for every ask it makes
const thyris = since => ({ id: "5150", cls: "thyris", title: "", pid: 4242, fifo: "/run/user/1000/thyris-anr-5150", buttons: ["close", "wait"], since });
{
  const n = notch();
  check("Thyris's first ask is shown", n.root.showNotAnswering(thyris(1000)) && n.root.notAnswering?.since === 1000
    && n.root.transientState === "notAnswering", `the notch shows ${n.root.transientState || "nothing"}`);
  check("offered again while it is up, it is the same prompt", n.root.showNotAnswering(thyris(1000)) && n.root.notAnswering?.since === 1000);
  n.root.answerNotAnswering("wait");
  check("answered Wait, it goes", n.root.notAnswering === null && JSON.stringify(n.answered()) === '["wait"]', JSON.stringify(n.answered()));
  n.root.showNotAnswering(thyris(1000));
  check("the answered prompt offered again is left as it is", n.root.notAnswering === null && n.root.transientState === "",
    `the notch shows ${n.root.transientState || "nothing"}`);
  const again = n.root.showNotAnswering(thyris(21000));
  check("Thyris's next ask 20 s later, the same id with a since of its own, is shown", again && n.root.notAnswering?.since === 21000
    && n.root.transientState === "notAnswering", `the notch shows ${n.root.transientState || "nothing"}`);
  n.root.answerNotAnswering("close");
  check("and is answered on its fifo", JSON.stringify(n.answered()) === '["wait","close"]', JSON.stringify(n.answered()));
}
{
  // scripts/activity/hyprland-dialog: one dialog, offered every 5 s with the same id and since until the wrapper ends
  const n = notch(), dialog = { id: "777", cls: "org.kde.krita", title: "Krita", pid: 4243, fifo: "/run/user/1000/tacit-anr-777", buttons: ["Terminate", "Wait"], since: 5000 };
  n.root.showNotAnswering(Object.assign({}, dialog));
  n.root.answerNotAnswering("wait");
  n.root.showNotAnswering(Object.assign({}, dialog));
  check("the wrapper's dialog offered again after its answer is left as it is", n.root.notAnswering === null && n.root.transientState === "",
    `the notch shows ${n.root.transientState || "nothing"}`);
}
done();
