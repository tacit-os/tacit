// A Bluetooth headset arriving and leaving (services/Audio.qml): the file's own onBluetoothSinkChanged and
// setDefaultSink() run under node on a pretend PipeWire, whose pin reads null once the node it names has gone, as
// Quickshell's does. When the headset leaves, the output goes back to where it was only if nobody chose another since.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a headset arriving and leaving (services/Audio.qml)");
const src = read("services/Audio.qml");
const at = src.indexOf("onBluetoothSinkChanged:");
const open = src.indexOf("{", at);
const handlerBody = src.slice(open + 1, matchBrace(src, open));

function desk() {
  const speakers = { name: "alsa_output.pci-0000_00_1f.3.analog-stereo" };
  const hdmi = { name: "alsa_output.pci-0000_00_1f.3.hdmi-stereo" };
  const headset = { name: "bluez_output.AC_80_0A_12_34_56.1" };
  const nodes = [speakers, hdmi];
  let pin = speakers.name;
  const live = name => nodes.find(n => n.name === name) ?? null;
  const Pipewire = {
    get preferredDefaultAudioSink() { return live(pin); },
    set preferredDefaultAudioSink(n) { pin = n ? n.name : null; },
    get defaultAudioSink() { return live(pin) ?? speakers; },
  };
  const root = { sinkBeforeBluetooth: null };
  Object.defineProperty(root, "bluetoothSink", { get: () => nodes.find(n => n.name.startsWith("bluez_output.")) ?? null });
  const scope = { root, Pipewire };
  const handler = inScope(scope, "", handlerBody);
  const f = qmlFunction(src, "setDefaultSink");
  const setDefaultSink = inScope(scope, f.params, f.body);
  return {
    speakers, hdmi, out: () => Pipewire.defaultAudioSink.name, setDefaultSink,
    connect() { nodes.push(headset); handler(); },
    leave() { nodes.splice(nodes.indexOf(headset), 1); handler(); },
  };
}

{
  const d = desk();
  d.connect();
  d.setDefaultSink(d.hdmi);            // Sound settings, while the headset is on
  d.leave();
  check("HDMI chosen while the headset was on stays the output when the headset leaves", d.out() === d.hdmi.name, `it went to ${d.out()}`);
}
{
  const d = desk();
  d.connect();
  check("a headset that arrives takes the output", d.out().startsWith("bluez_output."), d.out());
  d.leave();
  check("and gives it back to the speakers when it leaves", d.out() === d.speakers.name, `it went to ${d.out()}`);
}
{
  const d = desk();
  d.connect();
  d.setDefaultSink(d.speakers);        // the speakers picked by hand while the headset is on
  d.leave();
  d.connect();
  d.leave();
  check("a second visit of the headset still hands the output back", d.out() === d.speakers.name, `it went to ${d.out()}`);
}
done();
