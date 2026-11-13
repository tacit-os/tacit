// Files windows over a reload of the shell: FilesPanel.qml's create(), forget(), keep() and Component.onCompleted run
// under node with pretend windows, and services/Files.qml read as Quickshell 0.3.2 pairs a reload: singletons by file,
// a singleton's children by place (ReloadPropagator::onReload), a PersistentProperties copying its properties from the
// old one. shell.qml has to build Files before the reload ends (Reloadable::componentComplete: anything made after it
// gets no old instance), which the panel, built once Config is ready, never is.
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("Files windows after a reload of the shell (FilesPanel.qml, Files.qml, shell.qml)");

const files = read("services/Files.qml");
const panel = read("modules/ii/files/FilesPanel.qml");
const shell = read("shell.qml");

// the object children of Files.qml's Singleton, in order (what ReloadPropagator holds), with their bodies
function children(src) {
  const open = src.indexOf("{", src.search(/^Singleton\s*\{/m));
  const close = matchBrace(src, open), out = [];
  const re = /^ {4}([A-Z][\w.]*)\s*\{/gm;
  re.lastIndex = open;
  for (let m; (m = re.exec(src)) && m.index < close;) {
    const b = matchBrace(src, m.index + m[0].length - 1);
    out.push({ type: m[1], body: src.slice(m.index, b + 1) });
    re.lastIndex = b;
  }
  return out;
}

// a generation of the shell: Files (with its kept properties) and, once Config is ready, the panel
function generation(old) {
  const kids = children(files);
  // the reload: the old Files' child at the same place, copied over when both are PersistentProperties
  const kept = {};
  const at = kids.findIndex(k => k.type === "PersistentProperties");
  if (at >= 0) {
    for (const m of kids[at].body.matchAll(/property\s+[\w.<>]+\s+(\w+)\s*:\s*(.+)/g)) kept[m[1]] = inScope({}, "", `return (${m[2]});`)();
    const loadedEarly = /Component\.onCompleted\s*:\s*\{[^}]*\bFiles\.load\(\)/.test(shell);
    const before = old?.kids?.[at];
    if (loadedEarly && before?.type === "PersistentProperties") Object.assign(kept, structuredClone(old.kept));
  }
  const idOf = at >= 0 ? kids[at].body.match(/\bid:\s*(\w+)/)?.[1] : null;
  const Files = { picking: null, home: "/home/u" };
  for (const name of ["keepFolders", "keptFolders", "load"]) {
    const f = qmlFunction(files, name);
    if (f) Files[name] = inScope({ root: Files, ...(idOf ? { [idOf]: kept } : {}) }, f.params, f.body);
  }
  // pretend windows: a folder and its change signal, closing, forPick from Files.picking as the window sets it
  const windowComp = {
    createObject(parent, props) {
      const handlers = { closing: [], folderChanged: [] };
      const w = { forPick: Files.picking !== null, _folder: props.folder,
        closing: { connect: f => handlers.closing.push(f) }, folderChanged: { connect: f => handlers.folderChanged.push(f) },
        close() { handlers.closing.forEach(f => f()); }, go(f) { this._folder = f; handlers.folderChanged.forEach(h => h()); } };
      Object.defineProperty(w, "folder", { get: () => w._folder });
      return w;
    },
  };
  const root = { windows: [] };
  const scope = { root, windowComp, Files };
  for (const name of ["create", "keep", "forget", "newest", "newestOpen"]) {
    const f = qmlFunction(panel, name);
    if (f) root[name] = inScope(scope, f.params, f.body);
  }
  const ready = () => {
    const m = /^ {4}Component\.onCompleted\s*:\s*/m.exec(panel);
    if (m) inScope(scope, "", readExpression(panel, m.index + m[0].length).expr)();
  };
  return { kids, kept, Files, panel: root, ready, folders: () => root.windows.map(w => w.folder) };
}

{
  const a = generation(null);
  a.ready();
  check("a shell that starts opens no Files window", a.panel.windows.length === 0, `it opened ${JSON.stringify(a.folders())}`);
  a.panel.create("/home/u/Documents", "", "");
  a.panel.create("/home/u/Pictures", "", "");
  a.panel.windows[1].go("/run/media/u/USB/DCIM");
  a.Files.picking = { shell: "/usr/share/tacit", target: "claude" };
  a.panel.create("/home/u", "", "");     // Praxis' file chooser
  a.Files.picking = null;
  a.panel.create("/home/u/Music", "", "");
  a.panel.windows[3].close();

  const b = generation(a);
  b.ready();
  check("after a reload the windows open again at the folders they showed, without the file chooser's or the one closed",
    JSON.stringify(b.folders()) === JSON.stringify(["/home/u/Documents", "/run/media/u/USB/DCIM"]), `it opened ${JSON.stringify(b.folders())}`);
  const c = generation(b);
  c.ready();
  check("and again after the next reload", JSON.stringify(c.folders()) === JSON.stringify(["/home/u/Documents", "/run/media/u/USB/DCIM"]), `it opened ${JSON.stringify(c.folders())}`);
}
{
  const kids = children(files);
  check("what Files keeps is its first child, so the reload pairs it with the old one whatever comes after it",
    kids[0]?.type === "PersistentProperties", `its first child is ${kids[0]?.type ?? "nothing"}`);
}

done();
