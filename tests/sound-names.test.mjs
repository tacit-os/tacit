// Settings > Sound's device names (tacit-settings.qml soundName()): the card's own speakers and microphones say what
// they lack ("Without tuning", "Without echo cancelling") only beside the tuned chain that has it, which only the Book4
// Edge's package sets up (61-book4-speaker-eq.conf, 62-book4-echo-cancel.conf); on any other computer they are just
// Speakers and Microphones. soundName() runs under node on each computer's pretend PipeWire devices.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Sound's device names (tacit-settings.qml)");
const f = qmlFunction(read("tacit-settings.qml"), "soundName");
function computer(outputDevices, inputDevices) {
  const root = {};
  root.soundName = inScope({ root, Audio: { outputDevices, inputDevices } }, f.params, f.body);
  const say = d => [root.soundName(d).label, root.soundName(d).line].filter(x => x).join(" · ");
  return { outputs: outputDevices.map(say), inputs: inputDevices.map(say) };
}
const speakers = { name: "alsa_output.platform-sound.HiFi__Speaker__sink", description: "Built-in Audio Speaker playback" };
const mics = { name: "alsa_input.platform-sound.HiFi__Mic__source", description: "Built-in Audio Internal Microphones capture" };

{
  const c = computer([speakers], [mics]);
  check("a laptop without the tuned chain: its speakers are Speakers, nothing lacking", c.outputs.join() === "Speakers", c.outputs.join());
  check("and its microphones are Microphones", c.inputs.join() === "Microphones", c.inputs.join());
}
{
  const c = computer([speakers, { name: "book4_speakers_tuned", description: "Speakers (tuned)" },
    { name: "book4_speakers_aec", description: "Speakers (echo cancelled)" }],
    [mics, { name: "book4_mic_aec", description: "Internal microphones (echo cancelled)" }]);
  check("the Book4 Edge: the card's speakers say they are without the tuning beside the tuned ones",
    c.outputs.join(" | ") === "Speakers · Without tuning | Speakers · Tuned | Speakers · Echo cancelled", c.outputs.join(" | "));
  check("and the card's microphones beside the echo-cancelled ones", c.inputs.join(" | ") === "Microphones · Without echo cancelling | Microphones · Echo cancelled",
    c.inputs.join(" | "));
}
{
  const c = computer([speakers, { name: "alsa_output.usb-dac.analog-stereo", description: "Speakers (USB DAC)" }], [mics]);
  check("a second card's speakers with a kind of their own are not a tuned chain", c.outputs[0] === "Speakers", c.outputs.join(" | "));
}
done();
