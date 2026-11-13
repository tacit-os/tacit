// A pinned program that can no longer be started (removed in Apps): what a click on its pill in the dock does
// (modules/ii/overview/PaletteDock.qml). The dock's own activate(), launch(), openMenu(), reset() and menuAct() run
// under node, with the menu's words from SearchWidget.qml.
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a pin whose program is gone (PaletteDock.qml)");
const src = read("modules/ii/overview/PaletteDock.qml");
const search = read("modules/ii/overview/SearchWidget.qml");
const Translation = { tr: s => s };

// installed: the menu entries Quickshell has read (none yet, at the start of a session)
function dock({ installed, entriesRead = true }) {
  const pins = ["praxis", "krita"];
  const app = id => ({ appId: id, pinned: pins.includes(id), toplevels: [] });
  const timer = () => ({ stop() {}, restart() {} });
  const root = {
    launching: "", focusIndex: -1, menuEntry: null, peekEntry: null, peekCandidate: null, started: [], unpinned: [],
    programs: pins.map(app), entryCount: entriesRead ? installed.length : 0, draggingId: "", dragOffset: 0,
    entryFor: id => (entriesRead && installed.includes(id) ? { id: `${id}.desktop` } : null),
  };
  root.opened = Object.assign(() => root.opened.count++, { count: 0 });
  const scope = {
    root, Translation, launchTimer: timer(), peekTimer: timer(), followTimer: timer(), unpeekTimer: timer(), land: timer(),
    WindowBand: { heldAs: () => "" }, PaletteFrecency: { record() {} }, AppScope: { launch: e => root.started.push(e.id) },
    TaskbarApps: { togglePin: id => root.unpinned.push(id) }, Qt: { callLater: f => f() },
  };
  for (const name of ["activate", "launch", "openMenu", "reset", "cancelDrag", "menuAct", "togglePinFocused", "keepFocusOn"]) {
    const f = qmlFunction(src, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  // the menu's words for a program (SearchWidget's menuTab)
  const words = () => {
    const menuTab = { entry: root.menuEntry, appOpen: (root.menuEntry?.toplevels.length ?? 0) > 0 };
    return inScope({ menuTab, Translation }, "", qmlProperty(search, "actions").slice(1, -1))();
  };
  const click = id => { root.menuEntry = null; root.activate(root.programs.find(a => a.appId === id)); };
  return { root, words, click };
}

{
  const d = dock({ installed: ["praxis"] });
  d.click("krita");
  const words = d.words();
  check("a click on a pin whose program is gone opens its menu", d.root.menuEntry?.appId === "krita",
    d.root.opened.count ? "the dock closed with nothing opened" : "nothing happened");
  check("the menu offers Remove from dock", words.length === 1 && words[0].word === "Remove from dock", JSON.stringify(words));
  check("the dock stays open with the menu", d.root.opened.count === 0, "it closed");
  d.root.menuAct(words[0]?.act);
  check("Remove from dock takes it off the dock", d.root.unpinned.includes("krita"), "nothing was unpinned");
}
{
  const d = dock({ installed: ["praxis"] });
  d.click("praxis");
  check("a click on an installed program starts it and puts the dock away", d.root.started.includes("praxis.desktop") && d.root.opened.count === 1 && d.root.menuEntry === null,
    `started ${d.root.started.join(", ") || "nothing"}, menu ${d.root.menuEntry?.appId ?? "none"}`);
}
{
  const d = dock({ installed: ["praxis"], entriesRead: false });
  d.click("praxis");
  check("before the menu entries are read, a click offers no Remove from dock", d.root.menuEntry === null, "it offered to remove praxis");
}
{
  const d = dock({ installed: ["praxis"] });
  d.root.focusIndex = 1;               // Super, then Right to Krita, then Enter
  d.root.activate(d.root.programs[1]);
  check("from the keys, the menu opens and the keys stay on the pill", d.root.menuEntry?.appId === "krita" && d.root.focusIndex === 1,
    `menu ${d.root.menuEntry?.appId ?? "none"}, keys on ${d.root.focusIndex}`);
  d.root.togglePinFocused();           // Ctrl+P
  check("then Ctrl+P takes it off the dock", d.root.unpinned.includes("krita"), `it unpinned ${d.root.unpinned.join(", ") || "nothing"}`);
}

done();
