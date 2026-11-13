// Settings > Display & power's battery line (tacit-settings.qml): its times and "not charging" must be the shell's
// Battery's, measured from the pack's own energy as the notch shows them, not UPower's own estimates, which swing and
// say "Charging" while a capped charger lets the pack drain. Settings is its own process and each visit starts a new
// copy of Battery with no samples, which has no time for four minutes, so the line asks the shell's (battery times).
// The line's bindings run under node with a pretend UPower device; the asking runs under qmltestrunner offscreen beside
// a stand-in Process that answers as Quickshell 0.3.2's qs does, printing what Battery.qml's own times() returns.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the battery line on Display & power (tacit-settings.qml)");
const src = read("tacit-settings.qml");
const at = src.indexOf('eyebrow: "Battery"');
const summary = src.slice(src.lastIndexOf("Summary {", at), src.indexOf("live:", at));
const expr = name => {
  const m = new RegExp(`\\n\\s*(?:readonly property \\w+ )?${name}:\\s*`).exec(summary);
  return m ? readExpression(summary, m.index + m[0].length).expr : "undefined";
};
const batteryTime = secs => { const t = Math.round(secs / 60), h = Math.floor(t / 60), m = t % 60; return h > 0 ? `${h} h ${m} min` : `${m} min`; };
const UPowerDeviceState = { Charging: 1, Discharging: 2, FullyCharged: 4 };
// Battery is this process's own copy, just started: nothing measured yet. shell is what the shell answered.
function line(b, shell, onBattery) {
  const scope = { b, Battery: { drainingOnAc: false, timeToFull: 0, timeToEmpty: 0 }, UPower: { onBattery }, UPowerDeviceState,
    root: { batteryTime, shellBattery: shell } };
  scope.times = inScope(scope, "", `return (${expr("times")});`)();
  scope.charging = inScope(scope, "", `return (${expr("charging")});`)();
  return inScope(scope, "", `return (${expr("subtitle")});`)();
}
const shell = (t = {}) => ({ timeToEmpty: 0, timeToFull: 0, drainingOnAc: false, ...t });

// a capped charger: UPower says charging and full in 6 h 20 min, the pack's energy goes down
check("plugged in while the pack drains says so at once, as the notch does",
  line({ state: 1, percentage: 0.57, timeToFull: 22800 }, shell({ drainingOnAc: true }), false) === "Plugged in, not charging",
  line({ state: 1, percentage: 0.57, timeToFull: 22800 }, shell({ drainingOnAc: true }), false));
check("charging shows the shell's time to full at once, not UPower's",
  line({ state: 1, timeToFull: 32400 }, shell({ timeToFull: 3600 }), false) === "Charging · full in 1 h 0 min",
  line({ state: 1, timeToFull: 32400 }, shell({ timeToFull: 3600 }), false));
check("on battery shows the shell's time left at once, not UPower's",
  line({ state: 2, timeToEmpty: 11400 }, shell({ timeToEmpty: 9000 }), true) === "2 h 30 min left",
  line({ state: 2, timeToEmpty: 11400 }, shell({ timeToEmpty: 9000 }), true));
check("before the shell's Battery has measured a rate, no time is shown, as in the notch",
  line({ state: 2, timeToEmpty: 11400 }, shell(), true) === "On battery" && line({ state: 1, timeToFull: 5000 }, shell(), false) === "Charging",
  `${line({ state: 2, timeToEmpty: 11400 }, shell(), true)} / ${line({ state: 1, timeToFull: 5000 }, shell(), false)}`);
check("a trickle charge past 12 h is still 'slowly'", line({ state: 1 }, shell({ timeToFull: 50000 }), false) === "Charging slowly",
  line({ state: 1 }, shell({ timeToFull: 50000 }), false));
check("while the shell has not answered yet, no time (none that changes a moment later)",
  line({ state: 2, timeToEmpty: 11400 }, undefined, true) === "On battery", line({ state: 2, timeToEmpty: 11400 }, undefined, true));
check("with no shell answering, UPower's own times, as 1.2.14 showed them",
  line({ state: 2, timeToEmpty: 11400 }, null, true) === "3 h 10 min left" && line({ state: 1, timeToFull: 5000 }, null, false) === "Charging · full in 1 h 23 min",
  `${line({ state: 2, timeToEmpty: 11400 }, null, true)} / ${line({ state: 1, timeToFull: 5000 }, null, false)}`);

