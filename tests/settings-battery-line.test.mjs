// Settings > Display & power's battery line (tacit-settings.qml): its charging and subtitle bindings run under node with
// a pretend UPower device and the shell's Battery service. The times and "not charging" must be Battery's, measured from
// the pack's own energy as the notch shows them, not UPower's own estimates, which swing and say "Charging" while a
// capped charger lets the pack drain.
import { inScope, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the battery line on Display & power (tacit-settings.qml)");
const src = read("tacit-settings.qml");
const at = src.indexOf('eyebrow: "Battery"');
const summary = src.slice(src.lastIndexOf("Summary {", at), src.indexOf("live:", at));
const expr = name => { const m = new RegExp(`\\n\\s*(?:readonly property \\w+ )?${name}:\\s*`).exec(summary); return readExpression(summary, m.index + m[0].length).expr; };
const batteryTime = secs => { const t = Math.round(secs / 60), h = Math.floor(t / 60), m = t % 60; return h > 0 ? `${h} h ${m} min` : `${m} min`; };
const UPowerDeviceState = { Charging: 1, Discharging: 2, FullyCharged: 4 };
function line(b, battery, onBattery) {
  const scope = { b, Battery: { drainingOnAc: false, timeToFull: 0, timeToEmpty: 0, ...battery }, UPower: { onBattery }, UPowerDeviceState, root: { batteryTime } };
  scope.charging = inScope(scope, "", `return (${expr("charging")});`)();
  return inScope(scope, "", `return (${expr("subtitle")});`)();
}

// a capped charger: UPower says charging and full in 6 h 20 min, the pack's energy goes down
check("plugged in while the pack drains says so, as the notch does",
  line({ state: 1, percentage: 0.57, timeToFull: 22800 }, { drainingOnAc: true }, false) === "Plugged in, not charging",
  line({ state: 1, percentage: 0.57, timeToFull: 22800 }, { drainingOnAc: true }, false));
check("charging shows Battery's time to full, not UPower's",
  line({ state: 1, timeToFull: 32400 }, { timeToFull: 3600 }, false) === "Charging · full in 1 h 0 min",
  line({ state: 1, timeToFull: 32400 }, { timeToFull: 3600 }, false));
check("on battery shows Battery's time left, not UPower's",
  line({ state: 2, timeToEmpty: 11400 }, { timeToEmpty: 9000 }, true) === "2 h 30 min left",
  line({ state: 2, timeToEmpty: 11400 }, { timeToEmpty: 9000 }, true));
check("before Battery has measured a rate, no time is shown",
  line({ state: 2, timeToEmpty: 11400 }, {}, true) === "On battery" && line({ state: 1, timeToFull: 5000 }, {}, false) === "Charging",
  `${line({ state: 2, timeToEmpty: 11400 }, {}, true)} / ${line({ state: 1, timeToFull: 5000 }, {}, false)}`);
check("a trickle charge past 12 h is still 'slowly'", line({ state: 1 }, { timeToFull: 50000 }, false) === "Charging slowly", line({ state: 1 }, { timeToFull: 50000 }, false));
done();
