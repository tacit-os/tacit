// "Never" for turning the screen off and for sleep (Settings > Display & power's "When you step away", tacit-settings.qml,
// and scripts/hyprland/hypridle_refresh.py at login): the longest choices were an hour and two hours, so a docked laptop
// that must stay awake could only be held up by Caffeine, which holds off the lock too. Settings' own idleOptions(),
// setIdleTime() and parseIdle() run under node on this tree's packaged hypridle.conf; the copy they make is handed to the
// login script, and read as hypridle reads it (a line starting with # is a comment).
import { spawnSync } from "child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== Never for screen off and sleep (tacit-settings.qml, hypridle_refresh.py)");
const packaged = join(tree, "session", "xdg", "hypr", "hypridle.conf");
const now = readFileSync(packaged, "utf8");
const settings = read("tacit-settings.qml");

function settingsWith(theirs) {
  let file = theirs;
  const ui = { idleTimes: {} };
  const scope = {
    idleFile: { text: () => file, setText: t => (file = t) },
    idlePackaged: { text: () => now },
    Quickshell: { execDetached: args => (file = args[5]) },
    FileUtils: { trimFileProtocol: s => s },
    Directories: { config: "/home/someone/.config" },
    idleReload: { restart() {} },
    root: ui,
  };
  for (const name of ["idleKind", "parseIdle", "setIdleTime", "idleOptions", "durationText"]) {
    const f = qmlFunction(settings, name);
    if (f) ui[name] = inScope(scope, f.params, f.body);
  }
  const mark = qmlProperty(settings, "idleMark");
  if (mark) ui.idleMark = inScope({}, "", `return (${mark});`)();
  const sync = () => { ui.idleTimes = ui.parseIdle(file || now); };
  sync();
  return { ui, file: () => file, sync };
}
function refresh(text) {
  const dir = mkdtempSync(join(tmpdir(), "tacit-idle-never-"));
  try {
    writeFileSync(join(dir, "hypridle.conf"), text);
    spawnSync("python3", ["-I", join(tree, "scripts", "hyprland", "hypridle_refresh.py"), packaged, join(dir, "hypridle.conf")], { stdio: "pipe" });
    return readFileSync(join(dir, "hypridle.conf"), "utf8");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
// what hypridle runs after idling, as it reads the file: the on-timeout of each listener outside a comment
const runs = text => text.split("\n").filter(l => !/^\s*#/.test(l)).map(l => l.match(/^\s*on-timeout\s*=\s*(.*)$/)?.[1]).filter(Boolean);
const sleeps = text => runs(text).some(r => r.includes("$suspend_cmd"));
const darkens = text => runs(text).some(r => /dpms.*off/.test(r));

// the rows' choices, as the page asks for them
const s = settingsWith("");
const row = label => {
  const at = settings.indexOf(`label: "${label}"`);
  const o = settings.indexOf("options:", at);
  return inScope({ root: s.ui }, "", `return (${readExpression(settings, o + "options:".length).expr});`)();
};
const labels = opts => (opts ?? []).map(o => o.label);
check("Turn the screen off after offers Never, after the times", labels(row("Turn the screen off after")).at(-1) === "Never", labels(row("Turn the screen off after")).join(", "));
check("Sleep after offers Never, after the times", labels(row("Sleep after")).at(-1) === "Never", labels(row("Sleep after")).join(", "));
check("Lock the screen after does not", !labels(row("Lock the screen after")).includes("Never"), labels(row("Lock the screen after")).join(", "));

{
  const t = settingsWith("");
  t.ui.setIdleTime("sleep", 0);
  const off = t.file();
  t.sync();
  check("Never for sleep: hypridle has no sleep listener left, and the lock and the dark screen stay",
    !sleeps(off) && darkens(off) && runs(off).includes("$lock_cmd"), runs(off).join(" | "));
  check("and Settings reads it back as Never", t.ui.idleTimes.sleep === 0, JSON.stringify(t.ui.idleTimes));
  const after = refresh(off);
  check("the next login keeps it off, with the rest brought up to Tacit's", !sleeps(after) && after.includes("wifi-after-sleep.sh")
    && JSON.stringify(t.ui.parseIdle(after)) === '{"lock":300,"screen":600,"sleep":0}', JSON.stringify(t.ui.parseIdle(after)));
  check("and the one after changes nothing", refresh(after) === after);
  const back = settingsWith(after);
  back.ui.setIdleTime("sleep", 1800);
  check("a time picked again turns it on with that time", sleeps(back.file()) && JSON.stringify(back.ui.parseIdle(back.file())) === '{"lock":300,"screen":600,"sleep":1800}',
    JSON.stringify(back.ui.parseIdle(back.file())));
  check("and the login keeps that", refresh(back.file()) === back.file());
}
{
  const t = settingsWith("");
  t.ui.setIdleTime("screen", 0);
  check("Never for the screen: it is never turned off, and sleep still comes", !darkens(t.file()) && sleeps(t.file()), runs(t.file()).join(" | "));
}
done();
