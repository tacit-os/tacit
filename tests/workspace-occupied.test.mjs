// The bar's workspace indicator on two monitors (modules/common/models/WorkspaceModel.qml): its own activeWindowHere,
// currentWorkspaceNotFake and fakeWorkspace bindings under node, for monitor B while the focused window is on monitor A.
// The bar (modules/ii/bar/Workspaces.qml) draws the active workspace as occupied only when it is not fakeWorkspace.
import { inScope, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the active workspace's occupied cue on a second monitor (WorkspaceModel.qml)");
const src = read("modules/common/models/WorkspaceModel.qml");
const body = name => { const e = qmlProperty(src, name); return e.startsWith("{") ? e.slice(1, -1) : `return (${e});`; };

// monitor B's model with B's active workspace number, the windows Hyprland lists, and the one focused window
function model(activeNumber, windows, focused) {
  const s = {
    WM: { compositor: "hyprland" }, activeNumber,
    activeWindow: focused ? { activated: true, HyprlandToplevel: { address: focused.address.slice(2) } } : null,
    HyprlandData: {
      windowList: windows,
      clientForToplevel: t => (t ? windows.find(w => w.address === `0x${t.HyprlandToplevel.address}`) ?? null : null),
    },
  };
  for (const name of ["activeWindowHere", "currentWorkspaceNotFake", "fakeWorkspace"]) {
    const get = inScope(s, "", body(name));
    Object.defineProperty(s, name, { get });
  }
  return s;
}
const occupiedShown = (m, ws) => ws !== m.fakeWorkspace;   // Workspaces.qml: occupied[index] && wsId != fakeWorkspace

const onA = { address: "0xa1", workspace: { id: 1 } }, onB1 = { address: "0xb1", workspace: { id: 3 } }, onB2 = { address: "0xb2", workspace: { id: 3 } };
{
  const m = model(3, [onA, onB1, onB2], onA);
  check("B's workspace 3 with two windows, the focus on A: shown as occupied", occupiedShown(m, 3), `fakeWorkspace ${m.fakeWorkspace}`);
}
{
  const m = model(4, [onA, onB1, onB2], onA);
  check("B's empty workspace 4, the focus on A: shown as empty", !occupiedShown(m, 4), `fakeWorkspace ${m.fakeWorkspace}`);
}
{
  const m = model(3, [onA, onB1, onB2], onB1);
  check("B's workspace 3 with the focus on one of its windows: occupied", occupiedShown(m, 3), `fakeWorkspace ${m.fakeWorkspace}`);
}
{
  const fresh = { address: "0xb9", workspace: { id: 5 } };
  const m = model(5, [onA], fresh);
  check("a window just opened on B's workspace 5, not listed yet: occupied", occupiedShown(m, 5), `fakeWorkspace ${m.fakeWorkspace}`);
}

done();
