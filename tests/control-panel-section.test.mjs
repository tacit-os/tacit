// Ctrl+Super+V, "Shell: Sound (control panel)": the panel's openSound() (modules/ii/sidebarRight/SidebarRight.qml) and
// its content's own handlers (SidebarRightContent.qml) run under node. The panel must open on its sound section, both
// when the content is built by that open and when it was kept built.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the control panel opened on its sound section");
const panel = read("modules/ii/sidebarRight/SidebarRight.qml"), content = read("modules/ii/sidebarRight/SidebarRightContent.qml");
const flags = ["showWifiDialog", "showVpn", "showBluetoothDialog", "showAudioOutputDialog", "showAudioInputDialog", "showNightLightDialog"];

function build(GlobalStates) {
  const root = Object.fromEntries(flags.map(f => [f, false]));
  Object.assign(root, { sectionFlags: flags, loadArrangement() {} });
  const scope = { root, GlobalStates };
  for (const name of ["takeSection", "onSidebarRightSectionChanged"]) {
    const f = qmlFunction(content, name);
    if (f) root[name] = inScope(scope, f.params, f.body);
  }
  // the content's own Component.onCompleted (the last one, at its top level)
  const at = content.lastIndexOf("\n    Component.onCompleted: {");
  const open = content.indexOf("{", at);
  inScope(scope, "", content.slice(open + 1, matchBrace(content, open)))();
  return root;
}
// GlobalStates, telling a built content when the section changes as the Connections would
function states() {
  let section = "", content = null;
  return {
    sidebarRightOpen: false,
    get sidebarRightSection() { return section; },
    set sidebarRightSection(v) { section = v; content?.onSidebarRightSectionChanged?.(); },
    attach(c) { content = c; },
  };
}
const f = qmlFunction(panel, "openSound");
{
  const GlobalStates = states();
  inScope({ GlobalStates }, f.params, f.body)();
  const c = build(GlobalStates);   // the open builds the content
  check("built by the open, the panel shows its sound section", GlobalStates.sidebarRightOpen && c.showAudioOutputDialog === true);
  check("and the request is used up", GlobalStates.sidebarRightSection === "");
}
{
  const GlobalStates = states();
  const c = build(GlobalStates);   // kept built ("Keep the control panel loaded")
  GlobalStates.attach(c);
  inScope({ GlobalStates }, f.params, f.body)();
  check("kept built, the panel shows its sound section", GlobalStates.sidebarRightOpen && c.showAudioOutputDialog === true);
}
done();
