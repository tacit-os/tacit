// Super+M and the media corner on two monitors (MediaControls.toNotch, GlobalStates.toggleState): the notch's sheet
// opens on the monitor you are on, not the one an earlier Super+Space was pressed on. Those two, IslandController's
// openMedia() and each notch's keyScreen and onOpenRequested (IslandContent.qml) run under node, the notch's signal
// going to both screens as Quickshell sends it.
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Super+M and the media corner open the notch on the monitor you are on (MediaControls, GlobalStates)");
const media = read("modules/ii/mediaControls/MediaControls.qml");
const states = read("GlobalStates.qml");
const controller = read("services/IslandController.qml");
const content = read("modules/ii/island/IslandContent.qml");

const run = (scope, src, name) => { const f = qmlFunction(src, name); return f ? inScope(scope, f.params, f.body) : null; };

function desktop({ keyboardScreen, focused, screenList = [], keyboard = false, openOn = [] }) {
  const ic = { keyboardScreen, keyboard, ownsMedia: true, enabled: true, suppressed: false, notches: [] };
  ic.openRequested = () => ic.notches.forEach(n => n.onOpenRequested());
  const icScope = { root: ic, Hyprland: { focusedMonitor: { name: focused } }, Config: { options: { island: { screenList } } } };
  const openMedia = run(icScope, controller, "openMedia");
  if (openMedia) ic.openMedia = openMedia;
  const keyScreen = qmlProperty(content, "keyScreen");
  for (const name of screenList.length ? screenList : ["eDP-1", "HDMI-A-1"]) {
    const n = { screenData: { name }, open: openOn.includes(name), signinShown: false, pinnedUntilVisit: false };
    n.openSheet = () => { n.open = true; };
    Object.defineProperty(n, "keyScreen", { get: () => inScope({ root: n, IslandController: ic }, "", `return (${keyScreen});`)() });
    n.onOpenRequested = run({ root: n, IslandController: ic, pinTimer: { restart() {}, stop() {} } }, content, "onOpenRequested");
    ic.notches.push(n);
  }
  const open = () => ic.notches.filter(n => n.open).map(n => n.screenData.name);
  return { ic, open };
}
const superM = d => run({ root: { islandOwnsMedia: true }, IslandController: d.ic }, media, "toNotch")();
const corner = d => run({ root: { hotCornerOptions: [{ value: "mediaControlsOpen" }], mediaControlsOpen: false }, IslandController: d.ic }, states, "toggleState")("mediaControlsOpen");
const where = d => `open on [${d.open().join(", ")}]`;

{
  const d = desktop({ keyboardScreen: "eDP-1", focused: "HDMI-A-1" });   // Super+Space on the laptop earlier
  superM(d);
  check("Super+M on the second monitor opens its notch, not the laptop's", d.open().join() === "HDMI-A-1", where(d));
  check("and does not take the keyboard", d.ic.keyboard === false);
}
{
  const d = desktop({ keyboardScreen: "eDP-1", focused: "HDMI-A-1" });
  corner(d);
  check("resting in the second monitor's media corner opens its notch, not the laptop's", d.open().join() === "HDMI-A-1", where(d));
}
{
  const d = desktop({ keyboardScreen: "HDMI-A-1", focused: "eDP-1" });
  superM(d);
  check("and back on the laptop, Super+M opens the laptop's", d.open().join() === "eDP-1", where(d));
}
{
  const d = desktop({ keyboardScreen: "eDP-1", focused: "HDMI-A-1", keyboard: true, openOn: ["eDP-1"] });   // Ask is being typed in
  superM(d);
  check("a sheet holding the keyboard keeps it: Super+M elsewhere does not move it", d.ic.keyboardScreen === "eDP-1" && d.open().join() === "eDP-1", where(d));
}
{
  const d = desktop({ keyboardScreen: "", focused: "HDMI-A-1", screenList: ["eDP-1"] });   // Settings > Notch: the laptop only
  superM(d);
  check("on a monitor with no notch, Super+M still opens the notch there is", d.open().join() === "eDP-1", where(d));
}
done();
