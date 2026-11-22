// A file's path typed or pasted into Files' path field opens its folder with the file selected
// (modules/ii/files/FilesWindow.qml): the field's Enter, goTyped() and typedProbed() run under node, the probe's answer
// given as the test command would. Before, the path went to go() as a folder and showed it empty.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a pasted file path opens its folder with the file selected (FilesWindow.qml)");
const src = read("modules/ii/files/FilesWindow.qml");
const calls = [];
const typedProbe = { path: "", running: false };
const win = { folder: "/home/u", home: "/home/u", decodePath: s => decodeURIComponent(s),
  show: (f, sel) => calls.push(["show", f, sel]), go: p => calls.push(["go", p]) };
const scope = { win, typedProbe, Files: { parent: p => p.replace(/\/[^/]*$/, "") || "/" } };
for (const name of ["typedPath", "goTyped", "typedProbed"]) {
  try { const f = qmlFunction(src, name); win[name] = inScope(scope, f.params, f.body); } catch (e) { win[name] = null; }
}
const m = /if \(t\.length > 0\) (win\.[^;]+);/.exec(src);
const enter = t => inScope({ win, t }, "", `${m[1]};`)();

// the field's Enter on a file's path, then the probe answering "a file"
enter("/run/media/u/FILES/Music/song.wav");
const asked = typedProbe.path;
if (win.typedProbed && asked) win.typedProbed(true, asked);
check("Enter on a file's path asks whether it is a file before going anywhere", asked === "/run/media/u/FILES/Music/song.wav", asked || JSON.stringify(calls));
check("a file's path opens its folder with the file selected",
  JSON.stringify(calls.at(-1)) === JSON.stringify(["show", "/run/media/u/FILES/Music", "/run/media/u/FILES/Music/song.wav"]), JSON.stringify(calls));
calls.length = 0;
if (win.typedProbed) win.typedProbed(false, "/home/u/Music");
check("a folder's path still goes to the folder", JSON.stringify(calls) === JSON.stringify([["go", "/home/u/Music"]]), JSON.stringify(calls));
done();
