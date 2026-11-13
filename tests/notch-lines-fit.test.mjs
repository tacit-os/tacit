// The notch's lines that say something failed or must be done (Updates.qml's Tonight refused, Restart refused for the
// battery or the download, IslandController.qml's stick pulled out and safe to pull out): long enough to read, and
// whole in their wings. The handlers run under node; the hold is holdFor()'s, the wings wingFor()'s and the notch's
// centreWidth, the split IslandHeader's own parts(), and the wing margins IslandHeader's own anchors. The words are
// measured by Qt in the notch's fonts (Tacit Sans Condensed 15 at 560 for the point, 450 for the rest), with no status
// mark and with one beside them.
import { existsSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { adapterDefaults, inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { logged, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the notch's failure lines are read, and whole (Updates.qml, IslandController.qml)");
const updates = read("services/Updates.qml"), ic = read("services/IslandController.qml"), header = read("modules/ii/island/IslandHeader.qml");
const devices = read("services/Devices.qml");
const untyped = f => ({ params: f.params.replace(/:\s*[\w.<>]+/g, ""), body: f.body });
const exitedOf = id => {
  const at = updates.lastIndexOf("Process {", updates.indexOf(`id: ${id}`));
  const proc = updates.slice(at, matchBrace(updates, at + "Process ".length) + 1);
  return readExpression(proc, proc.indexOf("onExited:") + "onExited:".length).expr;
};

// ---- what each one asks of the notch
const lines = [];
const request = what => (name, payload) => lines.push({ what, name, payload });
{
  const root = { says: true, tonightSet: false, tonightFailed: "" };
  inScope({ root, IslandController: { request: request("Tonight refused") } }, "", `return (${exitedOf("tonightProc")});`)()(1, 0);
}
for (const [what, out] of [["Restart refused for the battery", "tacit: battery 12\n"], ["Restart's download refused", "error: failed to init transaction (unable to lock database)\n"]]) {
  const root = { says: true, restartFailed: "", restartCause: "", restartBattery: 0 };
  const cause = untyped(qmlFunction(updates, "failureCause"));
  root.failureCause = inScope({ root }, cause.params, cause.body);
  inScope({ root, restartOut: { text: out }, IslandController: { request: request(what) } }, "", `return (${exitedOf("restartProc")});`)()(1, 0);
}
{
  const Devices = { leaving: {} };
  for (const name of ["glyphFor", "nameFor"]) { const f = untyped(qmlFunction(devices, name)); Devices[name] = inScope({ root: Devices }, f.params, f.body); }
  const connAt = ic.lastIndexOf("Connections {", ic.indexOf("target: Devices"));
  const conn = ic.slice(connAt, matchBrace(ic, ic.indexOf("{", connAt)) + 1);
  const stick = { path: "/dev/sdb1", label: "SanDisk Ultra", size: "57.3G", usb: true, loop: false, mountpoint: "/run/media/a/SanDisk Ultra" };
  for (const [what, fn] of [["a stick pulled out without Eject", "onRemoved"], ["a stick safe to pull out", "onUnmounted"]]) {
    const f = untyped(qmlFunction(conn, fn));
    inScope({ root: { warmedUp: true, request: request(what) }, Devices }, f.params, f.body)(stick);
  }
}
check("each of them asks the notch for a line", lines.length === 5, lines.map(l => l.what).join(", "));

// ---- the notch's own numbers for a line: its hold, its wings and how it splits it
const hold = adapterDefaults(read("modules/common/Config.qml")).island.hold;
const holdFor = untyped(qmlFunction(ic, "holdFor")), wingFor = untyped(qmlFunction(ic, "wingFor"));
const parts = untyped(qmlFunction(header, "parts")), lower = untyped(qmlFunction(header, "lower"));
const headerRoot = {};
headerRoot.lower = inScope({ root: headerRoot }, lower.params, lower.body);
headerRoot.parts = inScope({ root: headerRoot }, parts.params, parts.body);
const centreExpr = readExpression(ic, ic.indexOf("readonly property real centreWidth:") + "readonly property real centreWidth:".length).expr;
const loader = id => { const at = header.lastIndexOf("Loader {", header.indexOf(`id: ${id}`)); return header.slice(at, matchBrace(header, at + "Loader ".length) + 1); };
const margin = (block, key, scope) => inScope(scope, "", `return (${readExpression(block, block.indexOf(`${key}:`) + key.length + 1).expr});`)();

// ---- the words, measured by Qt in the notch's fonts
const fontDirs = ["/usr/share/fonts/tacit", join(homedir(), ".local/share/fonts/tacit")];
const fontDir = fontDirs.find(d => existsSync(join(d, "TacitSansCondensed[wght].ttf")) && existsSync(join(d, "TacitSans[wght].ttf")));
const words = lines.map(l => headerRoot.parts(l.name, l.payload));
let measured = null, why = "";
if (!fontDir) why = `Tacit Sans Condensed is not in ${fontDirs.join(" or ")} (tacit-fonts): nothing was measured`;
else {
  const url = f => `file://${join(fontDir, f).replace(/\[/g, "%5B").replace(/\]/g, "%5D")}`;
  const scene = `import QtQuick
Item {
    FontLoader { id: condensed; source: "${url("TacitSansCondensed[wght].ttf")}" }
    FontLoader { id: sans; source: "${url("TacitSans[wght].ttf")}" }
    TextMetrics { id: m; font.pixelSize: 15; font.hintingPreference: Font.PreferNoHinting }
    TextMetrics { id: clock; font.family: sans.name; font.pixelSize: 16; font.variableAxes: ({ "wght": 500 }); font.features: ({ "tnum": 1 }); font.hintingPreference: Font.PreferNoHinting; text: "00:00" }
    function w(text, wght) { m.font.family = condensed.name; m.font.variableAxes = ({ "wght": wght }); m.text = text; return Math.ceil(m.advanceWidth); }
    Component.onCompleted: {
        const words = ${JSON.stringify(words)};
        console.log("measured " + JSON.stringify({ fonts: condensed.status === FontLoader.Ready && sans.status === FontLoader.Ready && condensed.name === "Tacit Sans Condensed",
            clock: Math.ceil(clock.advanceWidth), words: words.map(p => [w(p.point, 560), w(p.rest, 450)]) }));
        Qt.quit();
    }
}
`;
  try { measured = logged(runScene({ "scene.qml": scene }), "measured"); } catch (e) { why = e.message; }
  if (measured && !measured.fonts) { why = "Qt did not load the notch's fonts"; measured = null; }
}
check("the notch's fonts are measured by Qt", measured !== null, why);

// the wings' room (IslandHeader): the left from its 10 px edge to 8 px before the time; the right from 8 px after the time
// to the edge, or to the status mark (18 px, Material Symbols are one em wide) and its gaps
function room(name, payload, mark) {
  const root = { payload, signinSheetWidth: 0, focusRunning: false, mediaVisible: false };
  const wing = inScope({ root, AgentSessions: { active: null } }, wingFor.params, wingFor.body)(name);
  const centre = inScope({ root: { clockWidth: measured.clock, ambientGlyph: mark ? "bolt" : "", coffeeAside: false, recording: false, notchHovered: false },
    clock24: { advanceWidth: measured.clock } }, "", `return (${centreExpr});`)();
  const half = (centre + 2 * wing) / 2 - measured.clock / 2;
  const left = loader("leftWing"), right = loader("rightWing");
  const scope = { statusSlot: { visible: mark, width: 18 }, coffeeMark: { visible: false, width: 18 } };
  return { left: half - margin(left, "anchors.leftMargin", scope) - margin(left, "anchors.rightMargin", scope),
    right: half - margin(right, "anchors.leftMargin", scope) - margin(right, "anchors.rightMargin", scope) };
}

lines.forEach((l, i) => {
  const ms = inScope({ root: { payload: l.payload }, Config: { options: { island: { hold } } } }, holdFor.params, holdFor.body)(l.name);
  check(`${l.what}: held to be read, not flashed`, ms >= 4000, `"${l.payload.text}" is shown for ${ms} ms as "${l.name}"`);
  if (!measured) return;
  const [point, rest] = measured.words[i];
  for (const mark of [false, true]) {
    const r = room(l.name, l.payload, mark);
    check(`${l.what}: whole ${mark ? "beside a status mark" : "at rest"}`, point <= r.left && rest <= r.right,
      `"${words[i].point}" ${point} px in ${r.left} px, "${words[i].rest}" ${rest} px in ${r.right} px`);
  }
});
done();
