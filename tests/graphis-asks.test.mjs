// Graphis's questions about a file (code.qml): "changed on disk", "couldn't save", "no longer on disk" wait their turn
// while another is asked. askLater(), nextAsk(), answer() and nameOf() are the file's own, and so are the open files'
// onConflict and onMissingOnSave, run under node on two open index.js in different folders: each must get its question.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Graphis asks about each open file, also two with the same name (code.qml)");
const src = read("code.qml");
// a handler of the open file's (CodeDoc in docComp), as a function of the file
const handler = name => {
  const at = src.indexOf(`${name}:`, src.indexOf("id: docComp"));
  const expr = readExpression(src, at + name.length + 1).expr;
  return docItem => inScope({ root, docItem, Voice: { cant: s => `Can't ${s}.` } }, "", `return (${expr});`)();
};

const root = { ask: null, waitingAsks: [], docs: [], refocus() {} };
for (const name of ["askLater", "nextAsk", "answer", "nameOf"]) {
  const f = qmlFunction(src, name);
  if (f) root[name] = inScope({ root }, f.params, f.body);
}
// an open file: what its answers did
const file = rel => ({ rel, did: [], reloadFromDisk() { this.did.push("reload"); }, keepMine() { this.did.push("keep"); },
  save(force) { this.did.push(force ? "save anyway" : "save"); return true; } });
const a = file("src/a/index.js"), b = file("src/b/index.js"), readme = file("README.md");
root.docs = [a, b, readme].map(doc => ({ rel: doc.rel, doc }));
const conflict = handler("onConflict"), missing = handler("onMissingOnSave");
const asked = () => root.ask?.text ?? "nothing";

// git pull rewrites both while each has unsaved edits: both are in conflict
conflict(a);
conflict(b);
conflict(b);                                    // the same file's change seen twice is one question
const first = asked();
check("the first index.js is asked about", /index\.js changed on disk/.test(first), first);
check("the second one's question waits, once", root.waitingAsks.length === 1, `${root.waitingAsks.length} waiting`);
root.answer(0);                                 // Reload, on the first
check("Reload reached the first file only", a.did.join() === "reload" && b.did.length === 0, `a ${a.did}, b ${b.did}`);
const second = asked();
check("then the second index.js is asked about", /index\.js changed on disk/.test(second), `asked: ${second}`);
check("the two questions name their folders, so they can be told apart",
  first.startsWith("a/index.js") && second.startsWith("b/index.js"), `"${first}", then "${second}"`);
root.answer(1);                                 // Keep mine, on the second
check("Keep mine reached the second file", b.did.join() === "keep", `b ${b.did}`);
check("and nothing is left to ask", root.ask === null && root.waitingAsks.length === 0, `asked: ${asked()}`);

// a file whose question waited is closed before its turn
conflict(a);
missing(readme);
root.docs = root.docs.filter(d => d.doc !== readme);
root.answer(0);
check("a question about a file closed while it waited is not asked", root.ask === null, `asked: ${asked()}`);
root.docs = [{ rel: readme.rel, doc: readme }];
missing(readme);
check("a file with a name of its own is named alone", asked().startsWith("README.md is no longer on disk"), asked());
done();
