// The desktop's words go through Translation.tr (the tags' menu and drop ghost, the Notes, To-Do, Image converter, You and
// media widgets): each phrase is looked for as a Translation.tr key in its file, and the tags' menu (DesktopTags.qml's
// openMenu() and onPicked) and the drop ghost's name run under node with the words in German, since a pick that went by
// the words would stop working once they are translated.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the desktop's words in another language (DesktopTags.qml, the desktop widgets)");
const phrases = {
  "modules/ii/desktopIcons/DesktopTags.qml": ["Open", "Rename", "Move to the trash", "Put 1 file on the Desktop", "Put %1 files on the Desktop"],
  "services/DesktopIcons.qml": ["Put 1 file on the Desktop", "Put %1 files on the Desktop"],
  "modules/ii/background/widgets/notes/NotesWidget.qml": ["Notes", "Type your note..."],
  "modules/ii/background/widgets/todo/TodoWidget.qml": ["To-Do", "Type your task..."],
  "modules/ii/background/widgets/images/ImageConverterWidget.qml": ["Drop pictures here\nto convert to .%1", "Release to convert to .%1", "Convert to",
    "Converting...", "Converting %1 / %2...", "Saved: %1", "%1 files converted", "Failed: %1", "No supported files dropped.",
    "Converting to PDF...", "Merging %1 images into PDF...", "%1 pages → %2", "PDF failed.\nIs ImageMagick installed?", "Could not read file path."],
  "modules/ii/background/widgets/usercard/UserCardWidget.qml": ["Hi, %1", "Up %1"],
  "modules/ii/background/widgets/media/MediaWidget.qml": ["Play"],
};
for (const [file, list] of Object.entries(phrases)) {
  const src = read(file);
  const missing = list.filter(p => !src.includes(`Translation.tr(${JSON.stringify(p)})`));
  check(`${file.replace(/.*\//, "")}: ${list.length === 1 ? "its phrase is" : `${list.length} phrases are`} translated`, missing.length === 0, `not through Translation.tr: ${missing.map(p => JSON.stringify(p)).join(", ")}`);
}

// the tags' menu in German: each line still does its own thing
const tags = read("modules/ii/desktopIcons/DesktopTags.qml");
const openMenu = qmlFunction(tags, "openMenu");
const pickedAt = tags.indexOf("onPicked:");
const picked = readExpression(tags, pickedAt + "onPicked:".length).expr;
const german = { "Open": "Öffnen", "Rename": "Umbenennen", "Move to the trash": "In den Papierkorb", "Put 1 file on the Desktop": "1 Datei auf den Schreibtisch",
  "Put %1 files on the Desktop": "%1 Dateien auf den Schreibtisch" };
const Translation = { tr: s => Object.assign(new String(german[s] ?? s), { arg(v) { return String(this).replace("%1", v); } }) };
for (const one of [true, false]) {
  const did = [];
  const DesktopIcons = { selected: one ? ["Notes.txt"] : ["a.txt", "b.txt"], editing: "", open: n => did.push(`open ${n}`), trash: l => did.push(`trash ${l.join("+")}`) };
  const menu = { items: [], openAt() {}, keepInside() {} };
  const scope = { menu, board: {}, DesktopIcons, Translation };
  inScope(scope, openMenu.params, openMenu.body)(10, 10);
  const labels = menu.items.map(i => String(i.label));
  const pick = inScope(scope, "", `return (${picked});`)();
  menu.items.forEach((_, i) => {
    pick(i);
    if (DesktopIcons.editing) { did.push(`rename ${DesktopIcons.editing}`); DesktopIcons.editing = ""; }
  });
  const want = one ? ["open Notes.txt", "rename Notes.txt", "trash Notes.txt"] : ["open a.txt", "open b.txt", "trash a.txt+b.txt"];
  check(`in German the menu for ${one ? "one file" : "two files"} reads ${labels.join(", ")} and each does its own thing`,
    JSON.stringify(did) === JSON.stringify(want), did.join(", "));
}
// the drop ghost: one file and three
const ghostAt = tags.indexOf("name:", tags.indexOf("id: ghostTag"));
const ghost = readExpression(tags, ghostAt + "name:".length).expr;
const say = n => String(inScope({ DesktopIcons: { dropCount: n }, Translation, Voice: { count: (k, w) => `${k} ${w}${k === 1 ? "" : "s"}` } }, "", `return (${ghost});`)());
check("in German the drop ghost says 1 Datei and 3 Dateien", say(1) === "1 Datei auf den Schreibtisch" && say(3) === "3 Dateien auf den Schreibtisch", `${say(1)} / ${say(3)}`);
done();
