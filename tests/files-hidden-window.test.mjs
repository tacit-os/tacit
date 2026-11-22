// A Files window hidden into the dock keeps the size the person chose, and comes back from the dock even when the shell
// missed the band's "hidden" (Discord, OYINOS, 2026-11-22): services/Files.qml's rememberWindow and its saved state,
// services/WindowBand.qml's strayHidden and the dock's activate (modules/ii/overview/PaletteDock.qml), run under node.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a hidden Files window: its size and its way back");
const files = read("services/Files.qml");
const root = { windowState: { w: 1000, h: 640, floating: true, maximised: false }, saves: 0 };
const fscope = { root, saveTimer: { restart() { root.saves++; } } };
for (const name of ["heldSize", "rememberWindow"]) {
  const f = qmlFunction(files, name);
  if (f) root[name] = inScope(fscope, f.params, f.body);
}
root.rememberWindow({ w: 640, h: 400, floating: true, maximised: false });
check("the held window's 640 x 400 is not kept as Files' size", root.windowState.w === 1000 && root.windowState.h === 640, JSON.stringify(root.windowState));
root.rememberWindow({ w: 1200, h: 760, floating: true, maximised: false });
check("a size the person chose is kept", root.windowState.w === 1200 && root.windowState.h === 760, JSON.stringify(root.windowState));
// the saved state of an earlier version that kept 640 x 400
const load = /if \(p\.window\)\s*root\.windowState = ([^;]+);/.exec(files);
const loaded = load ? inScope({ root: { windowState: { w: 1000, h: 640, floating: true }, heldSize: root.heldSize }, p: { window: { w: 640, h: 400, floating: true } } }, "", `return ${load[1]};`)() : null;
check("a saved 640 x 400 from an earlier version opens at the default size", loaded && loaded.w === 1000 && loaded.h === 640, JSON.stringify(loaded));

const band = read("services/WindowBand.qml");
const toplevel = { id: "files" };
const held = {};
const bandRoot = { held, norm: a => (a ?? "").replace(/^0x/, ""), heldAs: () => "", addressOf: () => "0xabc" };
const sh = qmlFunction(band, "strayHidden");
const strayHidden = sh ? inScope({ root: bandRoot, HyprlandData: { windowByAddress: { "0xabc": { workspace: { name: "special:tacit-hidden" } } } } }, sh.params, sh.body) : () => false;
check("a window on the band's hidden workspace with no event for it counts as hidden", strayHidden(toplevel) === true);
const shown = sh ? inScope({ root: bandRoot, HyprlandData: { windowByAddress: { "0xabc": { workspace: { name: "1" } } } } }, sh.params, sh.body) : () => true;
check("a window on an ordinary workspace does not", shown(toplevel) === false);

const dock = read("modules/ii/overview/PaletteDock.qml");
const act = qmlFunction(dock, "activate");
let reopened = null, focused = false;
const WindowBand = { heldAs: () => "", strayHidden: () => true, reopenAll: a => { reopened = a; }, reopenWhenHidden() {}, addressOf: () => "0xabc" };
const app = { appId: "org.quickshell", toplevels: [{ activated: false, activate() { focused = true; } }] };
inScope({ root: { opened() {}, launch() {} }, WindowBand }, act.params, act.body)(app);
check("a dock click sends such a window back instead of only focusing it", JSON.stringify(reopened) === JSON.stringify(["0xabc"]) && !focused,
  `reopened ${JSON.stringify(reopened)}, focused ${focused}`);
done();
