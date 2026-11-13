// The control panel's volume bar (modules/ii/sidebarRight/SidebarRightContent.qml) against the ear protection
// (services/Audio.qml): the bar's own onMoved, Audio's functions and timer, and the protection's handler run under node
// on a pretend output that keeps its level as a float, as Quickshell does, and is heard at once by the protection.
import { adapterDefaults, inScope, matchBrace, qmlFunction, readExpression, runMigrate } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the control panel's volume bar and the ear protection");
const audioSrc = read("services/Audio.qml");
const panelSrc = read("modules/ii/sidebarRight/SidebarRightContent.qml");
const configSrc = read("modules/common/Config.qml");
const fresh = () => runMigrate(configSrc, adapterDefaults(configSrc)).options;

// the protection: the Connections block whose onVolumeChanged it is, with the properties it keeps
const protect = qmlFunction(audioSrc, "onVolumeChanged");
const connAt = audioSrc.lastIndexOf("Connections {", audioSrc.search(/function\s+onVolumeChanged/));
const connBlock = audioSrc.slice(connAt, matchBrace(audioSrc, audioSrc.indexOf("{", connAt)));
const connProps = {};
for (const m of connBlock.matchAll(/^\s*property\s+(\w+)\s+(\w+)\s*:\s*(.+)$/gm)) connProps[m[2]] = JSON.parse(m[3].replace(/\s*\/\/.*$/, ""));

// the bar: the LineSlider labelled Volume, and its onMoved
const barAt = panelSrc.lastIndexOf("LineSlider {", panelSrc.indexOf('label: Translation.tr("Volume")'));
const bar = panelSrc.slice(barAt, matchBrace(panelSrc, panelSrc.indexOf("{", barAt)) + 1);
const moved = bar.match(/onMoved:\s*(\w+)\s*=>\s*\{/);
const movedBody = bar.slice(moved.index + moved[0].length, matchBrace(bar, moved.index + moved[0].length - 1));

function panel(options, volume) {
  const said = [], rises = [];
  let heard = () => {};
  const a = { muted: false, _v: Math.fround(volume) };
  Object.defineProperty(a, "volume", { get: () => a._v, set: x => {
    const v = Math.fround(Math.max(0, x));
    if (v === a._v) return;
    rises.push(v - a._v);
    a._v = v;
    heard();
  } });
  const root = { sink: { audio: a, ready: true }, sinkProtectionTriggered: reason => said.push(reason),
    climbAudio: null, climbTarget: 0, climbWrote: 0 };
  const Translation = { tr: s => ({ arg: x => s.replace("%1", x) }) };
  const timers = {};
  const scope = { root, Audio: root, Config: { options }, Translation };
  for (const m of audioSrc.matchAll(/\bTimer\s*\{/g)) {
    const body = audioSrc.slice(m.index, matchBrace(audioSrc, m.index + m[0].length - 1));
    const id = body.match(/\bid:\s*(\w+)/)?.[1];
    if (!id) continue;
    const t = { running: false, start() { this.running = true; }, stop() { this.running = false; }, restart() { this.running = true; } };
    t.fire = inScope(scope, "", readExpression(body, body.indexOf("onTriggered:") + "onTriggered:".length).expr);
    scope[id] = timers[id] = t;
  }
  for (const name of ["setVolume", "climbVolume"]) {
    const f = qmlFunction(audioSrc, name);
    if (f) root[name] = inScope(scope, f.params, f.body);
  }
  const conn = Object.assign(Object.create({ root, sink: root.sink, Config: { options }, Translation }), structuredClone(connProps));
  const run = inScope(conn, protect.params, protect.body);
  let depth = 0;
  heard = () => { if (depth > 8) throw new Error("the protection keeps setting the volume"); depth++; try { run(); } finally { depth--; } };
  heard();                             // the protection's first look takes the level as it is
  const onMoved = inScope(scope, moved[1], movedBody);
  let ticks = 0;
  return {
    a, said, rises, ticks: () => ticks, climbing: () => Object.values(timers).some(t => t.running),
    // a press at x on the bar: the kit's Slider says moved there; then the timers' ticks until none runs (at most 200)
    press(x) {
      onMoved(x);
      while (Object.values(timers).some(t => t.running) && ticks < 200) { ticks++; for (const t of Object.values(timers)) if (t.running) t.fire(); }
    },
  };
}
const pct = v => `${Math.round(v * 1000) / 10}%`;

{
  const p = panel(fresh(), 0.2);
  p.press(0.7);
  const most = Math.max(...p.rises);
  check("at 20%, a press on the panel's bar at 70% takes the output to 70%, in steps the ear protection lets through",
    Math.abs(p.a.volume - 0.7) < 0.006 && !p.said.length && most <= 0.1,
    `it ends at ${pct(p.a.volume)}, the biggest rise written was ${pct(most)}${p.said.length ? `, the protection said "${p.said.at(-1)}"` : ""}`);
  p.press(0.7);
  check("and a second press there keeps it at 70%", Math.abs(p.a.volume - 0.7) < 0.006 && !p.said.length, pct(p.a.volume));
}
{
  const p = panel(fresh(), 0.7);
  p.press(0.3);
  check("a press lower, at 30% from 70%, goes there with one write", Math.abs(p.a.volume - 0.3) < 0.006 && p.rises.length === 1,
    `it ends at ${pct(p.a.volume)} after ${p.rises.length} writes`);
}
{
  const p = panel(fresh(), 0.5);
  for (const x of [0.52, 0.55, 0.57, 0.6]) p.press(x);
  check("a drag up in small moves follows the pointer", Math.abs(p.a.volume - 0.6) < 0.006 && !p.said.length, pct(p.a.volume));
}
{
  const o = fresh();
  o.audio.protection.maxAllowed = 60;
  const p = panel(o, 0.2);
  p.press(0.9);
  check("with Loudest allowed at 60%, a press at 90% climbs to under 60% and stops writing",
    p.a.volume > 0.5 && p.a.volume <= 0.6 && !p.climbing() && p.ticks() < 200,
    `it ends at ${pct(p.a.volume)} after ${p.ticks()} ticks${p.climbing() ? ", still climbing" : ""}`);
}
{
  const o = fresh();
  o.audio.protection.enable = false;
  const p = panel(o, 0.2);
  p.press(0.9);
  check("with the protection off, a press at 90% is one write", Math.abs(p.a.volume - 0.9) < 0.006 && p.rises.length === 1,
    `it ends at ${pct(p.a.volume)} after ${p.rises.length} writes`);
}
done();
