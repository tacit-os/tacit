// The bar has no dark/light button: Tacit is dark only, and switchwall.sh makes a dark palette whatever --mode it is
// given, so the button could never do anything. modules/ii/bar/UtilButtons.qml has no button that runs the colour
// script with a mode or a Loader for one, and Config.qml's bar.utilButtons has no showDarkModeToggle; the other buttons
// stay.
import { adapterDefaults } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the bar has no dark/light button (UtilButtons.qml, Config.qml)");
const src = read("modules/ii/bar/UtilButtons.qml");
check("no bar button runs the colour script with a mode", !/wallpaperSwitchScriptPath[^\n]*--mode/.test(src));
check("and no button loads on bar.utilButtons.showDarkModeToggle", !src.includes("showDarkModeToggle"));
const buttons = adapterDefaults(read("modules/common/Config.qml")).bar.utilButtons;
check("Config.qml has no showDarkModeToggle", !("showDarkModeToggle" in buttons), JSON.stringify(buttons));
const kept = ["showScreenSnip", "showColorPicker", "showMicToggle", "showKeyboardToggle", "showWallpaperToggle",
  "showPerformanceProfileToggle", "showScreenRecord"];
check("and the other buttons are kept, each with its Loader", kept.every(k => k in buttons && src.includes(`utilButtons.${k}`)),
  kept.filter(k => !(k in buttons) || !src.includes(`utilButtons.${k}`)).join(", "));
done();
