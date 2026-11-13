// The to-do list read from an empty todo.json (services/Todo.qml's own onLoaded, run under node): a file cut to zero
// bytes by a crash or a power cut is an empty list, as Notes reads one, not a list that "could not be read" for good.
import { inScope, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("services/Todo.qml");
const at = src.indexOf("onLoaded:", src.indexOf("id: todoFileView"));
const body = readExpression(src, at + "onLoaded:".length).expr.slice(1, -1);
const load = text => {
  const root = { list: ["kept"], broken: false };
  inScope({ root, todoFileView: { text: () => text }, console: { log() {} } }, "", body)();
  return root;
};

console.log("== the to-do list from an empty file (services/Todo.qml)");
for (const [what, text] of [["zero bytes", ""], ["only a line break", "\n"]]) {
  const r = load(text);
  check(`${what}: an empty list that takes new tasks`, !r.broken && Array.isArray(r.list) && r.list.length === 0, JSON.stringify(r));
}
const tasks = load('[{"content":"milk","done":false}]');
check("a list is read as before", !tasks.broken && tasks.list[0]?.content === "milk", JSON.stringify(tasks));
const bad = load('[{"content":"mi');
check("a file that is not JSON still keeps what is in memory and is not written over", bad.broken && bad.list[0] === "kept", JSON.stringify(bad));
done();
