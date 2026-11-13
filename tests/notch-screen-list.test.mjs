// The notch opened from a key with Settings > Notch limited to some screens (island.screenList) and the focus on a screen
// without one (services/IslandController.qml): openAsk(), openRecord(), stopRecording() and the `island open` IPC call,
// the file's own, under node, and each notch's keyScreen (modules/ii/island/IslandContent.qml), which decides whether it
// answers the key. A notch must answer, or nothing opens while the keyboard is taken.
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the notch from a key, with the notch on some screens only (IslandController.qml)");
const src = read("services/IslandController.qml");
const keyScreen = qmlProperty(read("modules/ii/island/IslandContent.qml"), "keyScreen");

function desk(screens, screenList, focused) {
  const root = { enabled: true, suppressed: false, recording: false, keyboard: false, keyboardScreen: "",
    recordRequested() {}, askRequested() {}, openRequested() {} };
  const scope = { root, Hyprland: { focusedMonitor: { name: focused } }, Config: { options: { island: { screenList } } },
    Quickshell: { screens: screens.map(name => ({ name })), execDetached() {} }, Claude: { invoke() {} }, GlobalStates: {},
    Directories: { recordScriptPath: "record.sh" } };
  for (const name of ["openAsk", "openRecord", "stopRecording", "open", "keyScreenName"]) {
    const f = qmlFunction(src, name);
    if (f) root[name] = inScope(scope, f.params.replace(/:\s*\w+/g, ""), f.body);
  }
  // the notches there are (Island.qml: one per listed screen, or every screen), and which of them answer the key
  const notches = screens.filter(s => !screenList.length || screenList.includes(s));
  const answering = () => notches.filter(s => inScope({ root: { screenData: { name: s } }, IslandController: root }, "", `return (${keyScreen});`)());
  return { root, answering };
}

for (const [how, press] of [["Super+Shift+Space (Ask)", r => r.openAsk("shortcut", [], "")], ["Super+Space (island open)", r => r.open()],
  ["the record key", r => r.openRecord()]]) {
  const d = desk(["eDP-1", "HDMI-A-1"], ["eDP-1"], "HDMI-A-1");
  press(d.root);
  check(`${how} with the focus on the screen without a notch opens the laptop's notch`, d.answering().join() === "eDP-1",
    `the keyboard is on ${JSON.stringify(d.root.keyboardScreen)}, ${d.answering().length ? d.answering().join() : "no notch"} answers`);
}
{
  const d = desk(["eDP-1", "HDMI-A-1"], ["eDP-1"], "HDMI-A-1");
  d.root.recording = true;
  d.root.openRecord();                 // the record key again: stops it, and the saved card goes to a notch that is there
  check("a recording stopped there shows its saved card on the laptop's notch", d.answering().join() === "eDP-1",
    `the card goes to ${JSON.stringify(d.root.keyboardScreen)}`);
}
{
  const d = desk(["eDP-1", "HDMI-A-1", "DP-1"], ["DP-2", "DP-1", "eDP-1"], "HDMI-A-1");
  d.root.openAsk("shortcut", [], "");
  check("with several listed, the first one connected answers", d.answering().join() === "DP-1", JSON.stringify(d.root.keyboardScreen));
}
{
  const d = desk(["eDP-1", "HDMI-A-1"], ["eDP-1", "HDMI-A-1"], "HDMI-A-1");
  d.root.openAsk("shortcut", [], "");
  check("a focused screen with a notch keeps the key", d.answering().join() === "HDMI-A-1", JSON.stringify(d.root.keyboardScreen));
  const all = desk(["eDP-1", "HDMI-A-1"], [], "HDMI-A-1");
  all.root.open();
  check("and with the notch on every screen, the focused one answers alone", all.answering().join() === "HDMI-A-1", JSON.stringify(all.root.keyboardScreen));
}
done();
