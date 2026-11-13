// Files dropped on the desktop of a monitor with no notch (Settings > Notch lists only the other): DropShelf.show()
// (modules/common/widgets/DropShelf.qml), the notches Island.qml makes for the screen list, and each notch's
// onDropShelfOpenChanged (modules/ii/island/IslandContent.qml), all the files' own code under node, with
// GlobalStates.dropShelfOpen telling its listeners only when it changes, as a QML property does. The flag is a pulse a
// notch clears; left set, the next drops are no change and the shelf never opens again.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a drop on a monitor without a notch (DropShelf.qml, IslandContent.qml)");
const island = read("modules/ii/island/Island.qml");
const model = readExpression(island, island.indexOf("model:") + "model:".length).expr;
const show = qmlFunction(read("modules/common/widgets/DropShelf.qml"), "show");
const handler = qmlFunction(read("modules/ii/island/IslandContent.qml"), "onDropShelfOpenChanged");

function desk(screenNames, screenList) {
  const screens = screenNames.map(name => ({ name }));
  const Config = { options: { island: { screenList } } };
  const listeners = [];
  const GlobalStates = { flag: false, dropShelfScreen: null, dropShelfX: 0, dropShelfY: 0 };
  Object.defineProperty(GlobalStates, "dropShelfOpen", {
    get() { return this.flag; },
    set(v) { v = Boolean(v); if (v === this.flag) return; this.flag = v; for (const l of [...listeners]) l(); },
  });
  const names = Array.from(inScope({ Quickshell: { screens }, Config }, "", model.slice(1, -1))()).map(s => s.name);
  const notches = names.map(name => {
    const root = { screenData: { name }, open: false, view: "home", signinShown: false, signinStage: "", sheetHeld: false, pinnedUntilVisit: false };
    const scope = { root, GlobalStates, Config, IslandController: { snapshotRows() {} }, pinTimer: { restart() {} } };
    listeners.push(inScope(scope, handler.params, handler.body));
    return root;
  });
  const shelf = inScope({ root: { addItems() {} }, GlobalStates }, show.params, show.body);
  const drop = name => shelf(["file:///home/a/report.pdf"], 10, 10, screens.find(s => s.name === name));
  const opened = () => notches.filter(n => n.open).map(n => n.screenData.name);
  const fold = () => notches.forEach(n => { n.open = false; });
  return { drop, opened, fold, GlobalStates, names };
}

{
  const d = desk(["eDP-1", "HDMI-A-1"], ["eDP-1"]);
  check("Settings > Notch on the laptop only: one notch", d.names.join() === "eDP-1", d.names.join());
  d.drop("HDMI-A-1");
  check("a drop on the monitor without one opens nothing", d.opened().length === 0, d.opened().join());
  check("and the flag is cleared", d.GlobalStates.dropShelfOpen === false);
  d.drop("eDP-1");
  check("the next drop, on the laptop, opens its shelf", d.opened().join() === "eDP-1", d.opened().join() || "nothing opened");
  d.fold();
  d.drop("HDMI-A-1");
  d.drop("HDMI-A-1");
  d.drop("eDP-1");
  check("and so does one after more drops on the other monitor", d.opened().join() === "eDP-1", d.opened().join() || "nothing opened");
}
{
  const d = desk(["eDP-1", "HDMI-A-1"], []);
  d.drop("HDMI-A-1");
  check("with a notch on every screen, a drop opens the shelf on its own screen's notch only", d.opened().join() === "HDMI-A-1",
    d.opened().join() || "nothing opened");
  d.fold();
  d.drop("eDP-1");
  check("and the next on the other one there", d.opened().join() === "eDP-1", d.opened().join() || "nothing opened");
}
done();
