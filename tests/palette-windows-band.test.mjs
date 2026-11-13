// The palette's Windows rows for windows the window band holds (services/PaletteWindows.qml windows and fuzzyQuery(),
// run under node), as the dock has them: one about to be closed is not offered, a hidden one comes back through the
// band and is not labelled with the band's special workspace.
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("services/PaletteWindows.qml");

console.log("== the palette's Windows rows and the window band (services/PaletteWindows.qml)");
{
  const did = [];
  const tr = s => Object.assign(new String(s), { arg: v => s.replace("%1", v) });
  const root = { sectionTitle: "Windows", moveHereLabel: "Move here" };
  const scope = { root, GlobalStates: { overviewOpen: true, searchOpen: false }, AppSearch: { guessIcon: () => "" },
    WM: { windowList: [
      { address: "0xa1", title: "notes.md", appId: "graphis", workspaceId: 1, focused: false },
      { address: "0xb2", title: "Praxis", appId: "praxis", workspaceId: -98, focused: false },
      { address: "0xc3", title: "Old tab", appId: "thyris", workspaceId: -97, focused: false },
      { address: "0xd4", title: "foot", appId: "foot", workspaceId: 2, focused: true }],
      workspaceById: { 1: { name: "1" }, 2: { name: "2" } }, focusWindow: a => did.push(`focus ${a}`), activeWorkspace: { id: 1 } },
    WindowBand: { held: { b2: "hidden", c3: "closed" }, norm: a => (a ?? "").replace(/^0x/, ""),
      reopenAll: a => did.push(`reopen ${a.join(" ")}`), reopenWhenHidden: a => did.push(`reopen when hidden ${a}`) },
    Config: { options: {} }, Translation: { tr }, resultComp: { createObject: (p, props) => props } };
  Object.defineProperty(root, "windows", { get: () => inScope(scope, "", qmlProperty(src, "windows").slice(1, -1))() });
  for (const name of ["matches", "focusWindow", "moveWindowHere", "fuzzyQuery"]) {
    const f = qmlFunction(src, name);
    root[name] = inScope(scope, f.params.replace(/:\s*\w+/g, ""), f.body);
  }
  const rows = root.fuzzyQuery("");
  const named = rows.map(r => `${r.name} (${r.comment})`);
  check("a window about to be closed is not offered", !rows.some(r => r.name === "Old tab"), JSON.stringify(named));
  const hidden = rows.find(r => r.name === "Praxis");
  check("a hidden window is listed with no workspace of the band's", hidden && !/-9\d/.test(String(hidden.comment)), JSON.stringify(named));
  hidden?.execute();
  check("picking it brings it back through the band, not by focusing its address", JSON.stringify(did) === JSON.stringify(["reopen 0xb2"]), JSON.stringify(did));
  check("and it has no Move here", hidden && hidden.actions.length === 0);
  did.length = 0;
  rows.find(r => r.name === "notes.md").execute();
  check("a window on a workspace leads the list, labelled with it, and is focused",
    JSON.stringify(did) === JSON.stringify(["focus 0xa1"]) && rows[0].name === "notes.md" && rows[0].comment === "workspace 1", JSON.stringify(named));
}
done();
