// The volume keys and the volume protection (services/Audio.qml) run under node on a pretend output: the file's own
// incrementVolume(), its bindings (value, keyMaxValue, hardMaxValue) and its protection handler, with the settings an
// old settings file comes out of Config.migrate() with. And the bar on Settings > Sound against that protection.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { adapterDefaults, inScope, loadInto, matchBrace, qmlFunction, qmlProperty, readExpression, runMigrate } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const audioSrc = read("services/Audio.qml");
const configSrc = read("modules/common/Config.qml");
const releases = join(dirname(fileURLToPath(import.meta.url)), "config", "releases");
const releaseFile = v => JSON.parse(readFileSync(join(releases, JSON.parse(readFileSync(join(releases, "index.json"), "utf8")).find(e => e.version === v).file), "utf8"));
const settings = file => runMigrate(configSrc, loadInto(adapterDefaults(configSrc), file)).options;

// the Connections block whose onVolumeChanged is the protection, and the properties it keeps
const handler = qmlFunction(audioSrc, "onVolumeChanged");
const connAt = audioSrc.lastIndexOf("Connections {", audioSrc.search(/function\s+onVolumeChanged/));
const connBlock = audioSrc.slice(connAt, matchBrace(audioSrc, audioSrc.indexOf("{", connAt)));
const connProps = {};
for (const m of connBlock.matchAll(/^\s*property\s+(\w+)\s+(\w+)\s*:\s*(.+)$/gm)) connProps[m[2]] = JSON.parse(m[3].replace(/\s*\/\/.*$/, ""));

// A desktop with one output, the Audio singleton built from the file. setVolume() is what PipeWire does with a write:
// the value changes and the Connections whose target is that output's audio hears it, at once.
function desktop(options, volume) {
  const said = [];
  const node = v => {
    const a = { muted: false, _v: v };
    Object.defineProperty(a, "volume", { get: () => a._v, set: x => { if (x === a._v) return; a._v = x; if (root.sink?.audio === a) heard(); } });
    return { audio: a, ready: true };
  };
  const root = { sink: node(volume), sinkProtectionTriggered: reason => said.push(reason) };
  const scope = { root, Audio: root, Config: { options }, Translation: { tr: s => ({ arg: x => s.replace("%1", x) }) } };
  const bind = name => { const e = qmlProperty(audioSrc, name); return e === null ? undefined : inScope(scope, "", `return (${e});`)(); };
  for (const name of ["value", "hardMaxValue", "keyMaxValue"]) Object.defineProperty(root, name, { get: () => bind(name) });
  Object.defineProperty(scope, "sink", { get: () => root.sink });
  for (const name of ["incrementVolume", "decrementVolume"]) { const f = qmlFunction(audioSrc, name); root[name] = inScope(scope, f.params, f.body); }
  const conn = Object.assign(Object.create(scope), structuredClone(connProps));
  let depth = 0;
  const run = inScope(conn, handler.params, handler.body);
  function heard() { if (depth > 8) throw new Error("the protection keeps setting the volume"); depth++; try { run(); } finally { depth--; } }
  return { root, said, node, press: n => { for (let i = 0; i < n; i++) root.incrementVolume(); }, heard };
}
const pct = v => `${Math.round(v * 1000) / 10}%`;

console.log("The volume keys and the volume protection (services/Audio.qml)");

// 1.2.14 changed the default to 100 but a file from before kept 99, and the keys stopped at 99% (#83)
{
  const d = desktop(settings(releaseFile("1.2.13")), 0.5);
  d.heard();                           // the protection's first look takes the level as it is
  d.press(40);
  const v = d.root.sink.audio.volume;
  check("with a settings file from 1.2.13, the volume-up key reaches 100%", Math.abs(v - 1) < 1e-9, `it stops at ${pct(v)}${d.said.length ? `, the protection said "${d.said.at(-1)}"` : ""}`);
}

// before 143f308 both keys stopped at 100% whatever Settings allowed
{
  const o = settings(releaseFile("1.2.13"));
  o.audio.protection.maxAllowed = 150;
  const d = desktop(o, 0.9);
  d.heard();
  d.press(40);
  const v = d.root.sink.audio.volume;
  check("with Loudest allowed at 150%, the volume-up key reaches 150%", Math.abs(v - 1.5) < 1e-9, `it stops at ${pct(v)}`);
}

