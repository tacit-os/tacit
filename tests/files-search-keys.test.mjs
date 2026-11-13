// Ctrl+W, Ctrl+L, Ctrl+B, Ctrl+. and Ctrl+Z work in Pinax while a search, Recent, the shelf or Large & old is shown
// (modules/ii/files/FilesWindow.qml): the window's own key handler runs under node with a search view up.
import { inScope, matchBrace } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the window's keys work in a search view (FilesWindow.qml)");
const keys = objectWith(read("modules/ii/files/FilesWindow.qml"), "id: keys");
const open = keys.indexOf("{", keys.indexOf("Keys.onPressed: event =>"));
const handler = keys.slice(open + 1, matchBrace(keys, open));
const Qt = { ControlModifier: 0x04000000, ShiftModifier: 0x02000000, AltModifier: 0x08000000,
  Key_Escape: 0x01000000, Key_Return: 0x01000004, Key_Enter: 0x01000005, Key_Up: 0x01000013, Key_Down: 0x01000015, Key_Space: 0x20,
  Key_W: 0x57, Key_L: 0x4c, Key_B: 0x42, Key_Z: 0x5a, Key_F: 0x46, Key_Period: 0x2e };
function press(key, view) {
  const did = [];
  const win = { editingIndex: -1, searching: true, visible: true, editingPath: false, railCompact: false, hits: [], searchCursor: 0, ...view,
    endSearch: () => did.push("end search"), stopJob: () => did.push("stop"), undo: () => did.push("undo"), openHit() {}, revealHit() {} };
  const scope = { win, Qt, K: { Kit: {} }, Files: { setRailPref: v => did.push(`rail ${v}`) }, hitList: { positionViewAtIndex() {} }, search: { forceActiveFocus() {}, selectAll() {} } };
  const event = { key, modifiers: key === Qt.Key_Escape ? 0 : Qt.ControlModifier, accepted: false };
  inScope(scope, "event", handler)(event);
  return { win, did, accepted: event.accepted };
}
for (const [what, view] of [["search results", {}], ["Recent", { recentShown: true }], ["the shelf", { shelfShown: true }], ["Large & old", { largeOld: true }]]) {
  check(`Ctrl+W closes the window over ${what}`, press(Qt.Key_W, view).win.visible === false);
  check(`Ctrl+L opens the path field over ${what}`, press(Qt.Key_L, view).win.editingPath === true);
}
check("Ctrl+. stops the running job over a search", press(Qt.Key_Period).did.join() === "stop", press(Qt.Key_Period).did.join());
check("Ctrl+Z takes the last change back over a search", press(Qt.Key_Z).did.join() === "undo", press(Qt.Key_Z).did.join());
check("Ctrl+B folds the rail over a search", press(Qt.Key_B).did.join() === "rail compact", press(Qt.Key_B).did.join());
check("Esc still leaves the search", press(Qt.Key_Escape).did.join() === "end search", press(Qt.Key_Escape).did.join());
done();
