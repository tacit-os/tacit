// Graphis keeps what a file holds (modules/code/CodeDoc.qml): a non-breaking space and a line separator (U+2028) are
// written back as they were, and a file with what the buffer cannot hold (U+2029) is not opened to be saved over.
// save(), bufferText(), the text's onTextChanged and the file's Component.onCompleted are the file's own, run under node
// with the editor replaced: its text gives U+00A0 as a space and U+2028/U+2029 as "\n", as Qt's TextEdit.text does
// (QTextDocument::toPlainText; seen on Qt 6.12), and Tacit.Edit's text() gives the buffer as it is, U+2029 as "\n".
import { inScope, matchBrace, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Graphis writes back non-breaking spaces and line separators (CodeDoc.qml)");
const src = read("modules/code/CodeDoc.qml");
const NBSP = String.fromCharCode(0xa0), LS = String.fromCharCode(0x2028), PS = String.fromCharCode(0x2029);
const show = s => JSON.stringify(s.replaceAll(NBSP, "<nbsp>").replaceAll(LS, "<U+2028>").replaceAll(PS, "<U+2029>"));
// a handler's block: the first "<name>: {" after `after`
const block = (name, after = 0) => { const open = src.indexOf("{", src.indexOf(`${name}: {`, after)); return src.slice(open + 1, matchBrace(src, open)); };

function editor(disk, { oldEdit = false } = {}) {
  let held = "";                     // what the buffer holds
  let written = null;
  const area = { textDocument: {}, cursorPosition: 0,
    get text() { return held.replaceAll(NBSP, " ").replaceAll(LS, "\n").replaceAll(PS, "\n"); },
    set text(t) { held = t.replaceAll(PS, "\n"); textChanged(); } };   // TextEdit says textChanged at once
  const Edit = oldEdit ? {} : { text: () => held };
  const file = { text: () => disk, data: () => new TextEncoder().encode(disk).buffer, setText(t) { written = t; } };
  const doc = { rel: "notes.md", problem: "", loaded: false, started: false, status: "", watchOnOpen: false, session: null,
    conflicted: false, missing: false, selfWrite: false, savingText: "", lastDisk: "", cached: "", dirty: false, eol: "\n",
    kindOf: () => "text", detectIndent: () => "    ", announce() {}, refreshMarks() {}, edited() {}, layoutTick: 0 };
  const scope = { doc, area, Edit, disk: file, Voice: { size: n => `${n} B` } };
  for (const name of ["fromDisk", "toDisk", "validUtf8", "unkept", "bufferText", "save"]) {
    const f = qmlFunction(src, name);
    if (f) doc[name] = inScope(scope, f.params, f.body);
  }
  for (const name of ["notUtf8", "unkeptChars"]) {
    const e = qmlProperty(src, name);
    if (e) doc[name] = inScope(scope, "", `return (${e});`)();
  }
  const textChanged = inScope(scope, "", block("onTextChanged", src.indexOf("id: area")));
  const completed = inScope(scope, "", block("Component.onCompleted", src.indexOf("const raw = disk.text()") - 400));
  // a key typed, or taken back with Ctrl+Z: the buffer changes and says so
  const type = (at, s) => { held = held.slice(0, at) + s + held.slice(at); textChanged(); };
  const untype = (at, n) => { held = held.slice(0, at) + held.slice(at + n); textChanged(); };
  return { doc, open: completed, type, untype, saved: () => (doc.save(), written), held: () => held };
}

{
  // French with a non-breaking space before the colon and in the price; JSON written by JavaScript with a U+2028
  const disk = `Prix${NBSP}: 10${NBSP}€\n{"note": "one${LS}two"}\n`;
  const e = editor(disk);
  e.open();
  check("a file with non-breaking spaces and U+2028 opens to be edited", e.doc.problem === "" && e.held() === disk, e.doc.problem);
  e.type(0, "x");
  e.untype(0, 1);
  check("a key typed and taken back leaves nothing unsaved", e.doc.dirty === false, `cached ${show(e.doc.cached)}`);
  e.type(0, "Le ");
  const out = e.saved();
  check("a typo fixed and saved writes the rest back as it was", out === `Le ${disk}`, `wrote ${show(out ?? "nothing")}`);
}
{
  const disk = `a paragraph${PS}another\n`;
  const e = editor(disk);
  e.open();
  check("a file with U+2029, which the buffer turns into a line break, is not opened to be saved over",
    e.doc.problem.length > 0 && e.doc.save() === false, `problem "${e.doc.problem}", buffer ${show(e.held())}`);
}
{
  // a Tacit.Edit built before text() (an older copy in ~/.local/lib/qml): editing still works, as before
  const e = editor("plain text\n", { oldEdit: true });
  let threw = "";
  try { e.open(); e.type(0, "x"); } catch (err) { threw = String(err); }
  check("with an older Tacit.Edit the file still opens, edits and saves", !threw && e.saved() === "xplain text\n", threw);
}
done();
