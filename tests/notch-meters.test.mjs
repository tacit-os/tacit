// A volume, brightness or mic key pressed while the notch shows something more important (services/IslandController.qml):
// the file's own request(), enqueue(), activate(), dismiss() and holdFor() under node, with the holds Config.qml gives.
// The on-screen meter stands down while the notch answers these keys, so the notch has to show them; what was showing
// comes back after, once.
import { adapterDefaults, inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a key's meter over another notch state (IslandController.qml)");
const src = read("services/IslandController.qml");
const options = adapterDefaults(read("modules/common/Config.qml"));

function notch() {
  const root = { enabled: true, suppressed: false, warmedUp: true, transientState: "", transientPriority: -1, payload: {}, queue: [],
    signinHolding: false };
  Object.defineProperty(root, "transientShowing", { get: () => root.transientState !== "" });
  const scope = { root, Config: { options }, holdTimer: { interval: 0, restart() {}, stop() {} } };
  for (const name of ["request", "enqueue", "activate", "dismiss", "holdFor", "signinHeldBack", "cancelState"]) {
    const f = qmlFunction(src, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  const shows = () => root.transientState || "nothing";
  return { root, shows };
}
const volume = n => n.root.request("volume", { kind: "volume" }, 76);

for (const [state, priority, key] of [["battery", 92, "volume"], ["timerDone", 88, "brightness"], ["flow", 150, "mic"]]) {
  const n = notch();
  n.root.request(state, { text: state }, priority);
  n.root.request(key, { kind: key }, 76);
  check(`the ${key} key over ${state} shows its meter`, n.shows() === key, `the notch shows ${n.shows()}`);
  n.root.dismiss();                    // the meter's hold ends
  check(`and ${state} comes back after it, as it was`, n.shows() === state && n.root.payload.text === state, `the notch shows ${n.shows()}`);
}
{
  const n = notch();
  n.root.activate("notAnswering", { id: "0x5a1", name: "Krita" }, 95);
  volume(n);
  check("over the not-answering prompt, the volume key shows its meter", n.shows() === "volume", `the notch shows ${n.shows()}`);
  n.root.dismiss();
  check("and the prompt comes back after it", n.shows() === "notAnswering" && n.root.payload.name === "Krita", `the notch shows ${n.shows()}`);
}
{
  const n = notch();
  n.root.request("claudeAsk", { request: "r1", text: "Run make?" }, 140);
  volume(n);
  n.root.dismiss();
  check("an agent's ask still comes back after a meter", n.shows() === "claudeAsk" && n.root.payload.request === "r1", `the notch shows ${n.shows()}`);
}
{
  const n = notch();
  n.root.request("battery", { text: "10% left" }, 92);
  for (let i = 0; i < 6; i++) volume(n);   // the key held down
  n.root.dismiss();
  n.root.dismiss();
  check("holding the key over the battery line brings the line back once", n.shows() === "nothing" && n.root.queue.length === 0,
    `after two holds the notch shows ${n.shows()}, ${n.root.queue.length} waiting`);
}
{
  const n = notch();
  n.root.request("battery", { text: "10% left" }, 92);
  volume(n);
  n.root.request("battery", { text: "9% left" }, 92);   // a newer battery line while the meter shows
  check("a newer battery line while the meter shows takes over", n.shows() === "battery" && n.root.payload.text === "9% left", `${n.shows()}: ${n.root.payload.text}`);
  n.root.dismiss();
  check("and the older one does not come back after it", n.shows() === "nothing", `the notch shows ${n.shows()}: ${n.root.payload.text}`);
}
{
  const n = notch();
  n.root.request("battery", { text: "10% left" }, 92);
  n.root.request("workspace", { id: 3 }, 30);
  check("a workspace numeral during the battery line is still dropped", n.shows() === "battery" && !n.root.queue.length);
  n.root.request("network", { text: "Wi-Fi on." }, 50);
  volume(n);
  const seen = [];
  for (let i = 0; i < 5 && n.root.transientShowing; i++) { n.root.dismiss(); seen.push(n.shows()); }
  check("after the meter come the battery line, then the lower line that waited behind it", seen.join(" > ") === "battery > network > nothing", seen.join(" > "));
}
done();
