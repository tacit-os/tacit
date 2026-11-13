// The volume and brightness keys' feedback (modules/ii/onScreenDisplay/OnScreenDisplay.qml): the on-screen meter stands
// down while the notch answers, and opens where the notch cannot. Its Connections' enabled bindings and the volume
// protection's handler run under node, on two monitors with the notch limited to one (Settings > Notch).
import { adapterDefaults, inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== volume and brightness feedback with the notch on some monitors (OnScreenDisplay.qml)");
const src = read("modules/ii/onScreenDisplay/OnScreenDisplay.qml");
const configSrc = read("modules/common/Config.qml");

// the enabled: binding of the Connections whose target is this
function enabledOf(target) {
  const at = src.indexOf(`target: ${target}`);
  const m = /enabled:\s*/.exec(src.slice(at));
  return readExpression(src, at + m.index + m[0].length).expr;
}

function osd({ screenList, focused, locked = false }) {
  const options = adapterDefaults(configSrc);
  options.island.screenList = screenList;
  const root = { protectionMessage: "", currentIndicator: "", opened: 0, triggerOsd() { root.opened++; } };
  const scope = { root, Config: { options }, IslandController: { suppressed: locked }, Hyprland: { focusedMonitor: { name: focused } } };
  for (const name of ["focusedHasNotch", "islandOwnsVolume", "islandOwnsBrightness"]) {
    const e = qmlProperty(src, name);
    Object.defineProperty(root, name, { get: () => (e === null ? undefined : inScope(scope, "", `return (${e});`)()) });
  }
  const on = target => inScope(scope, "", `return (${enabledOf(target)});`)();
  const protection = qmlFunction(src, "onSinkProtectionTriggered");
  inScope(scope, protection.params, protection.body)("Volume limited to 100%");
  return { volume: on("Audio.sink?.audio ?? null"), brightness: on("Brightness"), gamma: on("Hyprsunset"), warned: root.opened > 0 };
}
const says = r => `volume ${r.volume ? "shows" : "muted"}, brightness ${r.brightness ? "shows" : "muted"}, the protection ${r.warned ? "says it" : "says nothing"}`;

{
  const r = osd({ screenList: ["eDP-1"], focused: "HDMI-A-1" });
  check("on the monitor with no notch, the volume keys show the meter", r.volume, says(r));
  check("on the monitor with no notch, the brightness keys show the meter (and the gamma one)", r.brightness && r.gamma, says(r));
  check("on the monitor with no notch, the volume protection says why it held the volume", r.warned, says(r));
}
{
  const r = osd({ screenList: ["eDP-1"], focused: "eDP-1" });
  check("on the monitor with the notch, the meter stands down for it", !r.volume && !r.brightness && !r.gamma && !r.warned, says(r));
}
{
  const r = osd({ screenList: [], focused: "HDMI-A-1" });
  check("with the notch on every monitor, the meter stands down for it", !r.volume && !r.brightness && !r.warned, says(r));
}
{
  const r = osd({ screenList: [], focused: "eDP-1", locked: true });
  check("on the lock screen, where the notch is not shown, the meter shows", r.volume && r.brightness && r.warned, says(r));
}

done();
