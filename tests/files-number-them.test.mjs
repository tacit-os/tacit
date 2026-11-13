// "Number them" in Pinax's Rename many starts from the first name without its extension, as the plan takes it
// (modules/ii/files/RenameSheet.qml): the sheet's own open() and plan run under node on files with long, double and
// short extensions, a numbered photo and a dotfile.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Number them suggests the name without its extension (RenameSheet.qml)");
const src = read("modules/ii/files/RenameSheet.qml");
const planAt = src.indexOf("{", src.indexOf("readonly property var plan:"));
function numbered(names) {
  const field = () => ({ text: "", focusIn() {} });
  const sheet = { visible: false, takenNames: {}, focusFirst() {} };
  const scope = { sheet, find: field(), replaceWith: field(), base: field(), start: field() };
  const open = qmlFunction(src, "open");
  inScope(scope, open.params, open.body)(names.map(n => `/home/a/Downloads/${n}`));
  sheet.mode = "number";
  const plan = inScope(scope, "", src.slice(planAt + 1, matchBrace(src, planAt)))();
  return { base: scope.base.text, first: plan[0].name };
}
for (const [names, base, first] of [[["a.torrent", "b.torrent"], "a", "a 01.torrent"], [["notes.markdown", "todo.markdown"], "notes", "notes 01.markdown"],
  [["x.tar.gz", "y.tar.gz"], "x", "x 01.tar.gz"], [["IMG_0042.jpg", "IMG_0043.jpg"], "IMG", "IMG 01.jpg"], [[".bashrc", ".profile"], ".bashrc", ".bashrc 01"]]) {
  const r = numbered(names);
  check(`${names[0]}: the Name field starts as "${base}", so the first becomes ${first}`, r.base === base && r.first === first, `Name "${r.base}", first "${r.first}"`);
}
done();
