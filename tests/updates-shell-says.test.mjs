// "Tacit X is ready" is said once, by the shell's notch (services/Updates.qml announce(), say(), flush() and the boot
// lock's check, run under node). Settings loads the same file and finds the same ready list; if it marks the line said
// (updates-announced, shared), the shell's next look stays quiet and nothing ever says it.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("services/Updates.qml");
const exited = readExpression(src, src.indexOf("onExited:", src.indexOf("id: bootLockProc")) + "onExited:".length).expr;

function process(isShell) {
  let announced = "";
  const shown = [];
  const root = { pending: [], tacitVersion: "1.2.15" };
  const bootLockProc = { running: false };
  const scope = { root, bootLockProc, Config: { options: { updates: { enableCheck: true } } },
    IslandController: { enabled: true, suppressed: false, warmedUp: true, request: (name, data) => shown.push(data.text) },
    announcedFile: { text: () => announced, setText: t => { announced = t; } } };
  for (const name of ["announce", "say", "flush"]) {
    const f = qmlFunction(src, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  if (isShell) root.says = true;   // what shell.qml sets
  root.announce("tacit 1.2.14-2 -> 1.2.15-1");
  if (bootLockProc.running) inScope(scope, "", `return (${exited});`)()(0, 0);
  return { announced, shown };
}

console.log("== who says that updates are ready (services/Updates.qml, shell.qml)");
const settings = process(false);
check("Settings' copy says nothing and marks nothing said", settings.announced === "" && settings.shown.length === 0, JSON.stringify(settings));
const shell = process(true);
check("the shell's notch says 'Tacit 1.2.15 is ready', and marks it said", shell.shown[0] === "Tacit 1.2.15 is ready" && shell.announced !== "",
  JSON.stringify(shell));
check("shell.qml is the one that says", /\bUpdates\.says\s*=\s*true\b/.test(read("shell.qml")) && !/\bUpdates\.says\s*=/.test(read("tacit-settings.qml")));
done();
