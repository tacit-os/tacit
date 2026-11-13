// The tray menu's Pin and Unpin do what they say (modules/ii/bar/SysTrayMenu.qml, services/TrayService.qml): the menu
// entry's label and its action, and TrayService's lists of what the bar shows (pinnedItems) and what the overflow popup
// shows (unpinnedItems), run under node with the settings Config.qml starts with, and with the inversion off.
import { adapterDefaults, inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the tray menu's Pin and Unpin (SysTrayMenu.qml, TrayService.qml)");
const tray = read("services/TrayService.qml"), menu = read("modules/ii/bar/SysTrayMenu.qml");
const labelAt = menu.indexOf("text:", menu.indexOf('text: "push_pin"') + 1);
const label = readExpression(menu, labelAt + "text:".length).expr;
const actionAt = menu.lastIndexOf("releaseAction:", labelAt);
const action = readExpression(menu, actionAt + "releaseAction:".length).expr;

function service(invert) {
  const options = adapterDefaults(read("modules/common/Config.qml"));
  options.tray.invertPinnedItems = invert;
  const items = ["nm-applet", "steam", "Fcitx"].map(id => ({ id, status: 1 }));
  // the singleton's own properties are in scope by name too, as in QML
  const root = { Config: { options }, SystemTray: { items: { values: items } }, Status: { Passive: 0 } };
  root.root = root;
  const scope = root;
  for (const name of ["smartTray", "itemsInUserList", "itemsNotInUserList", "invertPins", "pinnedItems", "unpinnedItems"]) {
    const e = qmlProperty(tray, name);
    Object.defineProperty(root, name, { get: () => inScope(scope, "", `return (${e});`)() });
  }
  for (const name of ["pin", "unpin", "isPinned", "togglePin"]) {
    const f = qmlFunction(tray, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  return root;
}
const inBar = (s, id) => s.pinnedItems.some(i => i.id === id);

for (const invert of [true, false]) {
  const s = service(invert), what = invert ? "with the default settings" : "with the inversion off";
  for (const id of ["nm-applet", "Fcitx"]) {
    const scope = { TrayService: s, Translation: { tr: t => t }, root: { trayItemId: id } };
    const was = inBar(s, id) ? "in the bar" : "in the overflow popup";
    const said = inScope(scope, "", `return (${label});`)();
    inScope(scope, "", `return (${action});`)()();
    const now = inBar(s, id) ? "in the bar" : "in the overflow popup";
    const right = said === "Pin" ? now === "in the bar" : now === "in the overflow popup";
    check(`${what}, an item ${was} offers "${said}" and that is where it goes`, right && now !== was, `it went ${now}`);
  }
}
done();
