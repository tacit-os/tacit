// An update that stopped partway (services/Updates.qml, the notch's "updated" card): the notch said "The update stopped
// partway · it tries again", though nothing tries again by itself (tacit-update install takes /system-update away first
// and restarts whatever happened). Updates' own resultFile onLoaded reads a failed result; the header's rightFor() picks
// the card's right side, whose Restart pill runs under node.
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== an update that stopped partway (Updates.qml, IslandHeader.qml)");
const src = read("services/Updates.qml");
const at = src.indexOf("onLoaded:", src.indexOf("id: resultFile"));
const loaded = readExpression(src, at + "onLoaded:".length).expr;
function card(result) {
  const said = [];
  const file = text => ({ text: () => text, setText() {} });
  const scope = { root: { say: (name, data) => said.push({ name, data }) }, resultFile: file(JSON.stringify(result)), seenFile: file(""),
    announcedFile: file("1.2.15"), JSON };
  inScope(scope, "", `${loaded.replace(/^\{|\}$/g, "")}`)();
  return said[0];
}
const hsrc = read("modules/ii/island/IslandHeader.qml");
const rightFor = qmlFunction(hsrc, "rightFor");
const wings = { updatedNotesWing: "notes", updatedRetryWing: "retry", messageGlyphWing: "words", updateAnswerWing: "answer" };
const sideFor = payload => inScope({ root: {}, IslandController: { payload, transientShowing: true }, ...wings }, rightFor.params, rightFor.body)("updated");

{
  const c = card({ ok: false, at: 1800000000 });
  check("the card says \"Didn't install. Restart to try again.\"", c?.name === "updated" && c.data.text === "Didn't install. Restart to try again.",
    `${c?.name}: ${c?.data?.text}`);
  check("its right side is a Restart", sideFor(c.data) === "retry", `the right side is ${sideFor(c.data)}`);
  const at = hsrc.indexOf("id: updatedRetryWing");
  const wing = at < 0 ? "" : hsrc.slice(at, matchBrace(hsrc, hsrc.indexOf("{", at)));
  const text = wing.match(/\n\s*text:\s*"([^"]+)"/)?.[1];
  const action = wing.match(/\n\s*action:\s*/);
  let ran = 0;
  if (action) inScope({ Updates: { restartNow: () => ran++ }, IslandController: { dismiss() {} } }, "", `return (${readExpression(wing, action.index + action[0].length).expr});`)()();
  check("the Restart pill restarts to install again, as the ready card's does", text === "Restart" && ran === 1, `"${text}", restartNow ran ${ran} times`);
}
{
  const c = card({ ok: false, untouched: true, at: 1800000001 });
  check("one that changed nothing keeps its words, with no Restart", c.data.text === "The update didn't install · nothing changed" && sideFor(c.data) === "words",
    `${c.data.text}, the right side is ${sideFor(c.data)}`);
  const ok = card({ ok: true, version: "1.2.15-1", at: 1800000002 });
  check("a good one keeps What's new", ok.data.text === "Updated to Tacit 1.2.15" && sideFor(ok.data) === "notes", `${ok.data.text}, ${sideFor(ok.data)}`);
}
done();
