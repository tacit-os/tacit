// Settings > Lock & sleep showed Never for every time, and kept showing it after a time was picked (Discord, Oyinos:
// "the settings are locked to never"). parseIdle tells a listener turned off by Never from the "#off " that split()
// captures before it; for a listener without one Qt's JavaScript gives "" where node gives undefined, and the check
// was "!== undefined", so under Qt every listener read as turned off. Settings' own idleKind() and parseIdle() run here
// under Qt's qml tool offscreen, on the hypridle.conf files a computer can have: Tacit's packaged one, 1.2.13's, a copy
// Settings made with other times, and one with sleep turned off.
import { readFileSync } from "fs";
import { join } from "path";
import { qmlFunction } from "./lib/qml.mjs";
import { logged, runScene } from "./lib/qtscene.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== Lock & sleep's times as Settings reads them under Qt (tacit-settings.qml parseIdle)");
const settings = read("tacit-settings.qml");
const packaged = readFileSync(join(tree, "session", "xdg", "hypr", "hypridle.conf"), "utf8");
const old = readFileSync(join(tree, "tests", "config", "hypridle-1.2.13.conf"), "utf8");
const mark = "# Made by Settings > Lock & sleep from Tacit's hypridle.conf, with your times: the rest is Tacit's again at each login. Delete this line to keep edits of your own.";
const changed = mark + "\n" + packaged.replace("timeout = 300", "timeout = 120").replace("timeout = 900", "timeout = 3600");
// sleep turned off as setIdleTime does it: each line of its listener behind "#off "
const lines = packaged.split("\n"), at = lines.findIndex(l => l.includes("$suspend_cmd") && /on-timeout/.test(l));
let a = at, b = at;
while (!/^\s*listener\s*\{/.test(lines[a])) a--;
while (!/^\s*\}/.test(lines[b])) b++;
const sleepOff = mark + "\n" + lines.map((l, i) => (i >= a && i <= b ? "#off " + l : l)).join("\n");
const files = { packaged, "1.2.13": old, changed, "sleep off": sleepOff };

const fn = name => { const f = qmlFunction(settings, name); return f ? `function (${f.params}) {${f.body}\n}` : "function () { return {}; }"; };
const scene = `import QtQuick
Item {
    Component.onCompleted: {
        const root = {};
        root.idleKind = ${fn("idleKind")};
        root.parseIdle = ${fn("parseIdle")};
        const files = ${JSON.stringify(files)};
        const out = {};
        for (const k in files)
            out[k] = root.parseIdle(files[k]);
        console.log("TIMES " + JSON.stringify(out));
        Qt.quit();
    }
}
`;
const want = {
  packaged: { lock: 300, screen: 600, sleep: 900 },
  "1.2.13": { lock: 300, screen: 600, sleep: 900 },
  changed: { lock: 120, screen: 600, sleep: 3600 },
  "sleep off": { lock: 300, screen: 600, sleep: 0 },
};
try {
  const got = logged(runScene({ "idle.qml": scene }), "TIMES");
  for (const [k, w] of Object.entries(want))
    check(`${k}: ${JSON.stringify(w)}`, JSON.stringify(got[k]) === JSON.stringify(w), JSON.stringify(got[k]));
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
