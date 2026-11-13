// Rename many in Pinax shows why Rename waits when the clash is past the fifth name (modules/ii/files/RenameSheet.qml):
// the sheet's own plan, its preview rows' model and its "and N more" line run under node on twelve photos numbered
// "Trip" where Trip 08.jpg is already in the folder.
import { inScope, matchBrace, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Rename many shows the clash that keeps Rename waiting (RenameSheet.qml)");
const src = read("modules/ii/files/RenameSheet.qml");
const block = name => { const open = src.indexOf("{", src.indexOf(`readonly property var ${name}:`)); return src.slice(open + 1, matchBrace(src, open)); };
const sheet = { mode: "number", paths: Array.from({ length: 12 }, (_, i) => `/home/a/Photos/IMG_${100 + i}.jpg`), takenNames: { "Trip 08.jpg": true } };
const scope = { sheet, find: { text: "" }, replaceWith: { text: "" }, base: { text: "Trip" }, start: { text: "" } };
sheet.plan = inScope(scope, "", block("plan"))();
if (src.includes("readonly property var shown:")) sheet.shown = inScope(scope, "", block("shown"))();
const repeater = objectWith(src, "model: sheet.");
const rows = inScope(scope, "", `return (${readExpression(repeater, repeater.indexOf("model:") + 6).expr});`)();
const moreAt = src.indexOf("text: `and ");
const more = inScope(scope, "", `return (${readExpression(src, moreAt + 5).expr});`)();
const bad = rows.find(r => r.bad);
check("the preview shows the clash with Trip 08.jpg", bad?.name === "Trip 08.jpg" && bad.bad === "already here", JSON.stringify(rows.map(r => r.name + (r.bad ? ` (${r.bad})` : ""))));
check("the first five are still shown", rows.slice(0, 5).map(r => r.name).join() === "Trip 01.jpg,Trip 02.jpg,Trip 03.jpg,Trip 04.jpg,Trip 05.jpg");
check("'and N more' counts the rows not shown", more === `and ${12 - rows.length} more`, more);
done();
