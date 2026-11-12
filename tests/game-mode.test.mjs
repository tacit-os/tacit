// The Game mode pill (modules/common/models/quickToggles/GameModeToggle.qml): its toggled binding run under node on
// what hyprctl getoption -j animations:enabled answers, which HyprlandConfigOption stores as value
import { inScope, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the Game mode pill (GameModeToggle.qml)");
const src = read("modules/common/models/quickToggles/GameModeToggle.qml");
const expr = readExpression(src, src.indexOf("toggled:") + "toggled:".length).expr;
const toggled = value => inScope({ confOpt: { value } }, "", `return (${expr});`)();

// Hyprland 0.56.2: {"option": "animations:enabled", "bool": false, "set": true}
check("animations off, as Hyprland 0.56 answers it (false), shows Game mode on", toggled(false) === true);
check("animations on (true) shows Game mode off", toggled(true) === false);
check("an int answer (0, 1) is read the same way", toggled(0) === true && toggled(1) === false);
check("no answer yet (undefined) does not show Game mode on", toggled(undefined) === false);
done();
