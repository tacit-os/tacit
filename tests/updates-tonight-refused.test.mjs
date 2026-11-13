// Settings > About > Updates when systemctl refuses Tonight or Cancel tonight (services/Updates.qml, tacit-settings.qml):
// tonight(), cancelTonight() and their units' onExited run under node, then the row's description binding. Settings runs
// in its own process, where the notch's "Couldn't set the update for tonight" reaches no notch, so the row says it.
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Tonight refused, as About says it (services/Updates.qml, tacit-settings.qml)");
const src = read("services/Updates.qml");
const exitedOf = id => {
  const at = src.lastIndexOf("Process {", src.indexOf(`id: ${id}`));
  const proc = src.slice(at, matchBrace(src, at + "Process ".length) + 1);
  return readExpression(proc, proc.indexOf("onExited:") + "onExited:".length).expr;
};
const root = { tonightSet: false, tonightFailed: "" };
const scope = { root, tonightProc: { running: false }, cancelTonightProc: { running: false }, IslandController: { request() {} } };
const run = (fn, id, code) => {
  const f = qmlFunction(src, fn);
  inScope(scope, f.params, f.body)();
  inScope(scope, "", `return (${exitedOf(id)});`)()(code, 0);
};

const app = read("tacit-settings.qml");
const at = app.indexOf('description: Updates.phase === "looking"');
const desc = readExpression(app, at + "description:".length).expr;
const row = () => String(inScope({ Updates: { phase: "", lastCheckFailed: false, restartWarning: "", tonightFailed: root.tonightFailed, nightSkipped: "" },
  updatesGroup: { causeLine: () => "", restarting: false, restartFailed: "", tonight: root.tonightSet, ready: true, waiting: 3, checkedText: "" } }, "", `return (${desc});`)());

run("tonight", "tonightProc", 1);
check("a Tonight that systemctl refused says so in the row", row() === "Couldn't set the update for tonight", row());
run("tonight", "tonightProc", 0);
check("one that went through says when, as before", root.tonightSet && /^Tonight at 03:00/.test(row()), row());
run("cancelTonight", "cancelTonightProc", 1);
check("a Cancel tonight that was refused says so", root.tonightSet && row() === "Couldn't cancel tonight's update", row());
run("cancelTonight", "cancelTonightProc", 0);
check("and one that went through leaves the ready line", !root.tonightSet && /they install while the computer restarts/.test(row()), row());
done();
