// A window hidden into the dock by the window band is in Super+Tab, faded on the desktop it was on, and a click there
// sends it back (Discord, OYINOS, 2026-11-22: hidden by the band, it was not in Super+Tab; hidden by a swipe, it was):
// services/WindowBand.qml's keepHomes and homeOf, modules/ii/overview/OverviewWidget.qml's homeId, shown and choose,
// run under node.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Super+Tab: a window hidden into the dock");
const band = read("services/WindowBand.qml");
const held = {};
const bandRoot = { held, homes: {}, norm: a => (a ?? "").replace(/^0x/, "") };
const fn = (text, name, scope) => {
  const f = qmlFunction(text, name);
  return f ? inScope(scope, f.params, f.body) : null;
};
const keepHomes = fn(band, "keepHomes", { root: bandRoot });
const win = (ws, at, size) => ({ address: "0xabc", workspace: ws, at, size, monitor: 0 });
if (keepHomes) {
  keepHomes([win({ id: 3, name: "3" }, [100, 80], [1200, 760])]);
  check("a window's desktop is kept", bandRoot.homes.abc?.workspace?.id === 3, JSON.stringify(bandRoot.homes));
  held.abc = "hidden";
  keepHomes([win({ id: -98, name: "special:tacit-hidden" }, [100, 80], [1200, 760])]);
  check("and stays while it is on the band's hidden workspace", bandRoot.homes.abc?.workspace?.id === 3, JSON.stringify(bandRoot.homes));
  keepHomes([]);
  check("a window that is gone is forgotten", !("abc" in bandRoot.homes), JSON.stringify(bandRoot.homes));
} else check("WindowBand keeps each window's desktop (keepHomes)", false);

const homeScope = (kind, stray, homes) => ({ root: { homes, heldAs: () => kind, strayHidden: () => stray, norm: bandRoot.norm, addressOf: () => "0xabc" } });
const home = { workspace: { id: 3 } };
const homeOf = (kind, stray, homes) => fn(band, "homeOf", homeScope(kind, stray, homes));
check("a hidden window has its place", homeOf("hidden", false, { abc: home })?.({})?.workspace?.id === 3);
check("so has one Hyprland shows on the hidden workspace without its event", homeOf("", true, { abc: home })?.({})?.workspace?.id === 3);
check("one hidden before the shell started has an empty place, not none", JSON.stringify(homeOf("hidden", false, {})?.({})) === "{}");
check("a window that is not hidden has none", homeOf("", false, { abc: home })?.({}) === null);
check("nor one the band is closing", homeOf("closed", false, { abc: home })?.({}) === null);

const overview = read("modules/ii/overview/OverviewWidget.qml");
const ovRoot = { effectiveActiveWorkspaceId: 1, workspaceIds: [1, 2, 3], windowByAddress: { "0xabc": { workspace: { id: -98 } } } };
const homes = new Map();
const WindowBand = { homeOf: t => homes.get(t) ?? null, reopenAll(a) { calls.push(["reopen", a]); } };
const calls = [];
const Hyprland = { dispatch(c) { calls.push(["dispatch", c]); } };
const GlobalStates = { overviewOpen: true };
const scope = { root: ovRoot, WindowBand, Hyprland, GlobalStates };
ovRoot.homeId = fn(overview, "homeId", scope);
const shown = fn(overview, "shown", scope);
const choose = fn(overview, "choose", scope);
const t = { HyprlandToplevel: { address: "abc" } };
if (ovRoot.homeId && shown && choose) {
  homes.set(t, home);
  check("Super+Tab draws it on its own desktop", ovRoot.homeId(t) === 3 && shown(t) === true);
  homes.set(t, {});
  check("one hidden before the shell started, on the desktop in front", ovRoot.homeId(t) === 1);
  homes.delete(t);
  check("a window on no desktop that is not hidden stays out", shown(t) === false);
  choose("0xabc", true);
  check("a click sends the hidden window back and closes Super+Tab", JSON.stringify(calls) === JSON.stringify([["reopen", ["0xabc"]]]) && GlobalStates.overviewOpen === false, JSON.stringify(calls));
  calls.length = 0;
  GlobalStates.overviewOpen = true;
  choose("0xdef", false);
  check("any other window is focused as before", calls.length === 1 && calls[0][0] === "dispatch" && calls[0][1].includes("address:0xdef") && GlobalStates.overviewOpen === false, JSON.stringify(calls));
} else check("the overview has homeId, shown and choose", false);
check("a hidden tile does not drag (a drag would move it out behind the band's back)", /drag\.target: window\.held \? null : parent/.test(overview));
const workspaceIds = /readonly property var workspaceIds: \{([\s\S]*?)\n    \}/.exec(overview);
check("a hidden window's desktop has its card even with nothing else on it", !!workspaceIds && workspaceIds[1].includes("root.homeId(t)"));
done();
