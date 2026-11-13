// A second Super+M, and a second Super+Space, put away the notch's sheet they opened (services/IslandController.qml,
// modules/ii/island/IslandContent.qml, modules/ii/mediaControls/MediaControls.qml): the Super+M shortcut's onPressed
// and toNotch(), IslandController's openMedia() and its `island` calls, the notch's onOpenRequested, onCloseRequested,
// onAskRequested, openSheet() and onOpenChanged, the files' own, run under node on one screen. Super+Space runs the
// command its bind in session/hypr/tacit/keybinds.lua names.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a notch key pressed again puts its sheet away (IslandContent.qml, IslandController.qml)");
const controller = read("services/IslandController.qml");
const content = read("modules/ii/island/IslandContent.qml");
const media = read("modules/ii/mediaControls/MediaControls.qml");
const binds = read("session/hypr/tacit/keybinds.lua");

const fn = (scope, src, name, nth = 0) => {
  const f = qmlFunction(src, name, nth);
  return f ? inScope(scope, f.params.replace(/:\s*\w+/g, ""), f.body) : null;
};
const block = (src, at) => readExpression(src, at).expr.slice(1, -1);
// the `island` IpcHandler's own functions: the ones after its target line
const island = controller.slice(controller.indexOf('target: "island"'));

function notch() {
  const ic = { enabled: true, suppressed: false, keyboard: false, keyboardScreen: "", ownsMedia: true };
  const n = { open: false, view: "home", signinShown: false, signinStage: "", dragOver: false, pinnedUntilVisit: false,
    screenData: { name: "eDP-1" }, selected: -1, keyScreen: true, signinWaiting: false };
  const timers = { restart() {}, stop() {} };
  const scope = { root: n, IslandController: ic, DropShelf: { items: [] }, pinTimer: timers, signinBack: timers,
    sheetLoader: { item: null }, Persistent: { states: { record: { file: "" } } } };
  ic.snapshotRows = () => {};
  ic.keyScreenName = () => "eDP-1";
  n.openSheet = fn(scope, content, "openSheet");
  n.askUnfollow = n.addressFollow = n.forceActiveFocus = () => {};
  n.nextRow = () => 0;
  // open as a QML property: its onOpenChanged runs on a change
  const changed = inScope(scope, "", block(content, content.indexOf("onOpenChanged:") + "onOpenChanged:".length));
  let open = false;
  Object.defineProperty(n, "open", { get: () => open, set: v => { if (v !== open) { open = v; changed(); } } });
  const handlers = {};
  for (const name of ["onOpenRequested", "onCloseRequested", "onAskRequested"]) handlers[name] = fn(scope, content, name);
  ic.openRequested = key => handlers.onOpenRequested(key);
  ic.closeRequested = () => handlers.onCloseRequested();
  ic.askRequested = fresh => handlers.onAskRequested(fresh);
  const icScope = { root: ic, Hyprland: { focusedMonitor: { name: "eDP-1" } }, Config: { options: { island: { screenList: [] } } } };
  ic.openMedia = fn(icScope, controller, "openMedia");
  const ipc = {};
  for (const name of ["open", "toggle", "close"]) ipc[name] = fn(icScope, island, name);
  const mc = { islandOwnsMedia: true };
  const mcScope = { root: mc, IslandController: ic, GlobalStates: {} };
  mc.toNotch = fn(mcScope, media, "toNotch");
  const pressedAt = media.indexOf("onPressed:", media.indexOf('name: "mediaControlsToggle"'));
  const superM = inScope(mcScope, "", block(media, pressedAt + "onPressed:".length));
  // Super+Space: the IPC call its bind runs
  const call = /"SUPER \+ Space",\s*hl\.dsp\.exec_cmd\("[^"]*ipc call island (\w+)"/.exec(binds)?.[1];
  const superSpace = () => (ipc[call] ?? (() => {}))();
  const corner = () => ic.openMedia();
  return { n, ic, ipc, superM, superSpace, corner, call, ask: () => { ic.keyboard = true; ic.askRequested(false); } };
}
const state = d => `${d.n.open ? `open on ${d.n.view}` : "closed"}${d.ic.keyboard ? ", keyboard held" : ""}`;

{
  const d = notch();
  d.superM();
  const opened = d.n.open;
  d.superM();
  check("Super+M opens the sheet and Super+M again puts it away", opened && !d.n.open, state(d));
  d.superM();
  check("and a third time opens it again", d.n.open, state(d));
}
{
  const d = notch();
  check("Super+Space's bind calls `island toggle`", d.call === "toggle", `it calls island ${d.call}`);
  d.superSpace();
  const opened = d.n.open && d.ic.keyboard;
  d.superSpace();
  check("Super+Space opens the sheet with the keyboard and Super+Space again puts it away, the keyboard let go",
    opened && !d.n.open && !d.ic.keyboard, state(d));
}
{
  const d = notch();
  d.superM();
  d.corner();
  check("the media corner over the sheet Super+M opened leaves it open", d.n.open, state(d));
  d.superM();
  check("and Super+M still puts it away", !d.n.open, state(d));
  const e = notch();
  e.corner();
  e.corner();
  check("the media corner only opens, twice over too", e.n.open, state(e));
  const f = notch();
  f.ipc.open();
  f.ipc.open();
  check("a script's `island open` only opens, twice over too", f.n.open, state(f));
}
{
  const d = notch();
  d.superSpace();
  d.superM();
  check("Super+M over the sheet Super+Space opened keeps it", d.n.open, state(d));
  d.superM();
  check("and the second Super+M puts it away", !d.n.open, state(d));
}
{
  const d = notch();
  d.superM();
  d.ipc.close();               // Esc, a click away
  d.superM();
  check("a sheet put away another way: the next Super+M opens it", d.n.open, state(d));
}
{
  const d = notch();
  d.superSpace();
  d.ask();                     // Super+Shift+Space turns the sheet into Ask
  d.superSpace();
  check("Super+Space over Ask leaves Ask open (its own key puts it away)", d.n.open && d.n.view === "ask", state(d));
}
done();
