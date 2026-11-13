// The control panel's arrangement of its pills (modules/ii/sidebarRight/SidebarRightContent.qml): the file's own
// arrangement functions (load, save, demote, promote, the keyboard's moves, the undo line) run under node, with its
// sidebar-arrangement.json kept as the JsonAdapter would write and read it back.
import { adapterDefaults, inScope, loadInto, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the control panel's arrangement (SidebarRightContent.qml)");
const src = read("modules/ii/sidebarRight/SidebarRightContent.qml");
const adapterSrc = objectWith(src, "id: arrangementAdapter");
const fns = ["loadArrangement", "saveArrangement", "demote", "promoteAt", "keyboardMove", "pushUndo", "focusNext", "rowIds", "unplacedIds",
  "rowFillerIds", "drawerIds", "catalogEntry", "endDrag"];

// a panel on a file (the JSON on disk, or null for none): its root, and what it did
function panel(file) {
  const disk = { text: file === null ? null : JSON.stringify(file) };
  const said = [];
  const root = { _undoSnapshot: null, pendingFocus: "" };
  const arrangementAdapter = loadInto(adapterDefaults(adapterSrc), disk.text === null ? {} : JSON.parse(disk.text));
  const arrangementFile = { writeAdapter: () => { disk.text = JSON.stringify(arrangementAdapter); } };
  const scope = { root, arrangementAdapter, arrangementFile, _undoBox: { show: l => said.push(l), hide() {} } };
  for (const name of ["defaultPrimary", "defaultSecondary", "toggleCatalog"])
    root[name] = inScope(scope, "", `return (${qmlProperty(src, name)});`)();
  for (const name of fns) {
    const f = qmlFunction(src, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  // a drop with no zone under it (the drawer's area), for endDrag
  Object.assign(root, { zoneAt: () => "", mapToItem: () => ({ x: 0, y: 0 }), secondaryIndex: () => -1, primaryIndex: () => 0 });
  root.loadArrangement();
  // the file read back, as its FileView does on a change or the next start
  root.reload = () => panel(JSON.parse(disk.text));
  return { root, said, disk };
}
const same = (a, b) => JSON.stringify(Array.from(a)) === JSON.stringify(Array.from(b));

// [8] every top pill sent to More, or the row emptied
{
  const p = panel(null);
  const first = Array.from(p.root.primary);
  for (const id of first) p.root.demote(id);
  const again = p.root.reload();
  check("after all four top pills go to More, the next load keeps the top empty", again.root.primary.length === 0,
    `the top has ${Array.from(again.root.primary).join(", ")} again`);
  check("and the row as it was", same(again.root.secondary, p.root.secondary), Array.from(again.root.secondary).join(", "));
}
{
  const p = panel(null);
  for (const id of Array.from(p.root.secondary)) p.root.demote(id);
  const again = p.root.reload();
  check("after the row's three pills go to More, the next load keeps them there", again.root.secondary.length === 0,
    `the row has ${Array.from(again.root.secondary).join(", ")} again`);
}
{
  const p = panel(null);
  check("a first start, with no file, has the default pills",
    same(p.root.primary, p.root.defaultPrimary) && same(p.root.secondary, p.root.defaultSecondary), `${Array.from(p.root.primary)} / ${Array.from(p.root.secondary)}`);
  const old = panel({ primary: ["wifi", "vpn"], secondary: [] });
  check("a file from before with an empty row still gets the default row", same(old.root.secondary, old.root.defaultSecondary),
    Array.from(old.root.secondary).join(", "));
}

// [9] a pill the row filled in by itself, moved to More by the keyboard or dropped on the drawer's area
{
  const p = panel(null);
  const filler = p.root.rowFillerIds()[0];
  const wrote = p.disk.text;
  p.root.keyboardMove(filler, "Screenshot", "secondary", "down");
  check("Down on a pill the row filled in says nothing moved to More", p.said.length === 0, `it said "${p.said.join('", "')}"`);
  check("and writes nothing, the pill still in the row", p.disk.text === wrote && p.root.rowIds().includes(filler), p.disk.text);
  Object.assign(p.root, { dragTarget: filler, dragName: "Screenshot" });
  p.root.endDrag({ x: 0, y: 0 });
  check("nor does a drop of it on the drawer's area", p.said.length === 0, `it said "${p.said.join('", "')}"`);
}
{
  const p = panel(null);
  const placed = p.root.secondary[0];
  p.root.keyboardMove(placed, "Mic", "secondary", "down");
  check("Down on a pill placed in the row still moves it to More, with its undo line",
    !p.root.secondary.includes(placed) && p.said[0] === "Moved Mic to More", `${Array.from(p.root.secondary)}; ${p.said.join(", ")}`);
  const top = p.root.primary[0];
  Object.assign(p.root, { dragTarget: top, dragName: "Wi-Fi" });
  p.root.endDrag({ x: 0, y: 0 });
  check("and a top pill dropped on the drawer's area goes to More", !p.root.primary.includes(top) && p.said[1] === "Moved Wi-Fi",
    `${Array.from(p.root.primary)}; ${p.said.join(", ")}`);
}
done();
