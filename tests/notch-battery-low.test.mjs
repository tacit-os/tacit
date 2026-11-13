// The battery glyph in the notch's battery peek (modules/ii/island/IslandHeader.qml, batteryWing): its glyph and colour
// bindings run under node with services/Battery.qml's own isLow and isLowAndNotCharging, for Settings > Battery's
// "Warn when the battery falls to" (battery.low) set to 20, 30 and 10. The glyph's low mark follows that setting, as the
// low-battery warning does, not a fixed 20 %.
import { inScope, qmlProperty, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the notch's battery glyph and Settings' low level (IslandHeader.qml, Battery.qml)");
const battery = read("services/Battery.qml");
const glyph = objectWith(objectWith(read("modules/ii/island/IslandHeader.qml"), "id: batteryWing"), '"bolt"');
const binding = name => readExpression(glyph, glyph.indexOf(":", glyph.search(new RegExp(`\\n\\s*${name}:`))) + 1).expr;
const text = binding("text"), colour = binding("color");

function wing(pct, low, pluggedIn = false) {
  const Config = { options: { battery: { low, critical: 5, suspend: 3, full: 100 } } };
  const Battery = { available: true, percentage: pct / 100, isPluggedIn: pluggedIn };
  for (const name of ["isLow", "isLowAndNotCharging"])
    Battery[name] = inScope({ ...Battery, Config }, "", `return (${qmlProperty(battery, name)});`)();
  const scope = { Battery, Tacit: { inkMain: "main" }, IslandController: { subtextColor: "subtext" } };
  return { glyph: inScope(scope, "", `return (${text});`)(), ink: inScope(scope, "", `return (${colour});`)() };
}
const said = w => `${w.glyph} in ${w.ink}`;

check("at 20 % with the warning at 20 %, the alert", said(wing(20, 20)) === "battery_alert in main", said(wing(20, 20)));
check("at 25 % with the warning at 30 %, the alert, as the warning says", said(wing(25, 30)) === "battery_alert in main", said(wing(25, 30)));
check("at 15 % with the warning at 10 %, not yet", said(wing(15, 10)) === "battery_full in subtext", said(wing(15, 10)));
check("at 35 % with the warning at 30 %, a battery", said(wing(35, 30)) === "battery_full in subtext", said(wing(35, 30)));
check("plugged in at 8 %, the bolt, not the alert's ink", said(wing(8, 30, true)) === "bolt in subtext", said(wing(8, 30, true)));
done();
