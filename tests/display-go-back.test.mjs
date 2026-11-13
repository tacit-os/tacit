// Settings > Display & power after Go back (tacit-settings.qml): the old monitors.lua is put back and Hyprland reloads
// it, and the page's next change must start from the screens as they are again, not as they were refused. The page's
// own Hyprland handler, its hyprctl monitors reader and setMonitor() run under node on two pretend screens. Closing
// Settings while the Keep bar counts down goes back too: the window's onClosing and restoreDisplay() run under node.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("tacit-settings.qml");
const pageAt = src.indexOf("id: displayPage");
const page = src.slice(pageAt, matchBrace(src, src.indexOf("{", src.indexOf("ColumnLayout", pageAt))));
// the body of "<key>: { ... }" first found after "<marker>" in the page
function block(marker, key) {
  const at = page.indexOf(key, page.indexOf(marker));
  const open = page.indexOf("{", at);
  return page.slice(open + 1, matchBrace(page, open));
}

// what hyprctl monitors -j says: a laptop panel and a monitor to its right
const hyprctl = laptopScale => JSON.stringify([
  { id: 0, name: "eDP-1", description: "BOE 0x0BCA", width: 2880, height: 1800, refreshRate: 60, x: 0, y: 0, scale: laptopScale, transform: 0, availableModes: ["2880x1800@60.00Hz"], mirrorOf: "none" },
  { id: 1, name: "HDMI-A-1", description: "Dell U2723QE", width: 3840, height: 2160, refreshRate: 60, x: Math.round(2880 / laptopScale), y: 0, scale: 1.5, transform: 0, availableModes: ["3840x2160@60.00Hz", "2560x1440@59.95Hz"], mirrorOf: "none" },
]);

function displayPage() {
  const proc = () => ({ running: false, command: null });
  const dp = { screens: [], monitorsFileOurs: true };
  const scope = { dp, root: { displayKeepLeft: 0, displayBackupBase: "" }, readScreens: proc(), readMonitorsFile: proc(), writeMonitors: proc() };
  for (const name of ["outputOf", "monitorLine", "shiftedPosition", "setMonitor"]) { const f = qmlFunction(page, name); if (f) dp[name] = inScope(scope, f.params, f.body); }
  const raw = qmlFunction(page.slice(page.indexOf("target: Hyprland")), "onRawEvent");
  const event = inScope(scope, raw.params, raw.body);
  const readDone = inScope(scope, "text", block("id: readScreens", "onStreamFinished:"));
  // a read started is a read answered, with what Hyprland says now
  const hyprland = { now: "", say(name) { event({ name, data: "" }); if (scope.readScreens.running) { scope.readScreens.running = false; readDone(hyprland.now); } } };
  return { dp, scope, hyprland, readDone };
}
const laptopLine = s => s.scope.writeMonitors.command.find(l => l.includes('output = "eDP-1"'));

console.log("Display & power after Go back (tacit-settings.qml)");

{
  const s = displayPage();
  s.readDone(hyprctl(1));               // the page opens on the laptop at 100%
  s.hyprland.now = hyprctl(2);          // the person sets it to 200% and the write reads the screens again
  s.readDone(s.hyprland.now);
  s.hyprland.now = hyprctl(1);          // Go back (or the 15 s): the old file is back and Hyprland reloaded it
  s.hyprland.say("configreloaded");
  check("after Go back, the page reads the screens and the files again",
    s.dp.screens[0]?.scale === 1 && s.scope.readMonitorsFile.running,
    `the laptop reads ${Math.round((s.dp.screens[0]?.scale ?? 0) * 100)}%${s.scope.readMonitorsFile.running ? "" : ", monitors.lua not read again"}`);
  s.dp.setMonitor("HDMI-A-1", { mode: "2560x1440@59.951" });
  const line = laptopLine(s) ?? "";
  check("then a new resolution on the other monitor writes the laptop at 100%, not the 200% refused",
    /scale = 1\b/.test(line), line);
}
{
  const s = displayPage();
  s.readDone(hyprctl(1));
  s.scope.writeMonitors.running = true; // a write landing: its own end reads the screens
  s.hyprland.now = hyprctl(2);
  s.hyprland.say("configreloaded");
  check("a reload while a write is landing leaves the read to the write's end", s.dp.screens[0].scale === 1,
    `the page read ${s.dp.screens[0].scale * 100}% while the write ran`);
}

// closing the window (its button, Super+Q) while the bar counts down: the countdown ends with the process
{
  const app = read("tacit-settings.qml");
  const at = app.indexOf("{", app.indexOf("onClosing:"));
  const closing = app.slice(at + 1, matchBrace(app, at));
  const restore = qmlFunction(app, "restoreDisplay");
  function close(left) {
    const ran = [];
    const root = { displayKeepLeft: left, displayBackupBase: 'b="${XDG_RUNTIME_DIR:-/tmp}/tacit-monitors"; ', pickDone: null };
    const scope = { root, Directories: { shellFile: "shell.qml" }, Quickshell: { execDetached: c => ran.push(c.join(" ")) },
      Qt: { quit: () => ran.push("quit") } };
    root.restoreDisplay = inScope(scope, restore.params, restore.body);
    inScope(scope, "", closing)();
    return ran;
  }
  const ran = close(9);
  const back = ran.findIndex(c => c.includes('cp -f "$b.previous" "$f"'));
  check("closing Settings with 9 s left on the Keep bar puts the old monitors.lua back before it quits",
    back >= 0 && back < ran.indexOf("quit"), JSON.stringify(ran));
  check("closing it with nothing waiting on Keep leaves the screens alone", close(0).join() === "quit", JSON.stringify(close(0)));
}

done();
