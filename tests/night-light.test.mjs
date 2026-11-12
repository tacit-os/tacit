// The night light over a restart of the shell (services/Hyprsunset.qml): its own load(), toggleTemperature() and the
// rest run under node, with a pretend hyprsunset that answers at once and a Persistent store kept between two starts.
// A night light switched on by hand must come back; "By time of day" keeps its own way.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the night light over a restart (Hyprsunset.qml)");
const src = read("services/Hyprsunset.qml");

// one start of the shell; `stored` is states.json, kept from one start to the next
function shell(stored, automatic = false) {
  const sent = [];
  const root = { isNiri: false, automatic, loaded: false, temperatureActive: false, manualActive: undefined, colorTemperature: 5800,
    clockHour: 21, clockMinute: 0, manualActiveHour: 0, manualActiveMinute: 0, shouldBeOn: false, manualRestored: false,
    applyHyprsunset(request, done) { sent.push(request); done?.(true); } };
  const scope = { root, Persistent: { ready: true, states: stored }, Config: { ready: true } };
  for (const name of ["load", "ensureState", "enableTemperature", "disableTemperature", "toggleTemperature", "restoreManual"]) {
    const f = qmlFunction(src, name);
    if (f) root[name] = inScope(scope, f.params, f.body);
  }
  return { root, sent };
}
{
  const stored = { nightLight: { on: false } };
  const first = shell(stored);
  first.root.load();
  first.root.toggleTemperature(true);          // switched on by hand at 9 pm
  const next = shell(stored);                  // the shell restarts (an update, a reload)
  next.root.load();
  check("a night light switched on by hand is on again after the shell restarts",
    next.root.temperatureActive === true && next.sent.at(-1) === "temperature 5800", JSON.stringify(next.sent));
  next.root.toggleTemperature(false);          // and switched off
  const third = shell(stored);
  third.root.load();
  check("switched off by hand, it stays off", third.root.temperatureActive === false && !third.sent.some(r => r.startsWith("temperature")),
    JSON.stringify(third.sent));
}
{
  const stored = { nightLight: { on: true } };
  const s = shell(stored, true);               // "By time of day", outside its hours
  s.root.load();
  check("with \"By time of day\" a hand-made on from before is not applied", !s.sent.some(r => r.startsWith("temperature")), JSON.stringify(s.sent));
}
done();
