// A double click on Shut down or Restart on the Session screen (modules/ii/sessionScreen/SessionScreen.qml): its own
// activate(), which arms a two-press action on the first press and runs it on the next, run under node with a clock of
// its own and Qt's double-click time of 400 ms.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a double click on the Session screen's Shut down (SessionScreen.qml)");
const src = read("modules/ii/sessionScreen/SessionScreen.qml");
const activate = qmlFunction(src, "activate");

// presses on action i at the given times (ms): which of them ran the action
function presses(i, times) {
  let now = 0;
  const ran = [];
  const sessionRoot = {
    actions: [0, 1, 2, 3, 4, 5, 6, 7].map(k => ({ busy: "busy", run: () => ran.push(now) })),
    twoPress: [0, 1, 4, 5, 6], armedIndex: -1, armedAt: 0, focusIndex: 3, waitingFor: "", failedText: "",
    hide() {},
  };
  const scope = { sessionRoot, disarmTimer: { restart() {} }, Date: { now: () => now }, Qt: { styleHints: { mouseDoubleClickInterval: 400 } } };
  const run = inScope(scope, activate.params, activate.body);
  for (const t of times) {
    now = t;
    // a run leaves the screen waiting under its busy word, which would turn the presses after it away
    sessionRoot.waitingFor = "";
    run(i);
  }
  return ran;
}
check("a double click on Shut down (100 ms apart) only arms it", presses(0, [0, 100]).length === 0, `ran at ${presses(0, [0, 100]).join(", ")} ms`);
check("and on Restart", presses(1, [0, 150]).length === 0, `ran at ${presses(1, [0, 150]).join(", ")} ms`);
check("a second press after reading Press again (900 ms) runs it", presses(0, [0, 900]).join() === "900", `ran at ${presses(0, [0, 900]).join(", ")} ms`);
check("a double click, then a press: the press runs it", presses(0, [0, 100, 1200]).join() === "1200", `ran at ${presses(0, [0, 100, 1200]).join(", ")} ms`);
check("Lock still runs on the first press", presses(3, [0]).join() === "0", `ran at ${presses(3, [0]).join(", ")} ms`);
done();