// before 29ffb51 the protection kept the old output's level, and took the first change on a new output back to it
{
  const d = desktop(settings(releaseFile("1.2.13")), 0.3);
  d.heard();
  d.press(1);                          // the protection knows the speakers at 32%
  d.root.sink = d.node(0.8);           // headphones arrive at 80% and become the output
  d.press(1);
  const v = d.root.sink.audio.volume;
  check("on a new output, the first key press goes from that output's level", Math.abs(v - 0.82) < 1e-9, `80% went to ${pct(v)}${d.said.length ? `, the protection said "${d.said.at(-1)}"` : ""}`);
}

// before 1f7e80f the volume binding threw while the output's audio was not bound yet (after boot, a switch)
{
  const d = desktop(settings(releaseFile("1.2.13")), 0.5);
  d.root.sink = { audio: null, ready: false };
  let v, err = "";
  try { v = d.root.value; d.press(1); } catch (e) { err = e.message; }
  check("an output whose audio is not bound yet reads 0 and a key does nothing", !err && v === 0, err || `it reads ${v}`);
}

// The volume-up key itself (session/hypr/hyprland/keybinds.lua), pressed with the shell running: what its command does.
// Before this the key ran wpctl with its own limit of 100% (-l 1.0), and only the notch's wheel went through Audio.qml.
{
  const lua = read("session/hypr/hyprland/keybinds.lua");
  const ipc = JSON.parse(lua.match(/local qsIpcCall = ("[^"]*")/)[1]);
  const m = lua.match(/hl\.bind\("XF86AudioRaiseVolume", hl\.dsp\.exec_cmd\((.+?)\),\s*\n/);
  const cmd = m[1].replace(/qsIpcCall \.\. "([^"]*)"/, (_, rest) => JSON.stringify(ipc + rest)).replace(/^"|"$/g, "");
  const o = settings(releaseFile("1.2.13"));
  o.audio.protection.maxAllowed = 150;
  const d = desktop(o, 0.9);
  d.heard();
  // the shell answers "qs ipc call <target> <function>" from the IpcHandler of that target in Audio.qml
  const key = () => {
    const call = cmd.match(/ipc call (\w+) (\w+)/);
    if (call) {
      const at = audioSrc.indexOf(`target: "${call[1]}"`);
      const f = at >= 0 ? qmlFunction(audioSrc.slice(at), call[2]) : null;
      if (f) return inScope({ root: d.root }, f.params, f.body)();
    }
    const w = cmd.match(/wpctl set-volume @DEFAULT_AUDIO_SINK@ (\d+)%\+(?: -l ([\d.]+))?/);
    const a = d.root.sink.audio;
    a.volume = Math.min(w[2] ? +w[2] : Infinity, Math.round((a.volume + w[1] / 100) * 1000) / 1000);
  };
  for (let i = 0; i < 40; i++) key();
  const v = d.root.sink.audio.volume;
  check("with Loudest allowed at 150%, the real volume-up key reaches 150%", Math.abs(v - 1.5) < 1e-9, `it stops at ${pct(v)} (${cmd})`);
}

// Settings > Sound's bar (the Ruler with id volumeSlider in tacit-settings.qml): its own onMoved, functions and timer,
// with two protections listening to the output as on a desktop, Settings' own Audio and the shell's. The output keeps
// its level as a float, as Quickshell does (QVector<float>), and a write is heard at once in the process that made it.
const settingsSrc = read("tacit-settings.qml");
const rulerAt = settingsSrc.lastIndexOf("Ruler {", settingsSrc.indexOf("id: volumeSlider"));
const ruler = settingsSrc.slice(rulerAt, matchBrace(settingsSrc, settingsSrc.indexOf("{", rulerAt)) + 1);
function soundPage(options, volume) {
  const said = [], rises = [], listeners = [];
  const a = { muted: false, _v: Math.fround(volume) };
  Object.defineProperty(a, "volume", { get: () => a._v, set: x => {
    const v = Math.fround(Math.max(0, x));
    if (v === a._v) return;
    rises.push(v - a._v);
    a._v = v;
    for (const l of listeners) l();
  } });
  const audio = { sink: { audio: a, ready: true }, sinkProtectionTriggered: reason => said.push(reason) };
  for (let i = 0; i < 2; i++) {
    const conn = Object.assign(Object.create({ root: audio, sink: audio.sink, Config: { options },
      Translation: { tr: s => ({ arg: x => s.replace("%1", x) }) } }), structuredClone(connProps));
    const run = inScope(conn, handler.params, handler.body);
    let depth = 0;
    const heard = () => { if (depth > 8) throw new Error("the protection keeps setting the volume"); depth++; try { run(); } finally { depth--; } };
    heard();                           // the first look takes the level as it is
    listeners.push(heard);
  }
  const bar = { value: a.volume, pressed: false };
  const scope = { volumeSlider: bar, Audio: audio, Config: { options } };
  for (const m of ruler.matchAll(/^\s*property\s+\w+\s+(\w+)\s*:\s*(.+)$/gm)) bar[m[1]] = inScope(scope, "", `return (${m[2]});`)();
  const timers = [];
  for (const m of ruler.matchAll(/\bTimer\s*\{/g)) {
    const body = ruler.slice(m.index, matchBrace(ruler, m.index + m[0].length - 1));
    const t = { running: false, start() { this.running = true; }, stop() { this.running = false; }, restart() { this.running = true; } };
    scope[body.match(/\bid:\s*(\w+)/)[1]] = t;
    const on = body.indexOf("onTriggered:");
    t.fire = inScope(scope, "", readExpression(body, on + "onTriggered:".length).expr);
    timers.push(t);
  }
  for (const m of ruler.matchAll(/\bfunction\s+(\w+)\s*\(/g)) { const f = qmlFunction(ruler, m[1]); bar[m[1]] = inScope(scope, f.params, f.body); }
  const on = ruler.indexOf("onMoved:") + "onMoved:".length;
  const open = ruler.slice(on).match(/^\s*\{/);
  const moved = inScope(scope, "", open ? ruler.slice(on + open[0].length, matchBrace(ruler, on + open[0].length - 1)) : readExpression(ruler, on).expr);
  // the timers' ticks until none runs, at most 200 of them
  let ticks = 0;
  const wait = () => { while (timers.some(t => t.running) && ticks < 200) { ticks++; for (const t of timers) if (t.running) t.fire(); } };
  return {
    a, said, rises, bar, timers, ticks: () => ticks,
    // a press at x moves the knob there and says moved; on release the Binding puts the knob on the real level
    click(x) { bar.pressed = true; bar.value = x; moved(); wait(); bar.pressed = false; bar.value = a.volume; },
    // a Slider's arrow key with no stepSize: a tenth of its range
    key() { bar.value = Math.min(1, bar.value + 0.1); moved(); wait(); bar.value = a.volume; },
  };
}
const fresh = () => runMigrate(configSrc, adapterDefaults(configSrc)).options;

// before this a click more than 10% up went to the output and was taken back at once, so the knob came back
{
  const p = soundPage(fresh(), 0.2);
  p.click(0.7);
  const v = p.a.volume, most = Math.max(...p.rises);
  check("at 20%, a click on the Sound page's bar at 70% takes the output to 70%, in steps the ear protection lets through",
    Math.abs(v - 0.7) < 0.006 && !p.said.length && most <= 0.1 && Math.abs(p.bar.value - v) < 1e-9,
    `it ends at ${pct(v)}, the biggest rise written was ${pct(most)}${p.said.length ? `, the protection said "${p.said.at(-1)}"` : ""}`);
}
{
  const p = soundPage(fresh(), 0.5);
  p.key();
  const v = p.a.volume;
  check("at 50%, the bar's arrow key takes the output to 60%", Math.abs(v - 0.6) < 0.006 && !p.said.length,
    `it ends at ${pct(v)}${p.said.length ? `, the protection said "${p.said.at(-1)}"` : ""}`);
}
{
  const p = soundPage(fresh(), 0.7);
  p.click(0.3);
  check("a click lower, at 30% from 70%, goes there with one write", Math.abs(p.a.volume - 0.3) < 0.006 && p.rises.length === 1,
    `it ends at ${pct(p.a.volume)} after ${p.rises.length} writes`);
}
{
  const o = fresh();
  o.audio.protection.maxAllowed = 60;
  const p = soundPage(o, 0.2);
  p.click(0.9);
  const v = p.a.volume;
  check("with Loudest allowed at 60%, a click at 90% climbs to under 60% and stops writing",
    v > 0.5 && v <= 0.6 && !p.timers.some(t => t.running) && p.ticks() < 200,
    `it ends at ${pct(v)} after ${p.ticks()} ticks${p.timers.some(t => t.running) ? ", still climbing" : ""}`);
}

done();
