// The mic's mute key (services/IslandController.qml): the notch's handler for the default source's mute, its requestMic()
// and holdFor(), and the resting glyph's binding, run under node. The key must be answered on screen, and a muted mic
// that an app still holds must not show as the live mic.
import { inScope, matchBrace, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the mic's mute key (IslandController.qml)");
const src = read("services/IslandController.qml");
const said = [];
const Audio = { ready: true, sink: { audio: { muted: false } }, source: { ready: true, audio: { muted: false } } };
const Config = { options: { island: { hold: { meter: 1300, greeting: 4200, battery: 4000, timerDone: 3500, power: 2600, notification: 4000,
  network: 2400, workspace: 750, activity: 30000, activityDone: 2000, activityFail: 4000, download: 3000 } } } };
const root = { request: (name, data) => said.push({ name, ...data }) };
const scope = { root, Audio, Config };
for (const name of ["requestMic", "holdFor"]) {
  const f = qmlFunction(src, name);
  if (f) root[name] = inScope(scope, f.params, f.body);
}

// the Connections that follows the default source's mute, as the mute key flips it
{
  const at = src.search(/target:\s*Audio\.source\b/);
  let handler = null;
  if (at >= 0) {
    const open = src.lastIndexOf("Connections {", at) + "Connections ".length;
    const f = qmlFunction(src.slice(open, matchBrace(src, open) + 1), "onMutedChanged");
    if (f) handler = inScope(scope, f.params, f.body);
  }
  const press = muted => { Audio.source.audio.muted = muted; const n = said.length; handler?.(); return said[n]; };
  const off = press(true), on = press(false);
  check("the mute key is answered in the notch: muted, then on again",
    off?.name === "mic" && /muted/i.test(off.text) && on?.name === "mic" && !/muted/i.test(on.text), JSON.stringify(said));
  check("for as short a time as a volume key's", root.holdFor?.("mic") === root.holdFor?.("volume"),
    `${root.holdFor?.("mic")} ms against ${root.holdFor?.("volume")} ms`);
}

// the resting glyph while an app has the mic (a call)
{
  const expr = qmlProperty(src, "ambientGlyph");
  const glyph = muted => {
    Audio.source.audio.muted = muted;
    return inScope({ root: { chargerFault: false, micLive: true }, Audio }, "", expr.slice(1, -1))();
  };
  check("an app holding the mic shows the mic while it hears, and the mic struck through while muted",
    glyph(false) === "mic" && glyph(true) === "mic_off", `${glyph(false)}, ${glyph(true)}`);
}
done();
