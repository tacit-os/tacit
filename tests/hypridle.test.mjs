// Settings > Lock & sleep's copy of hypridle.conf, and the login step that brings it up to Tacit's
// (scripts/hyprland/hypridle_refresh.py). Settings' own setIdleTime() and parseIdle() run under node; the copy it makes
// from 1.2.13's packaged file (tests/config/hypridle-1.2.13.conf, without the Wi-Fi step after sleep) is handed to the
// script with this tree's packaged file.
import { spawnSync } from "child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

const old = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "config", "hypridle-1.2.13.conf"), "utf8");
const packaged = join(tree, "session", "xdg", "hypr", "hypridle.conf");
const now = readFileSync(packaged, "utf8");
const settings = read("tacit-settings.qml");
const WIFI = "wifi-after-sleep.sh";

// Settings with only this text in ~/.config/hypr/hypridle.conf ("" for none) and this packaged file
function settingsWith(theirs, packagedText) {
  let file = theirs;
  const scope = {
    idleFile: { text: () => file, setText: t => (file = t) },
    idlePackaged: { text: () => packagedText },
    Quickshell: { execDetached: args => (file = args[5]) },   // bash -c <script> _ <path> <text>
    FileUtils: { trimFileProtocol: s => s },
    Directories: { config: "/home/someone/.config" },
    idleReload: { restart() {} },
    root: { idleTimes: {} },
  };
  const ui = scope.root;
  for (const name of ["idleKind", "parseIdle", "setIdleTime"]) {
    const f = qmlFunction(settings, name);
    ui[name] = f ? inScope(scope, f.params, f.body) : () => ({});
  }
  const mark = qmlProperty(settings, "idleMark");
  if (mark) ui.idleMark = inScope({}, "", `return (${mark});`)();
  return { ui, file: () => file };
}
// the refresh script run on this text as ~/.config/hypr/hypridle.conf: the file afterwards
function refresh(text) {
  const dir = mkdtempSync(join(tmpdir(), "tacit-hypridle-"));
  try {
    writeFileSync(join(dir, "hypridle.conf"), text);
    spawnSync("python3", ["-I", join(tree, "scripts", "hyprland", "hypridle_refresh.py"), packaged, join(dir, "hypridle.conf")], { stdio: "pipe" });
    return readFileSync(join(dir, "hypridle.conf"), "utf8");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
// the times Settings reads in a file
const times = text => JSON.stringify(settingsWith(text, now).ui.parseIdle(text));

console.log("The Lock & sleep times' copy of hypridle.conf (tacit-settings.qml, scripts/hyprland/hypridle_refresh.py)");

// made by 1.2.13's Settings: the lock after 10 min, the screen off after 20 (Settings then wrote the packaged file as it was)
const made = settingsWith("", old);
made.ui.setIdleTime("lock", 600);
const copy1213 = made.file().replace(/^#.*Settings.*\n/, "");
const timed = copy1213.replace(/timeout = 600 # 10mins/, "timeout = 1200");
{
  const after = refresh(timed);
  check("a copy 1.2.13's Settings made gets the Wi-Fi step after sleep, with the person's times, and is marked as Settings'",
    after.includes(WIFI) && times(after) === '{"lock":600,"screen":1200,"sleep":900}' && after.split("\n")[0] === made.ui.idleMark,
    `times ${times(after)}, Wi-Fi step ${after.includes(WIFI)}, first line ${JSON.stringify(after.split("\n")[0])}`);
  check("the next login changes nothing", refresh(after) === after);
}
// made by this Settings, then the packaged file changed: still brought up to it
{
  const s = settingsWith("", old);
  s.ui.setIdleTime("sleep", 1800);
  const after = refresh(s.file());
  check("a copy this Settings makes is brought up too", after.includes(WIFI) && times(after) === '{"lock":300,"screen":600,"sleep":1800}',
    `times ${times(after)}, Wi-Fi step ${after.includes(WIFI)}`);
  const again = settingsWith(after, now);
  again.ui.setIdleTime("lock", 120);
  check("a time changed in it keeps it marked", refresh(again.file()) === again.file() && times(again.file()) === '{"lock":120,"screen":600,"sleep":1800}',
    times(again.file()));
}
// the person's own file: an extra listener of theirs, or a lock command of their own
{
  const own = timed.replace("listener {", "listener {\n    timeout = 60\n    on-timeout = brightnessctl -s set 10\n}\n\nlistener {");
  check("a file with a listener of the person's own is left alone", refresh(own) === own);
  const cmd = timed.replace(/^\$lock_cmd = .*$/m, "$lock_cmd = swaylock");
  check("a file with a lock command of the person's own is left alone", refresh(cmd) === cmd);
}

done();
