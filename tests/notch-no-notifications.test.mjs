// Notifications are the pop-ups' and the centre's, never the notch's (the owner, 2026-11-13). A file that saved
// island.states.notification on before 1.2.15 stood the pop-ups down and sent each notification to the notch, which
// showed the sender and the app and nothing of the message. Config's own defaults take that file as its JsonAdapter
// does (the keys it declares, nothing else); NotificationPopup.qml's and ScreenCorners.qml's bindings and every
// onNotify in IslandController.qml run under node with it.
import { adapterDefaults, inScope, loadInto, matchBrace, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a saved \"notifications in the notch\" (NotificationPopup.qml, ScreenCorners.qml, IslandController.qml)");
const options = loadInto(adapterDefaults(read("modules/common/Config.qml")), { island: { enable: true, states: { notification: true } } });
const Config = { options };
const popup = { notificationId: 1, summary: "Ana", body: "are you coming tonight?", appName: "WhatsApp", hasInlineReply: true, popup: true };
const Notifications = { popupList: [popup], list: [popup], popupInhibited: false };
const GlobalStates = { notificationCenterOpen: false };
const WlrKeyboardFocus = { None: "none", OnDemand: "on demand", Exclusive: "exclusive" };
const value = (src, name, scope) => inScope(scope, "", `return (${readExpression(src, src.indexOf(`${name}:`, src.indexOf(`property bool ${name}`)) + name.length + 1).expr});`)();

// the panel: its window, its rows, and the keys for a reply
{
  const src = read("modules/ii/notificationPopup/NotificationPopup.qml");
  const outer = { };
  const scope = { Config, Notifications, GlobalStates, notificationPopup: outer };
  const owns = qmlProperty(src, "islandOwnsPopups");   // release-1.2.15's gate
  if (owns) outer.islandOwnsPopups = inScope(scope, "", `return (${owns});`)();
  outer.showing = value(src, "showing", scope);
  check("with a pop-up waiting, the panel's window is made", outer.showing === true, `showing ${outer.showing}`);
  const winAt = src.indexOf("PanelWindow {");
  const win = src.slice(winAt, matchBrace(src, src.indexOf("{", winAt)) + 1);
  const root = { centerOpen: false, replying: false };
  const wscope = { Config, Notifications, GlobalStates, notificationPopup: outer, root, WlrKeyboardFocus };
  if (win.includes("property bool islandOwnsPopups")) root.islandOwnsPopups = value(win, "islandOwnsPopups", wscope);
  root.hasPopups = value(win, "hasPopups", wscope);
  const listAt = win.indexOf("NotificationPopupList {");
  const list = win.slice(listAt, matchBrace(win, win.indexOf("{", listAt)) + 1);
  const shown = inScope(wscope, "", `return (${readExpression(list, list.indexOf("visible:") + "visible:".length).expr});`)();
  check("and its pop-up rows show", root.hasPopups === true && shown === true, `hasPopups ${root.hasPopups}, rows visible ${shown}`);
  const keys = inScope(wscope, "", `return (${readExpression(win, win.indexOf("WlrLayershell.keyboardFocus:") + "WlrLayershell.keyboardFocus:".length).expr});`)();
  check("a pop-up with a reply field can take the keys when clicked", keys === "on demand", keys);
}

// the corner's edge that opens the centre steps aside while the panel shows there
{
  const src = read("modules/ii/screenCorners/ScreenCorners.qml");
  const at = src.indexOf("readonly property bool panelShowing:");
  const showing = inScope({ Config, Notifications, GlobalStates }, "", `return (${readExpression(src, at + "readonly property bool panelShowing:".length).expr});`)();
  check("the corner's door knows the panel is showing", showing === true, `panelShowing ${showing}`);
}

// a WhatsApp message reaching the shell asks nothing of the notch
{
  const src = read("services/IslandController.qml");
  const asked = [];
  const root = { enabled: true, request: name => asked.push(name), phoneCode: null };
  let at = -1, handlers = 0;
  while ((at = src.indexOf("function onNotify(", at + 1)) >= 0) {
    const conn = src.lastIndexOf("Connections {", at);
    const block = src.slice(conn, matchBrace(src, src.indexOf("{", conn)) + 1);
    const scope = { root, Config, Notifications, phoneCodeExpiry: { restart() {} } };
    const enabled = /\n\s*enabled:/.test(block) ? inScope(scope, "", `return (${readExpression(block, block.indexOf("enabled:") + "enabled:".length).expr});`)() : true;
    if (!enabled) continue;
    handlers++;
    const open = src.indexOf("{", src.indexOf(")", at));
    inScope(scope, "notification", src.slice(open + 1, matchBrace(src, open)))(popup);
  }
  check("the shell's notifications go to no notch state", asked.length === 0, `${handlers} handlers listening asked for ${JSON.stringify(asked)}`);
}
done();
