// "N notifications while you were away" on the lock: LockScreen.qml's own handler for the lock beginning and
// LockSurface.qml's own bindings for that line, run under node. A day of popups seen and answered, with the
// notification centre never opened, must not be counted as come while the person was away; what comes during the lock is.
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the lock's notifications while you were away");
const screen = read("modules/common/panels/lock/LockScreen.qml"), surface = read("modules/ii/lock/LockSurface.qml");
const tr = s => Object.assign(new String(s), { arg: x => s.replace("%1", x) });

const Notifications = { unread: 0, list: [] };
const arrive = appName => { Notifications.list.push({ appName }); Notifications.unread++; };
const GlobalStates = { screenLocked: false };
const lockContext = { reset() {}, checkFingerprints() {}, tryFingerUnlock() {} };
const locked = qmlFunction(screen, "onScreenLockedChanged");
const lockChanged = inScope({ GlobalStates, lockContext, Notifications }, locked.params, locked.body);

const line = surface.indexOf("1 notification while you were away");
const bind = name => {
  const e = readExpression(surface, surface.lastIndexOf(`${name}:`, line) + name.length + 1).expr;
  return e.startsWith("{") ? e.slice(1, -1) : `return (${e});`;
};
const away = qmlProperty(surface, "awayCount");
// the line under the clock, or "" while it is hidden
function shown() {
  const root = { context: lockContext };
  if (away) root.awayCount = inScope({ root, Notifications }, "", `return (${away});`)();
  const scope = { root, Notifications, Translation: { tr } };
  return inScope(scope, "", bind("visible"))() ? String(inScope(scope, "", bind("text"))()) : "";
}

for (let i = 0; i < 23; i++) arrive(i % 2 ? "Discord" : "Mail");   // popups all day, each seen and answered
GlobalStates.screenLocked = true;
lockChanged();
check("locked after a day of popups seen: nothing is said to have come while away", shown() === "", `it says "${shown()}"`);
arrive("Signal");
arrive("Mail");
check("two come while it is locked: those two, newest first", shown() === "2 notifications while you were away · Mail, Signal",
  `it says "${shown()}"`);
GlobalStates.screenLocked = false;
lockChanged();
GlobalStates.screenLocked = true;
lockChanged();
check("locked again with nothing new: nothing", shown() === "", `it says "${shown()}"`);
arrive("Calendar");
check("one comes: that one", shown() === "1 notification while you were away · Calendar", `it says "${shown()}"`);
done();
