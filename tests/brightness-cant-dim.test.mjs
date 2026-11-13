// A brightness key on a screen that can't be dimmed (services/Brightness.qml, IslandController.qml, tacit-settings.qml):
// a desktop's monitor with no DDC answer, or no backlight. The key used to do nothing and say nothing. Brightness's own
// increaseBrightness() and decreaseBrightness(), a screen's initialize() and its read's onExited run under node with
// pretend screens; the notch's request() takes the answer; Settings > Screen's note is read with the shell's answer.
import { adapterDefaults, inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a brightness key on a screen that can't be dimmed (Brightness.qml, IslandController.qml)");
const src = read("services/Brightness.qml");
const compAt = src.indexOf("component BrightnessMonitor:");
const comp = src.slice(compAt, matchBrace(src, src.indexOf("{", compAt)) + 1);
const procAt = comp.indexOf("initProc: Process {");
const exited = readExpression(comp, comp.indexOf("onExited:", procAt) + "onExited:".length).expr;

// the service with one screen, focused, as initialize() and its read leave it
function service(name, { ddc = false } = {}) {
  const timer = () => ({ running: false, restart() { this.running = true; }, start() { this.running = true; }, stop() { this.running = false; } });
  const said = [];
  const root = { monitors: [], ddcMonitors: ddc ? [{ name, busNum: "7" }] : [], cantDim: () => said.push("cantDim"), initializeMonitor() {} };
  const monitor = { screen: { name }, ready: false, settled: false, ddcTries: 0, retrying: false, brightness: 0.5, isDdc: false, busNum: "",
    retryTimer: timer(), initProc: { running: false }, setBrightness(v) { this.brightness = v; } };
  monitor.isInternal = /^(eDP|LVDS|DSI)/i.test(name);
  root.monitors.push(monitor);
  const scope = { root, monitor, Hyprland: { focusedMonitor: { name } }, initializeMonitor: () => {}, monitors: root.monitors,
    screen: monitor.screen, retryTimer: monitor.retryTimer, initProc: monitor.initProc };
  for (const k of ["isDdc", "busNum"]) Object.defineProperty(scope, k, { get: () => monitor[k], set: v => { monitor[k] = v; } });
  const init = qmlFunction(comp, "initialize");
  const initialize = inScope(scope, init.params, init.body).bind(monitor);
  const exit = inScope(scope, "", `return (${exited});`)();
  for (const f of ["increaseBrightness", "decreaseBrightness"]) {
    const fn = qmlFunction(src, f);
    root[f] = inScope(scope, fn.params, fn.body);
  }
  return { root, monitor, said, initialize, exit };
}

{
  const s = service("DP-1");
  s.initialize();
  s.root.increaseBrightness();
  s.root.decreaseBrightness();
  check("a monitor with no DDC answer and no backlight: each key says it can't be dimmed", s.said.length === 2,
    `said ${s.said.length} times, the screen ${s.monitor.settled ? "settled" : "not settled"}`);
}
{
  const s = service("DP-1", { ddc: true });
  s.initialize();
  s.exit(1, 0);   // its first read gave nothing: asked again in 5 s
  s.root.increaseBrightness();
  check("a DDC monitor still being asked again says nothing yet", s.said.length === 0 && s.monitor.retryTimer.running,
    `said ${s.said.length} times, retry ${s.monitor.retryTimer.running ? "waiting" : "not waiting"}`);
  for (let i = 0; i < 3; i++) { s.monitor.retrying = true; s.exit(1, 0); }
  s.root.increaseBrightness();
  check("once its retries are spent, the key says so", s.said.length === 1, `said ${s.said.length} times`);
}
{
  const s = service("eDP-1");
  s.initialize();
  s.monitor.ready = true;   // the panel's read came back with a level
  s.exit(0, 0);
  s.root.increaseBrightness();
  check("a screen that can be dimmed is dimmed, without the words", s.said.length === 0 && Math.abs(s.monitor.brightness - 0.55) < 1e-9,
    `said ${s.said.length} times, brightness ${s.monitor.brightness}`);
}
{
  const s = service("eDP-1");
  s.root.increaseBrightness();   // the screen list just changed: nothing asked yet
  check("before the screen is asked at all, nothing is said", s.said.length === 0, `said ${s.said.length} times`);
}

// the notch: the answer comes at once over a longer line, like the meter, and the line comes back after it
const isrc = read("services/IslandController.qml");
const options = adapterDefaults(read("modules/common/Config.qml"));
const handler = qmlFunction(isrc, "onCantDim");
check("the notch listens for it", handler !== null);
if (handler) {
  const root = { enabled: true, suppressed: false, warmedUp: true, transientState: "", transientPriority: -1, payload: {}, queue: [] };
  Object.defineProperty(root, "transientShowing", { get: () => root.transientState !== "" });
  const scope = { root, Config: { options }, Translation: { tr: s => s }, holdTimer: { interval: 0, restart() {}, stop() {} } };
  for (const name of ["request", "enqueue", "activate", "dismiss", "holdFor", "wingFor", "signinHeldBack", "cancelState"]) {
    const f = qmlFunction(isrc, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  root.request("battery", { text: "10% left" }, 92);
  inScope(scope, "", handler.body)();
  const p = root.payload;
  check("the notch says \"This screen can't be dimmed from here\"", root.transientState !== "battery"
    && `${p.text} ${p.value}` === "This screen can't be dimmed from here", `${root.transientState}: ${p.text} | ${p.value}`);
  check("it is read, not flashed like a meter", root.holdFor(root.transientState) >= 4000, `${root.holdFor(root.transientState)} ms`);
  const wide = root.wingFor(root.transientState);
  root.payload = { text: "10% left" };
  const plain = root.wingFor("battery");
  root.payload = p;
  check("its wings are wider than a plain line's, for \"can't be dimmed from here\"", wide > plain, `${wide} against ${plain}`);
  root.dismiss();
  check("the battery line comes back after it", root.transientState === "battery", root.transientState || "nothing");
}

// Settings > Screen: why there is no slider
console.log("== Settings > Screen with no screen to dim (tacit-settings.qml)");
const ssrc = read("tacit-settings.qml");
const group = ssrc.slice(ssrc.indexOf('title: "Screen"'));
const note = readExpression(group, group.indexOf("note:") + "note:".length).expr;
const pageAt = ssrc.indexOf("id: displayPage");
const page = ssrc.slice(pageAt, ssrc.indexOf('title: "Screen"'));
const readAt = page.indexOf("id: readBrightness");
const onRead = readExpression(page, page.indexOf("onRead:", readAt) + "onRead:".length).expr;
function settings(answer, screens) {
  const dp = { brightness: -1, monitorsWriteFailed: false, screens, cantDim: false };
  inScope({ dp }, "", `return (${onRead});`)()(answer);
  return { dp, note: inScope({ dp }, "", `return (${note});`)() };
}
{
  const s = settings("-1", [{ name: "DP-1" }]);
  check("the shell says no screen can be dimmed: the page says why there is no slider", /can't be dimmed from here/.test(s.note), `"${s.note}"`);
  const t = settings("0.6", [{ name: "eDP-1" }]);
  check("with a level there is a slider and no such note", t.dp.brightness === 0.6 && t.note === "", `brightness ${t.dp.brightness}, "${t.note}"`);
  const u = settings("", [{ name: "DP-1" }]);
  check("no answer from the shell is not taken for a screen that can't be dimmed", !/dimmed/.test(u.note), `"${u.note}"`);
}
done();
