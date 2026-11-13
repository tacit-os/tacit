// Settings > Display & power, a second change picked while the first is being written (tacit-settings.qml): the page's
// setMonitor(), its write's onExited and its hyprctl monitors reader run under node on two pretend screens, with a
// stand-in Process that starts only when it is not running already, as Quickshell's does. The second change must run
// once the first has landed, built on the screens as the first left them.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("tacit-settings.qml");
const pageAt = src.indexOf("id: displayPage");
const page = src.slice(pageAt, matchBrace(src, src.indexOf("{", src.indexOf("ColumnLayout", pageAt))));
function block(marker, key) {
  const at = page.indexOf(key, page.indexOf(marker));
  const open = page.indexOf("{", at);
  return page.slice(open + 1, matchBrace(page, open));
}
const hyprctl = laptopScale => JSON.stringify([
  { id: 0, name: "eDP-1", description: "BOE 0x0BCA", width: 2880, height: 1800, refreshRate: 60, x: 0, y: 0, scale: laptopScale, transform: 0, availableModes: ["2880x1800@60.00Hz"], mirrorOf: "none" },
  { id: 1, name: "HDMI-A-1", description: "Dell U2723QE", width: 3840, height: 2160, refreshRate: 60, x: Math.round(2880 / laptopScale), y: 0, scale: 1.5, transform: 0, availableModes: ["3840x2160@60.00Hz", "2560x1440@59.95Hz"], mirrorOf: "none" },
]);

// a Process: what it ran, each time it started
function proc(started) {
  let running = false;
  return { command: null, get running() { return running; }, set running(v) { if (v && !running) started.push(this.command); running = !!v; } };
}
const started = [];
const dp = { screens: [], monitorsFileOurs: true, settling: false, waitingChanges: [] };
const scope = { dp, root: { displayKeepLeft: 0, displayBackupBase: "" }, readScreens: proc([]), readMonitorsFile: proc([]), writeMonitors: proc(started) };
for (const name of ["outputOf", "monitorLine", "shiftedPosition", "setMonitor"]) { const f = qmlFunction(page, name); if (f) dp[name] = inScope(scope, f.params, f.body); }
const readDone = inScope(scope, "text", block("id: readScreens", "onStreamFinished:"));
const writeExited = inScope(scope, "exitCode", block("id: writeMonitors", "onExited:"));
// a screen's line, by its connector or its description
const laptop = ["eDP-1", "BOE 0x0BCA"], monitor = ["HDMI-A-1", "Dell U2723QE"];
const lineOf = (cmd, keys) => (cmd ?? []).find(l => l.includes("hl.monitor(") && keys.some(k => l.includes(`"${k}"`) || l.includes(`"desc:${k}"`))) ?? "";

console.log("== a second display change while the first is written (tacit-settings.qml)");
readDone(hyprctl(1));
dp.setMonitor("eDP-1", { scale: 2 });                       // 200 % on the laptop: hyprctl reload takes a moment
dp.setMonitor("HDMI-A-1", { mode: "2560x1440@59.95" });     // and meanwhile a new resolution on the monitor
check("the first change is written at once", started.length === 1 && /scale = 2\b/.test(lineOf(started[0], laptop)), lineOf(started[0], laptop));
scope.writeMonitors.running = false;                        // the first write ends, and the page reads the screens
writeExited(0);
scope.readScreens.running = false;
readDone(hyprctl(2));
check("the second change is written once the first has landed", started.length === 2, `${started.length} write(s)`);
check("with the resolution picked", /mode = "2560x1440@59.95"/.test(lineOf(started[1], monitor)), lineOf(started[1], monitor));
check("built on the screens as the first left them (the laptop stays at 200 %)", /scale = 2\b/.test(lineOf(started[1], laptop)), lineOf(started[1], laptop));
scope.writeMonitors.running = false;
writeExited(0);
scope.readScreens.running = false;
readDone(hyprctl(2));
check("and nothing more is written after it", started.length === 2, `${started.length} writes`);
dp.setMonitor("eDP-1", { scale: 1 });
check("a later change is written at once again", started.length === 3, `${started.length} writes`);
done();
