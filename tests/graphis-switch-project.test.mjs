// Changes let go with "Don't save" when another project opens are not offered back (code.qml): guardUnsaved, the
// answer's run, setProject and dropKept are the window's own, run under node on a project with one unsaved file whose
// record was already written aside (keep(), two seconds after the edit).
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== another project opened with \"Don't save\" leaves nothing to restore (code.qml)");
const src = read("code.qml");
const removed = [];
const project = { root: "/home/a/p", setRoot(d) { project.root = d; } };
const root = { keptDir: "/home/a/.local/state/quickshell/user/graphis-unsaved", ask: null, picking: true, current: 0,
  saveSession() {}, remember() {}, restoreSession() {}, offerKept() {} };
const scope = { root, project, tree: { forceActiveFocus() {} }, Voice: { count: (n, w) => `${n} ${w}s` },
  Quickshell: { execDetached: argv => { if (argv[0] === "rm") removed.push(...argv.slice(2)); } }, Qt: { md5: s => `md5(${s})` } };
for (const name of ["unsavedDocs", "guardUnsaved", "openProject", "setProject", "dropKept", "keptPath"]) {
  const f = qmlFunction(src, name);
  root[name] = inScope(scope, f.params, f.body);
}
const abs = "/home/a/p/a.py";
root.docs = [{ rel: "a.py", doc: { abs, rel: "a.py", dirty: true, session: null, destroy() {} } }];
root.keptText = { [abs]: "print('draft')\n" };

root.openProject("/home/a/q");
const dontSave = root.ask?.buttons.find(b => b.label === "Don't save");
check("opening another project asks about the unsaved file", !!dontSave, JSON.stringify(root.ask));
dontSave?.run();
check("the other project is open", project.root === "/home/a/q", project.root);
check("the record kept aside for a.py is removed", removed.includes(root.keptPath(abs)), `removed ${JSON.stringify(removed)}`);
check("and the keeper no longer holds its text", !(abs in root.keptText), JSON.stringify(root.keptText));
done();
