// A setting Settings asks the desktop to carry out, while the shell isn't answering: each `qs ipc call` is read, a failed
// one puts its setting back, and the top of the page says "The desktop isn't answering. Try again in a moment." until a
// call goes through or another page opens (tacit-settings.qml's callShell and its users). The tree's own blocks run under
// qmltestrunner offscreen beside a stand-in Process that answers as Quickshell 0.3.2's qs does: exit 255 with no shell,
// exit 0 with "Not ready to accept queries yet." on stderr while it reloads, nothing at all from a shell that hangs, and
// exit 0 with nothing said when it takes the call.
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a setting changed while the desktop isn't answering (tacit-settings.qml)");
const src = read("tacit-settings.qml");
const fn = (block, name) => { const f = qmlFunction(block, name); return f ? `function ${name}(${f.params}) {${f.body}}` : null; };
const parts = { shellAnswered: fn(src, "shellAnswered"), callShell: fn(src, "callShell"), startPick: fn(src, "startPick"),
  applyWallpaper: fn(src, "applyWallpaper"), setNight: fn(src, "setNight") };
let component = null, writeSilent = null;
try { component = objectWith(src, "id: shellCall"); } catch (e) {}
try { writeSilent = objectWith(src, "id: writeSilent"); } catch (e) {}
const dndAt = src.indexOf("onToggled:", src.indexOf('label: "Do not disturb"'));
const dndToggled = readExpression(src, dndAt + "onToggled:".length).expr;
check("Settings reads each call to the shell (callShell, shellAnswered)", !!(component && parts.callShell && parts.shellAnswered),
  Object.entries(parts).filter(([, v]) => !v).map(([k]) => k).join(", ") + (component ? "" : " shellCall"));

// release-1.2.15 runs here too, with what it has: its calls went through Quickshell.execDetached, which gives no answer
if (writeSilent && parts.startPick && parts.applyWallpaper && parts.setNight) {
  const files = {
    ...module("Quickshell.Io", { FakeShell: `QtObject { property string mode: "up" }` }, {
      StdioCollector: `QtObject { property string text: "" }`,
      // as Quickshell's Process: stderr's text is in before exited, which comes before running reads false; a Process
      // stopped while it runs ends as a crash (status 1)
      Process: `QtObject {
    id: p
    property var command: []
    property bool running: false
    property QtObject stderr: null
    property QtObject stdout: null
    property bool live: false
    signal exited(int exitCode, int exitStatus)
    property Timer answer: Timer { interval: 20; onTriggered: p.end() }
    onRunningChanged: {
        if (p.running && !p.live) {
            p.live = true;
            if (FakeShell.mode !== "hung") p.answer.start();
        } else if (!p.running && p.live) {
            p.live = false;
            p.answer.stop();
            p.exited(0, 1);
        }
    }
    function end() {
        if (p.stderr) p.stderr.text = FakeShell.mode === "gone" ? " INFO: No running instances for \\"/x/shell.qml\\"\\n"
            : FakeShell.mode === "reloading" ? " ERROR: Not ready to accept queries yet.\\n" : "";
        p.live = false;
        p.exited(FakeShell.mode === "gone" ? 255 : 0, 0);
        p.running = false;
    }
}` }),
    ...module("qs.modules.common", { Directories: `QtObject { property string shellFile: "/x/shell.qml" }` }),
    ...module("Quickshell", { Quickshell: `QtObject { function env(name) { return "/home/someone"; } function execDetached(argv) {} }` }),
  };
  const scene = `import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common
TestCase {
    id: root
    name: "DesktopSilent"
    when: windowShown
    property bool desktopSilent: false
    property var pickDone: null
    property bool pickImages: false
    readonly property string selfPath: "/x/tacit-settings.qml"
    ${parts.shellAnswered ?? ""}
    ${component ?? ""}
    ${parts.callShell ?? ""}
    ${parts.startPick}
    ${parts.applyWallpaper}
    QtObject {
        id: dp
        property bool nightOn: false
        ${parts.setNight}
    }
    Timer { id: nightCheck; interval: 100000 }
    QtObject { id: np; property bool silent: false }
    QtObject { id: readSilent; property bool running: false }
    ${writeSilent}
    function settle(ms) { wait(ms ?? 120); }
    function test_calls() {
        const out = {};
        FakeShell.mode = "up";
        root.applyWallpaper("/w/beach.jpg"); settle();
        out.upSilent = root.desktopSilent;

        FakeShell.mode = "gone";
        root.applyWallpaper("/w/beach.jpg"); settle();
        out.goneSilent = root.desktopSilent;
        FakeShell.mode = "up";
        root.applyWallpaper("/w/beach.jpg"); settle();
        out.backSilent = root.desktopSilent;

        FakeShell.mode = "reloading";
        dp.setNight(true);
        out.nightAtOnce = dp.nightOn;
        settle();
        out.nightAfter = dp.nightOn;
        out.reloadingSilent = root.desktopSilent;

        FakeShell.mode = "gone";
        const done = path => {};
        root.startPick("/home/someone/Pictures", "A picture", true, false, done);
        out.pickWaits = root.pickDone === done;
        settle();
        out.pickAfter = root.pickDone === null;
        FakeShell.mode = "up";
        root.startPick("/home/someone/Pictures", "A picture", true, false, done);
        settle();
        out.pickUp = root.pickDone === done;

        FakeShell.mode = "gone";
        np.silent = false;
        (${dndToggled})(true);
        out.dndAtOnce = np.silent;
        settle();
        out.dndAfter = np.silent;
        out.dndReread = readSilent.running;

        FakeShell.mode = "hung";
        root.desktopSilent = false;
        dp.nightOn = false;
        dp.setNight(true);
        settle(1000);
        out.hungAt1s = [root.desktopSilent, dp.nightOn];
        settle(4600);
        out.hungAt56s = [root.desktopSilent, dp.nightOn];
        console.log("CALLS " + JSON.stringify(out));
    }
}
`;
  let out = null;
  try {
    out = logged(runScene({ "tst_silent.qml": scene, ...files }), "CALLS");
  } catch (e) {
    check("the scene ran", false, String(e.message ?? e));
  }
  if (out) {
    check("a call the shell takes says nothing", out.upSilent === false);
    check("with no shell running (qs exits 255) the page says the desktop isn't answering", out.goneSilent === true);
    check("and the next call that goes through takes the line away", out.backSilent === false);
    check("night light picked while the shell reloads (qs exits 0, \"Not ready\") goes back to off, and the page says so",
      out.nightAtOnce === true && out.nightAfter === false && out.reloadingSilent === true, JSON.stringify(out));
    check("a file pick with no shell waits for no pick", out.pickWaits && out.pickAfter, JSON.stringify(out));
    check("one the shell takes still waits for the Files window's answer", out.pickUp === true);
    check("Do not disturb turned on with no shell is off again, and read back from the shell",
      out.dndAtOnce === true && out.dndAfter === false && out.dndReread === true, JSON.stringify(out));
    check("a shell that holds the call is waited for, then taken as not answering after 5 s",
      JSON.stringify(out.hungAt1s) === "[false,true]" && JSON.stringify(out.hungAt56s) === "[true,false]", JSON.stringify(out));
  }
}

