// The project picker over the open files keeps the keyboard (code.qml): refocus() and show() are the window's own,
// run under node with the picker up (Ctrl+O) over an open file, as a question answered there, a tab key (Alt+2) and the
// keys that open the Finder or a new file's draft would leave it; the Shortcuts' enabled conditions are read as written.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the project picker keeps the keyboard over the open files (code.qml)");
const src = read("code.qml");
const went = [];
const editor = { focusEditor: () => went.push("editor") };
const root = { picking: true, treeShown: true, current: 0, docs: [{ rel: "a.py", doc: editor }, { rel: "b.py", doc: editor }] };
Object.defineProperty(root, "cur", { get: () => root.docs[root.current]?.doc ?? null });
const scope = { root, project: { root: "/home/a/p", reveal() {} }, picker: { focusFilter: () => went.push("picker") },
  tree: { forceActiveFocus: () => went.push("tree") }, sessionLater: { restart() {} } };
for (const name of ["refocus", "show", "materialize"]) {
  const f = qmlFunction(src, name);
  root[name] = inScope(scope, f.params, f.body);
}

root.refocus();      // a "changed on disk" question answered, or the Finder closed, while the picker is up
check("a question answered over the picker leaves the keys in its field", went.join() === "picker", went.join());
went.length = 0;
root.show(1);        // Alt+2 or Ctrl+PgDown
check("a tab shown under the picker does not take the keys", went.join() === "picker", went.join());
root.picking = false;
went.length = 0;
root.refocus();
check("with the picker gone the open file takes them, as before", went.join() === "editor", went.join());

for (const seq of ["Ctrl+N", "Ctrl+Shift+N", "Ctrl+P", "Ctrl+Shift+F"]) {
  const m = new RegExp(`Shortcut \\{ sequence: "${seq.replace(/\+/g, "\\+")}"; enabled: ([^;]+);`).exec(src);
  const on = picking => inScope({ root: { ask: null, picking }, project: { root: "/home/a/p" } }, "", `return (${m[1]});`)();
  check(`${seq} waits while the picker is up`, m && on(true) === false && on(false) === true, m ? m[1] : "no such Shortcut");
}
done();
