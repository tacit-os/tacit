// A name Pinax's rename field refuses is said, and Enter leaves the field open to fix it
// (modules/ii/files/FilesRow.qml, FilesWindow.qml): the field's own key and focus handlers run under node on a name
// already in the folder and on one holding a '/', then the list's onRefused, which puts the reason in the foot.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the rename field says why it refuses a name (FilesRow.qml)");
const field = objectWith(read("modules/ii/files/FilesRow.qml"), "id: nameEdit");
const body = name => { const at = field.indexOf("{", field.indexOf(name)); return field.slice(at + 1, matchBrace(field, at)); };
const Qt = { Key_Escape: 0x01000000, Key_Tab: 0x01000001, Key_Return: 0x01000004, Key_Enter: 0x01000005 };

function rowWith(text, taken) {
  const did = [];
  const row = { editing: true, index: 3, fileName: "draft.txt", taken,
    renamed: (i, n) => did.push(`renamed ${n}`), refused: why => did.push(`refused ${why}`), editDone: () => did.push("done"),
    ListView: { view: { editNext: () => did.push("next") } } };
  const scope = { row, text, activeFocus: false, Qt };
  const f = qmlFunction(field, "refusal");
  if (f) scope.refusal = inScope(scope, f.params, f.body);
  return { did, key: k => { const event = { key: k, accepted: false }; inScope(scope, "event", body("Keys.onPressed: event =>"))(event); return event.accepted; },
    away: () => inScope(scope, "", body("onActiveFocusChanged:"))() };
}

{
  const r = rowWith("final.txt", true);
  r.key(Qt.Key_Return);
  check("Enter on a name already here says so and keeps the field", r.did.join() === "refused final.txt is already here", r.did.join());
}
{
  const r = rowWith("notes/final.txt", false);
  r.key(Qt.Key_Enter);
  check("Enter on a name with a '/' says it can't hold one and keeps the field", r.did.join() === "refused A name can't hold /", r.did.join());
}
{
  const r = rowWith("final.txt", true);
  r.away();
  check("a click elsewhere drops a name already here, saying why", r.did.join() === "refused final.txt is already here,done", r.did.join());
}
{
  const r = rowWith("final.txt", false);
  r.key(Qt.Key_Return);
  check("a free name is still taken on Enter", r.did.join() === "renamed final.txt,done", r.did.join());
}
// the list's row hands the reason to the window's foot
const win = read("modules/ii/files/FilesWindow.qml");
const m = /onRefused: why => \{([^\n]*)\}\n/.exec(win);
const w = { reason: "" };
let restarted = 0;
if (m) inScope({ win: w, reasonTimer: { restart: () => restarted++ } }, "why", m[1])("final.txt is already here");
check("the window's foot says the reason", w.reason === "final.txt is already here" && restarted === 1, m ? `reason "${w.reason}"` : "no onRefused on the list's rows");
done();
