// The bar's Bluetooth icon opens the control panel on its Bluetooth list (modules/ii/bar/Bluetooth.qml and
// modules/ii/sidebarRight/SidebarRightContent.qml). The icon's onClicked and the panel content's own handlers for
// GlobalStates run under node, with the content already built (kept loaded) and built by the open.
import { inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the bar's Bluetooth icon (bar/Bluetooth.qml, SidebarRightContent.qml)");
const bar = read("modules/ii/bar/Bluetooth.qml");
const content = read("modules/ii/sidebarRight/SidebarRightContent.qml");
const onClicked = readExpression(bar, bar.search(/onClicked:\s*/) + bar.match(/onClicked:\s*/)[0].length).expr;
const completedAt = content.lastIndexOf("Component.onCompleted: {") + "Component.onCompleted: ".length;
const onCompleted = content.slice(completedAt + 1, matchBrace(content, completedAt));

function panel({ keptLoaded }) {
  let built = null;
  const GlobalStates = {};
  // GlobalStates' handlers in the content, as its Connections block has them; a signal it does not listen to goes nowhere
  const hear = name => built?.handlers[name]?.();
  let section = "", open = false;
  Object.defineProperty(GlobalStates, "sidebarRightSection", { get: () => section, set: v => { if (v === section) return; section = v; hear("onSidebarRightSectionChanged"); } });
  Object.defineProperty(GlobalStates, "sidebarRightOpen", { get: () => open, set: v => {
    if (v === open) return;
    open = v;
    if (open && !built) build();           // the Loader makes the content as the panel opens
    hear("onSidebarRightOpenChanged");
  } });
  GlobalStates.requestBluetoothDialog = () => hear("onRequestBluetoothDialog");
  function build() {
    const root = { drawerOpen: false, editMode: false, loadArrangement() {} };
    const scope = { root, GlobalStates, BluetoothStatus: { available: true }, _undoBox: { hide() {} } };
    root.sectionFlags = inScope(scope, "", `return (${qmlProperty(content, "sectionFlags")});`)();
    for (const f of root.sectionFlags) root[f] = false;
    for (const name of ["only", "takeSection"]) { const f = qmlFunction(content, name); root[name] = inScope(scope, f.params, f.body); }
    const handlers = {};
    for (const name of ["onSidebarRightSectionChanged", "onSidebarRightOpenChanged", "onRequestBluetoothDialog"]) {
      const f = qmlFunction(content, name);
      if (f) handlers[name] = inScope(scope, f.params, f.body);
    }
    built = { root, handlers };
    inScope(scope, "", onCompleted)();
  }
  if (keptLoaded) build();
  const click = () => inScope({ GlobalStates, Config: { options: { bar: { tooltips: { clickToShow: false } } } }, Qt: { LeftButton: 1, RightButton: 2 } }, "", `return (${onClicked});`)()({ button: 1 });
  return { click, GlobalStates, root: () => built?.root };
}

for (const keptLoaded of [true, false]) {
  const p = panel({ keptLoaded });
  p.click();
  const how = keptLoaded ? "with the panel kept loaded" : "with the panel built by the open";
  check(`${how}, a click on the icon opens the panel`, p.GlobalStates.sidebarRightOpen, "it stays closed");
  check(`${how}, the panel opens on its Bluetooth list`, p.root()?.showBluetoothDialog === true, "the Bluetooth list stays folded");
  check(`${how}, the request is taken once`, p.GlobalStates.sidebarRightSection === "", `"${p.GlobalStates.sidebarRightSection}" is left waiting`);
  p.GlobalStates.sidebarRightOpen = false;
  check(`${how}, closing the panel folds the list again`, p.root()?.showBluetoothDialog === false, "it stays open");
}

done();
