// The notch's "just happened" rows for the clipboard (services/Recents.qml onClipboard(), run under node over cliphist's
// list as it changes): a copy is a row, and deleting the newest entry is not a copy of the one under it. cliphist gives
// every copy a higher number than the last, a copy of older text and a copy after a wipe too.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("services/Recents.qml");

console.log("== the clipboard in the notch's recent rows (services/Recents.qml)");
{
  const root = { lastEntryId: "", selfCopy: "", lastShotAt: 0, items: [], kindOf: () => "text" };
  const Cliphist = { entries: [], entryIsImage: () => false };
  const scope = { root, Cliphist, ToplevelManager: { activeToplevel: null }, FileUtils: { trimFileProtocol: s => s },
    Directories: { home: "/home/someone" } };
  for (const name of ["onClipboard", "add"]) {
    const f = qmlFunction(src, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  const list = (...e) => { Cliphist.entries = e; root.onClipboard(); return root.items.map(i => i.text); };
  list("2\tolder words", "1\tfirst");
  const copied = list("3\thunter2", "2\tolder words", "1\tfirst");
  check("a copy is a row", JSON.stringify(copied) === JSON.stringify(["hunter2"]), JSON.stringify(copied));
  const deleted = list("2\tolder words", "1\tfirst");
  check("deleting it from the palette's clipboard section is not news: 'older words' is not shown as just copied",
    JSON.stringify(deleted) === JSON.stringify(["hunter2"]), JSON.stringify(deleted));
  const next = list("4\tnew words", "2\tolder words", "1\tfirst");
  const again = list("5\tolder words", "4\tnew words", "1\tfirst");
  check("the next copy is a row, and copying older text again is too", JSON.stringify(again) === JSON.stringify(["older words", "new words", "hunter2"]),
    `${JSON.stringify(next)} then ${JSON.stringify(again)}`);
  list();
  const wiped = list("6\tafter a wipe");
  check("after the history is wiped, a copy is still a row", wiped[0] === "after a wipe", JSON.stringify(wiped));
}
done();
