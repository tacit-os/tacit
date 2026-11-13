// On several monitors only one Bluetooth pairing sheet holds the keyboard, the focused monitor's when the question came
// (modules/ii/bluetooth/BluetoothPairing.qml): the Scope's pickKeyScreen(), its asking handler, its linger and each
// screen's window's keyboard binding run under node with three monitors. With every sheet exclusive the compositor
// chooses which gets the keys, and the code typed can land in a sheet on another screen.
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the Bluetooth pairing sheet on three monitors (BluetoothPairing.qml)");
const src = read("modules/ii/bluetooth/BluetoothPairing.qml");
const expr = (key, from = 0) => { const at = src.indexOf(key, from); return at < 0 ? null : readExpression(src, at + key.length).expr; };
const handler = qmlFunction(src, "onAskingChanged");
const pick = qmlFunction(src, "pickKeyScreen");
const winAt = src.indexOf("delegate: PanelWindow");
const focusExpr = expr("WlrLayershell.keyboardFocus:", winAt);
const takesExpr = qmlProperty(src.slice(winAt), "takesKeys");
const lingerFired = expr("onTriggered:", src.indexOf("id: linger"));

function desk(focusedName) {
  const screens = ["eDP-1", "DP-2", "HDMI-A-1"].map(name => ({ name }));
  const agent = { asking: false };
  const hypr = { focusedMonitor: { name: focusedName } };
  const linger = { running: false, stop() { this.running = false; }, restart() { this.running = true; } };
  const root = { up: false, keyScreenName: "" };
  const scope = { root, linger, BluetoothAgent: agent, Hyprland: hypr, WM: { compositor: "hyprland" }, NiriBackend: {},
    Quickshell: { screens }, WlrKeyboardFocus: { Exclusive: "exclusive", None: "none" } };
  if (pick) root.pickKeyScreen = inScope(scope, pick.params, pick.body);
  const changed = inScope(scope, handler.params, handler.body);
  return {
    hypr,
    ask() { agent.asking = true; changed(); },
    answer() { agent.asking = false; changed(); },
    folded() { linger.running = false; inScope(scope, "", `${lingerFired};`)(); },
    // which screens' windows ask for the keyboard exclusively
    keyed() {
      return screens.filter(screen => {
        const panelWindow = { screen };
        const s = { ...scope, panelWindow };
        if (takesExpr !== null) panelWindow.takesKeys = inScope(s, "", `return (${takesExpr});`)();
        return inScope(s, "", `return (${focusExpr});`)() === "exclusive";
      }).map(s => s.name);
    },
  };
}

{
  const d = desk("DP-2");
  d.ask();
  check("asked while working on DP-2, only DP-2's sheet holds the keyboard", d.keyed().join() === "DP-2", d.keyed().join(", "));
  d.hypr.focusedMonitor = { name: "HDMI-A-1" };
  check("the focus moving to another monitor does not move the keys mid-code", d.keyed().join() === "DP-2", d.keyed().join(", "));
  d.answer();
  d.ask();
  check("a second question while the sheet folds back keeps its screen", d.keyed().join() === "DP-2", d.keyed().join(", "));
  d.answer(); d.folded();
  d.ask();
  check("the next question, after it folded, goes to the screen in use then", d.keyed().join() === "HDMI-A-1", d.keyed().join(", "));
}
{
  const d = desk("");
  d.ask();
  check("with no focused monitor known, the first screen's sheet holds it", d.keyed().join() === "eDP-1", d.keyed().join(", "));
}
done();
