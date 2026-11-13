// Settings > About > Updates' release notes (services/Updates.qml, tacit-settings.qml): Updates' reading of the release
// file runs under node over a run of starts, with updates-version in memory, then its installedNotes and Settings'
// shownNotes and the notes' title on a notes.json of seven releases. After an update over skipped releases every one it
// brought is listed, not only the newest; "What's new" titles only the releases waiting, and the installed one's notes
// are never titled as if they were coming.
import { inScope, matchBrace, qmlProperty, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the notes About shows (services/Updates.qml, tacit-settings.qml)");
const upd = read("services/Updates.qml");
const at = upd.indexOf("onLoaded:", upd.indexOf('path: "/usr/share/tacit/release"'));
const open = upd.indexOf("{", at);
const onRelease = upd.slice(open + 1, matchBrace(upd, open));
const newerFn = qmlFunction(upd, "newer");
const installedExpr = qmlProperty(upd, "installedNotes");

const file = { saved: "" };
const versionFile = { text: () => file.saved, setText: t => { file.saved = t; } };
const root = { currentVersion: "", versionBefore: "", notes: [] };
root.newer = inScope({}, newerFn.params, newerFn.body);
const start = version => inScope({ root, versionFile, text: () => `NAME="Tacit"\nVERSION="${version}"\n` }, "", onRelease)();

start("1.2.9");
check("the first start remembers its version, with none before it", root.versionBefore === "" && JSON.parse(file.saved || "{}").version === "1.2.9", file.saved);
start("1.2.9");
check("a start on the same version changes nothing", root.versionBefore === "", root.versionBefore);
start("1.2.14");
check("the start after an update knows the version it ran before", root.versionBefore === "1.2.9", `before "${root.versionBefore}"`);
start("1.2.14");
check("and keeps knowing it at the next start", root.versionBefore === "1.2.9", `before "${root.versionBefore}"`);

root.notes = ["1.2.14", "1.2.13", "1.2.12", "1.2.11", "1.2.10", "1.2.9", "1.2.8"].map(v => ({ version: v, changes: [`${v} change`] }));
const installed = installedExpr ? inScope({ root }, "", `return (${installedExpr});`)() : [];
check("after it, the notes of every release it brought are listed", installed.map(r => r.version).join(" ") === "1.2.14 1.2.13 1.2.12 1.2.11 1.2.10",
  installed.map(r => r.version).join(" ") || "none");
root.versionBefore = "";
const fresh = installedExpr ? inScope({ root }, "", `return (${installedExpr});`)() : [];
check("with no version known before, only this one's", fresh.map(r => r.version).join(" ") === "1.2.14", fresh.map(r => r.version).join(" ") || "none");

// Settings: the notes shown and their title
const app = read("tacit-settings.qml");
const group = app.slice(app.indexOf("id: updatesGroup"));
const waitingExpr = qmlProperty(group, "notesWaiting");
const shownExpr = qmlProperty(group, "shownNotes");
const titleAt = group.indexOf("text:", group.indexOf("model: updatesGroup.shownNotes"));
const titleExpr = group.slice(titleAt + 5, group.indexOf("\n", titleAt)).trim();
function about(ready, nextNotes) {
  const Updates = { nextNotes, installedNotes: installed, notes: root.notes, currentVersion: "1.2.14" };
  const updatesGroup = { ready };
  if (waitingExpr) updatesGroup.notesWaiting = inScope({ Updates, updatesGroup }, "", `return (${waitingExpr});`)();
  const shown = inScope({ Updates, updatesGroup }, "", `return (${shownExpr});`)();
  return shown.map(modelData => inScope({ Updates, updatesGroup, modelData }, "", `return (${titleExpr});`)());
}
const otherParts = about(true, []);
check("with only other parts waiting, this computer's notes are not titled as coming", otherParts.length > 0 && otherParts.every(t => t.startsWith("New in Tacit")), otherParts.join(" | "));
const coming = about(true, [{ version: "1.2.15", changes: [] }]);
check("a Tacit release waiting is titled What's new", coming.join(" | ") === "What's new in Tacit 1.2.15", coming.join(" | "));
const none = about(false, []);
check("nothing waiting, the releases it got are listed", none.join(" | ") === "New in Tacit 1.2.14 | New in Tacit 1.2.13 | New in Tacit 1.2.12 | New in Tacit 1.2.11 | New in Tacit 1.2.10", none.join(" | "));
done();
