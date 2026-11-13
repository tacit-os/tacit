// Settings > Display & power's monitors.lua lines (tacit-settings.qml): setMonitor() runs under node on pretend screens,
// and the write it builds runs under bash on a monitors.lua in a folder of its own, with a stand-in hyprctl. A monitor's
// line goes by its description (desc:), so the same monitor on another dock port keeps its scale and place and the next
// one on the old port does not take them; the laptop's panel, and two monitors alike with no serial, go by connector.
// Hyprland uses the last line that fits a screen, so an older line for a screen that is plugged in has to go.
import { spawnSync } from "child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("tacit-settings.qml");
const pageAt = src.indexOf("id: displayPage");
const page = src.slice(pageAt, matchBrace(src, src.indexOf("{", src.indexOf("ColumnLayout", pageAt))));
const laptop = { name: "eDP-1", description: "BOE 0x0BCA", width: 2880, height: 1800, refreshRate: 60, x: 0, y: 0, scale: 2, transform: 0, modes: [], mirrorOf: "none" };
const dell = (name, serial = " 7XYZ123") => ({ name, description: `Dell Inc. DELL U2723QE${serial}`, width: 3840, height: 2160, refreshRate: 60, x: 1440, y: 0, scale: 1.5, transform: 0, modes: [], mirrorOf: "none" });

// the write setMonitor() builds for these screens, run on monitors.lua as it is: the file after it
function write(screens, name, change, before) {
  const writeMonitors = { running: false, command: null };
  const dp = { screens, monitorsFileOurs: true, settling: false, waitingChanges: [] };
  const scope = { dp, root: { displayKeepLeft: 0, displayBackupBase: 'b="$XDG_RUNTIME_DIR/tacit-monitors"; ' }, readScreens: {}, readMonitorsFile: {}, writeMonitors };
  for (const f of ["outputOf", "monitorLine", "shiftedPosition", "setMonitor"]) {
    const fn = qmlFunction(page, f);
    if (fn) dp[f] = inScope(scope, fn.params, fn.body);
  }
  dp.setMonitor(name, change);
  const dir = mkdtempSync(join(tmpdir(), "tacit-monitors-"));
  try {
    mkdirSync(join(dir, "config/hypr"), { recursive: true });
    mkdirSync(join(dir, "bin"));
    mkdirSync(join(dir, "run"));
    writeFileSync(join(dir, "bin/hyprctl"), "#!/bin/sh\nexit 0\n");
    chmodSync(join(dir, "bin/hyprctl"), 0o755);
    if (before !== undefined) writeFileSync(join(dir, "config/hypr/monitors.lua"), before);
    const [cmd, ...args] = writeMonitors.command;
    const r = spawnSync(cmd, args, { encoding: "utf8", env: { PATH: `${join(dir, "bin")}:${process.env.PATH}`, HOME: dir, XDG_CONFIG_HOME: join(dir, "config"), XDG_RUNTIME_DIR: join(dir, "run") } });
    if (r.status !== 0) throw new Error(`the write failed: ${r.stderr}`);
    return readFileSync(join(dir, "config/hypr/monitors.lua"), "utf8").split("\n").filter(l => l.startsWith("hl.monitor("));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
const outputs = lines => lines.map(l => l.match(/output = "([^"]*)"/)?.[1]);

console.log("== monitors.lua lines by monitor, not by port (tacit-settings.qml)");
// at the desk: the 4K monitor on DP-3 at 150 %, right of the laptop
const desk = write([laptop, dell("DP-3")], "DP-3", { scale: 1.5 });
check("the monitor's line goes by its description", outputs(desk).includes("desc:Dell Inc. DELL U2723QE 7XYZ123"), outputs(desk).join(", "));
check("the laptop's panel goes by its connector (the lid's lines add to it)", outputs(desk).includes("eDP-1"), outputs(desk).join(", "));

// the same monitor through another dock port, its line from before still in the file, and an old line by port
const before = ["-- Written by Tacit Settings (Display & power).", ...desk, 'hl.monitor({ output = "DP-4", mode = "1920x1080@60.000", position = "0x0", scale = 1 })',
  'hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60.000", position = "3000x0", scale = 1 })'].join("\n") + "\n";
const moved = write([laptop, dell("DP-4")], "DP-4", { scale: 2 });
check("on DP-4 its line is the same one", outputs(moved).includes("desc:Dell Inc. DELL U2723QE 7XYZ123") && !outputs(moved).includes("DP-4"), outputs(moved).join(", "));
const after = write([laptop, dell("DP-4")], "DP-4", { scale: 2 }, before);
const out = outputs(after);
check("its earlier line gives way to the new one, not kept beside it", out.filter(o => o === "desc:Dell Inc. DELL U2723QE 7XYZ123").length === 1 && /scale = 2\b/.test(after.find(l => l.includes("desc:Dell")) ?? ""), after.join(" | "));
check("an older line by the port it is on now goes (Hyprland would take it, as the last)", !out.includes("DP-4"), out.join(", "));
check("a line for a screen not plugged in stays, for when it is back", out.includes("HDMI-A-1"), out.join(", "));

// two alike with no serial: one description fits both, so they go by connector; a mirror names its source as its line does
const twins = write([laptop, dell("DP-3", ""), dell("DP-4", "")], "DP-4", { scale: 2 });
check("two monitors alike with no serial go by their connectors", outputs(twins).includes("DP-3") && outputs(twins).includes("DP-4"), outputs(twins).join(", "));
const mirrored = write([dell("DP-3"), { ...dell("HDMI-A-1", " 99AA"), description: "LG Electronics LG TV 0x01" }], "HDMI-A-1", { position: "auto", mirror: "DP-3" });
check("a mirror names its source by description too", mirrored.some(l => l.includes('mirror = "desc:Dell Inc. DELL U2723QE 7XYZ123"')), mirrored.join(" | "));
done();
