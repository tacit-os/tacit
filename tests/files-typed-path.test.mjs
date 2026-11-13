// A path typed into Pinax's path field (Ctrl+L) goes where it says (modules/ii/files/FilesWindow.qml): the field's own
// Enter handler and the window's typedPath run under node from ~/Documents with a bare name, ~, ~/..., ~name, ".." and
// an absolute path.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the path field reads what is typed as a path (FilesWindow.qml)");
const src = read("modules/ii/files/FilesWindow.qml");
const field = objectWith(src, "id: pathEdit");
const open = field.indexOf("{", field.indexOf("Keys.onPressed: event =>"));
const handler = field.slice(open + 1, matchBrace(field, open));
const Qt = { Key_Escape: 0x01000000, Key_Return: 0x01000004, Key_Enter: 0x01000005 };
function typed(text) {
  let went = null;
  const win = { home: "/home/a", folder: "/home/a/Documents", editingPath: true, go: p => { went = p; } };
  const f = qmlFunction(src, "typedPath");
  if (f) win.typedPath = inScope({ win }, f.params, f.body);
  inScope({ win, text, Qt }, "event", handler)({ key: Qt.Key_Return, accepted: false });
  return went;
}
for (const [text, want, what] of [["Downloads", "/home/a/Documents/Downloads", "a bare name is a folder in the one shown"],
  ["~", "/home/a", "~ is home"], ["~/Music", "/home/a/Music", "~/Music is in home"], ["..", "/home/a", ".. is the folder above"],
  ["../Pictures/./2026", "/home/a/Pictures/2026", "../Pictures/./2026 is walked"], ["~bob", "/home/a/Documents/~bob", "~bob is a name, not <home>bob"],
  ["/etc/", "/etc", "an absolute path is itself"]])
  check(`${what} (${text})`, typed(text)?.replace(/(.)\/+$/, "$1") === want, `went to ${typed(text)}`);   // go() trims a trailing /
done();
