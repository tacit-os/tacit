// Settings > Network's VPN rows hold what the control panel's VPN rows do (modules/ii/sidebarRight/vpn/VpnSection.qml):
// "On when not trusted" and Forget, behind the row's ⋯, besides its switch. The row's own bindings and the menu's runs
// (tacit-settings.qml's VPN Repeater) go under node with a stand-in Vpn service; what they ask of Vpn is compared.
import { inScope, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the VPN rows in Settings > Network (tacit-settings.qml)");
const src = read("tacit-settings.qml");
const group = objectWith(src, 'title: "VPN"');
const rowAt = group.indexOf("required property var modelData");
const row = objectWith(group, "required property var modelData");
const expr = (block, name) => {
  const at = new RegExp(`(^|\\n)\\s*${name}:`).exec(block);
  return at ? readExpression(block, at.index + at[0].length).expr : null;
};
check("the VPN group has a row for each VPN", rowAt >= 0);

const asked = [];
const Vpn = { autoVpn: "", busy: false, toggle: n => asked.push(["toggle", n]), setAuto: n => asked.push(["setAuto", n]),
  forget: n => asked.push(["forget", n]) };
const conn = { name: "Office", kind: "wireguard", active: false };
const vpnRow = { modelData: conn, enabled: true };
const value = e => inScope({ Vpn, vpnRow, modelData: conn }, "", `return (${e});`)();
vpnRow.auto = expr(row, "readonly property bool auto") !== null ? value(expr(row, "readonly property bool auto")) : false;

const itemsExpr = expr(row, "items");
check("the row has a menu", itemsExpr !== null);
if (itemsExpr) {
  const items = () => value(itemsExpr);
  const auto = items().find(i => i.label === "On when not trusted"), forget = items().find(i => i.label === "Forget");
  check('its menu offers "On when not trusted", not ticked while another VPN or none is set so', !!auto && auto.checked === false,
    JSON.stringify(items().map(i => i.label)));
  check("and Forget", !!forget);
  if (auto) { auto.run(); check("On when not trusted sets this VPN to come on by itself", JSON.stringify(asked.pop()) === '["setAuto","Office"]'); }
  if (forget) { forget.run(); check("Forget forgets this VPN", JSON.stringify(asked.pop()) === '["forget","Office"]'); }
  Vpn.autoVpn = "Office";
  vpnRow.auto = value(expr(row, "readonly property bool auto"));
  check("once it is the one set, the menu ticks it", items().find(i => i.label === "On when not trusted")?.checked === true);
  const description = value(expr(row, "description"));
  check("and the row says so under its name", description.includes("On when not trusted"), description);
}
// the switch is still there: the row, and its toggle, turn the VPN on or off
const activated = expr(row, "onActivated");
if (activated) { value(activated); check("a click on the row turns the VPN on or off", JSON.stringify(asked.pop()) === '["toggle","Office"]'); }
// (a SwitchRow's own, or a Toggle beside the menu)
const toggle = row.includes("Toggle {") ? objectWith(row, "focusPolicy: Qt.NoFocus") : null;
check("the row keeps its switch, on while the VPN is", /^SwitchRow\s*\{[\s\S]*checked:\s*modelData\.active/.test(row)
  || (toggle !== null && /checked:\s*vpnRow\.modelData\.active/.test(toggle)), toggle ?? row.split("\n")[0]);
done();
