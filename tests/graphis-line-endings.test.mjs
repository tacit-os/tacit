// Graphis writes each line's own ending back (modules/code/CodeDoc.qml): a file that mixes "\n" and "\r\n", or breaks
// lines at a lone "\r", saved after one change keeps every other line as it was. save(), fromDisk(), toDisk() and the
// file's Component.onCompleted are the file's own, run under node with the editor replaced by a buffer that holds every
// break as "\n" (fromDisk's work), as TextEdit does.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Graphis writes back each line's own ending (CodeDoc.qml)");
const src = read("modules/code/CodeDoc.qml");
const show = s => JSON.stringify(s);
const block = (name, after = 0) => { const open = src.indexOf("{", src.indexOf(`${name}: {`, after)); return src.slice(open + 1, matchBrace(src, open)); };

function editor(disk) {
  let held = "", written = null;
  const area = { textDocument: {}, cursorPosition: 0, get text() { return held; }, set text(t) { held = t; } };
  const file = { text: () => disk, data: () => new TextEncoder().encode(disk).buffer, setText(t) { written = t; disk = t; } };
  const doc = { rel: "run.sh", problem: "", loaded: false, started: false, status: "", watchOnOpen: false, session: null,
    conflicted: false, missing: false, selfWrite: false, savingText: "", lastDisk: "", dirty: false, eol: "\n",
    kindOf: () => "text", detectIndent: () => "    ", announce() {}, refreshMarks() {} };
  const scope = { doc, area, Edit: { text: () => held }, disk: file, Voice: { size: n => `${n} B` } };
  for (const name of ["fromDisk", "toDisk", "validUtf8", "unkept", "bufferText", "save"]) {
    const f = qmlFunction(src, name);
    if (f) doc[name] = inScope(scope, f.params, f.body);
  }
  const completed = inScope(scope, "", block("Component.onCompleted", src.indexOf("const raw = disk.text()") - 400));
  completed();
  // one change, then Ctrl+S
  return { edit: (from, to) => { held = held.replace(from, to); doc.dirty = true; }, saved: () => (doc.save(), written) };
}

{
  // a script with one line pasted from Windows
  const e = editor("#!/bin/sh\necho one\necho two\r\necho three\n");
  e.edit("echo one", "echo 1");
  const out = e.saved();
  check("a script with one Windows line keeps every other line's \"\\n\" (the shebang too)", out === "#!/bin/sh\necho 1\necho two\r\necho three\n", `wrote ${show(out)}`);
}
{
  // the changed line was the Windows one: it keeps its own ending, and a line added after it takes the file's commonest
  const e = editor("a\r\nb\nc\nd\n");
  e.edit("a", "A\nnew");
  const out = e.saved();
  check("lines added in a mixed file take its commonest ending; the lines around keep theirs", out === "A\r\nnew\r\nb\nc\nd\n" || out === "A\nnew\r\nb\nc\nd\n", `wrote ${show(out)}`);
}
{
  // a log with progress lines: each update ends in a lone "\r"
  const e = editor("copy 10%\rcopy 50%\rcopy 100%\ndone\n");
  e.edit("done", "Done");
  const out = e.saved();
  check("a lone \"\\r\" is written back as \"\\r\", not as a new line", out === "copy 10%\rcopy 50%\rcopy 100%\nDone\n", `wrote ${show(out)}`);
}
{
  const e = editor("one\r\ntwo\r\n");
  e.edit("one", "one\nmore");
  const out = e.saved();
  check("a Windows file stays Windows throughout, as before", out === "one\r\nmore\r\ntwo\r\n", `wrote ${show(out)}`);
}
{
  const e = editor("one\ntwo\n");
  e.edit("two", "2");
  const out = e.saved();
  check("a plain file stays plain", out === "one\n2\n", `wrote ${show(out)}`);
}
done();
