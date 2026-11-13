// The busy bar of the Wi-Fi, VPN and Bluetooth sections and the wallpaper grids
// (modules/common/widgets/StyledIndeterminateProgressBar.qml): the controls style the shell runs (shell.qml's pragma)
// draws a ProgressBar with the palette roles its own ProgressBar.qml reads (Qt's installed copy), and each of those
// must come from the wallpaper's palette (Appearance), not the style's defaults.
import { existsSync, readFileSync } from "fs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the busy bar's colours (StyledIndeterminateProgressBar.qml)");
const style = read("shell.qml").match(/QT_QUICK_CONTROLS_STYLE=(\w+)/)?.[1] ?? "Basic";
const styleFile = `/usr/lib/qt6/qml/QtQuick/Controls/${style}/ProgressBar.qml`;
// Basic's bar is palette.dark on palette.midlight (Qt 6.12); the installed file says, where it is there
const roles = existsSync(styleFile) ? [...new Set([...readFileSync(styleFile, "utf8").matchAll(/control\.palette\.(\w+)/g)].map(m => m[1]))] : ["dark", "midlight"];
const bar = read("modules/common/widgets/StyledIndeterminateProgressBar.qml");

check(`the ${style} style's ProgressBar reads palette roles (${roles.join(", ")})`, roles.length > 0);
for (const role of roles) {
  const set = new RegExp(`\\bpalette\\.${role}:\\s*(Appearance\\.[\\w.]+)`).exec(bar);
  check(`palette.${role} comes from the wallpaper's palette`, !!set, "not set: the style's default colour is drawn");
}

done();