// The asking: the page's timer, root.askBattery and the checked call (callShell), against a qs that prints what the
// shell's Battery.times() returns, one that refuses (a shell from before this target: exit 0, "Target not found."),
// and none running (exit 255). A read is no setting: it neither raises nor takes away "The desktop isn't answering".
const battery = read("services/Battery.qml");
const times = qmlFunction(battery, "times");
const answer = times ? inScope({ root: { timeToEmpty: 9000, timeToFull: 0, drainingOnAc: false }, JSON }, times.params, times.body)() : null;
check("the shell's Battery answers its times over IPC (battery times)", typeof answer === "string" && /^\s*target:\s*"battery"/m.test(battery), String(answer));
const fn = name => { const f = qmlFunction(src, name); return f ? `function ${name}(${f.params}) {${f.body}}` : null; };
const parts = { shellAnswered: fn("shellAnswered"), callShell: fn("callShell"), askBattery: fn("askBattery") };
let component = null, timer = null;
try { component = objectWith(src, "id: shellCall"); } catch (e) {}
try { timer = objectWith(src, "onTriggered: root.askBattery()"); } catch (e) {}
const page = src.indexOf(" id: dp\n");
check("Display & power asks the shell when it opens, and as often as Battery measures, through the checked call",
  !!(parts.askBattery && parts.callShell && component && timer && /triggeredOnStart:\s*true/.test(timer) && src.indexOf(timer) > page
    && /callShell\(\s*\["battery",\s*"times"\]/.test(parts.askBattery)),
  `${Object.entries(parts).filter(([, v]) => !v).map(([k]) => k).join(", ")}${component ? "" : " shellCall"}${timer ? "" : " no timer asks"}`);

if (answer && parts.askBattery && parts.callShell && parts.shellAnswered && component && timer) {
  const files = {
    ...module("Quickshell.Io", { FakeShell: `QtObject { property string mode: "up"; property string answer: ${JSON.stringify(answer)} }` }, {
      StdioCollector: `QtObject { property string text: "" }`,
      // as Quickshell's Process: stdout's text is in before exited. qs prints its own words on stdout too, as all its log
      // lines (Quickshell 0.3.2's LogManager), and nothing on stderr
      Process: `QtObject {
    id: p
    property var command: []
    property bool running: false
    property QtObject stderr: null
    property QtObject stdout: null
    property bool live: false
    signal exited(int exitCode, int exitStatus)
    property Timer reply: Timer { interval: 20; onTriggered: p.end() }
    onRunningChanged: {
        if (p.running && !p.live) {
            p.live = true;
            p.reply.start();
        }
    }
    function end() {
        const asked = p.command.slice(-2).join(" ") === "battery times";
        if (p.stdout) p.stdout.text = FakeShell.mode === "gone" ? "No running instances for \\"/x/shell.qml\\"\\n"
            : FakeShell.mode === "old" || !asked ? "Target not found.\\n" : FakeShell.answer + "\\n";
        p.live = false;
        p.exited(FakeShell.mode === "gone" ? 255 : 0, 0);
        p.running = false;
    }
}` }),
    ...module("qs.modules.common", { Directories: `QtObject { property string shellFile: "/x/shell.qml" }` }),
  };
  const scene = `import QtQuick
import QtTest
import Quickshell.Io
import qs.modules.common
TestCase {
    id: root
    name: "BatteryAsked"
    when: windowShown
    property bool desktopSilent: false
    readonly property bool hasBattery: true
    property var shellBattery: undefined
    ${parts.shellAnswered}
    ${component}
    ${parts.callShell}
    ${parts.askBattery}
    ${timer}
    function settle() { wait(150); }
    function test_asked() {
        const out = {};
        settle();
        out.opened = root.shellBattery;
        out.openedSilent = root.desktopSilent;
        FakeShell.mode = "old";
        root.askBattery(); settle();
        out.old = root.shellBattery;
        out.oldSilent = root.desktopSilent;
        FakeShell.mode = "up";
        root.askBattery(); settle();
        out.back = root.shellBattery;
        root.desktopSilent = true;
        root.askBattery(); settle();
        out.keptSilent = root.desktopSilent;
        FakeShell.mode = "gone";
        root.askBattery(); settle();
        out.gone = root.shellBattery;
        console.log("ASKED " + JSON.stringify(out));
    }
}
`;
  let out = null;
  try {
    out = logged(runScene({ "tst_battery.qml": scene, ...files }), "ASKED");
  } catch (e) {
    check("the scene ran", false, String(e.message ?? e));
  }
  if (out) {
    check("opening the page has the shell's times, and the line shows them at once",
      out.opened?.timeToEmpty === 9000 && line({ state: 2, timeToEmpty: 11400 }, out.opened, true) === "2 h 30 min left", JSON.stringify(out));
    check("a shell that refuses (qs exits 0, \"Target not found.\") is no answer: UPower's times, as 1.2.14",
      out.old === null && line({ state: 2, timeToEmpty: 11400 }, out.old, true) === "3 h 10 min left", JSON.stringify(out));
    check("the next answer brings the shell's times back", out.back?.timeToEmpty === 9000, JSON.stringify(out));
    check("with no shell running (qs exits 255), UPower's times", out.gone === null, JSON.stringify(out));
    check("asking leaves \"The desktop isn't answering\" as it was", out.openedSilent === false && out.oldSilent === false && out.keptSilent === true,
      JSON.stringify(out));
  }
}
done();
