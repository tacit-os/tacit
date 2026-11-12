// The volume keys and the volume protection (services/Audio.qml) run under node on a pretend output: the file's own
// incrementVolume(), its bindings (value, keyMaxValue, hardMaxValue) and its protection handler, with the settings an
// old settings file comes out of Config.migrate() with.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { adapterDefaults, inScope, loadInto, matchBrace, qmlFunction, qmlProperty, runMigrate } from "./lib/qml.mjs";
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

done();