// brightness: a write not answered puts the knob back at the shell's own level, the file the shell writes
{
  const at = src.indexOf("onTriggered:", src.indexOf("id: brightnessWrite"));
  const triggered = readExpression(src, at + "onTriggered:".length).expr;
  let failed = null, reloaded = 0;
  inScope({ root: { callShell: (args, f) => { failed = f; } }, dp: { wantBrightness: 0.4 }, brightnessLevelFile: { reload: () => reloaded++ },
    Quickshell: { execDetached: () => {} }, Directories: { shellFile: "/x/shell.qml" } }, "", triggered)();
  if (failed) failed();
  check("a brightness write not answered puts the knob back at the shell's level", reloaded === 1, failed ? `reloaded ${reloaded} times` : "it is not read");
}

// the line, at the top of every page, and gone when another page opens
{
  const label = "The desktop isn't answering. Try again in a moment.";
  // in the page's column above the page itself, so on every page; shown while root.desktopSilent
  const at = src.indexOf(`label: "${label}"`);
  const group = at >= 0 ? src.slice(src.lastIndexOf("Group {", at), at) : "";
  const shown = /visible:\s*root\.desktopSilent/.test(group) && src.indexOf("id: pageColumn") < at && at < src.indexOf("id: pageLoader");
  check(`the top of the page says "${label}" while a call is not answered`, !!shown);
  const changed = readExpression(src, src.indexOf("onCurrentChanged:") + "onCurrentChanged:".length).expr;
  const root = { desktopSilent: true, revealPage() {}, revealInRail() {} };
  inScope({ root, Qt: { callLater: () => {} } }, "", changed.slice(1, -1))();
  check("and another page opening takes it away", root.desktopSilent === false);
}
done();
