// A cable and the VPN set to come on by itself (services/Vpn.qml, services/Network.qml, Settings > Network): any wired
// network counted as trusted, so plugging into a hotel's socket took the VPN down with no way to say otherwise. A cable
// is still trusted by default, and now has the same Trusted switch as a Wi-Fi network. Network's own profile reader,
// isWiredTrusted() and setWiredTrusted(), Vpn's own applyRule(), connect(), disconnect() and start(), and the Wired row's
// bindings in Settings run under node with a pretend nmcli.
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a cable's Trusted switch and the auto VPN (Vpn.qml, Network.qml, tacit-settings.qml)");
const vsrc = read("services/Vpn.qml");
const nsrc = read("services/Network.qml");
const untyped = f => f && { params: f.params.replace(/:\s*[\w.<>]+/g, ""), body: f.body };

// the cable's profile name, as Network reads it from nmcli -t -f NAME,TYPE c show --active
const nameAt = nsrc.indexOf("onStreamFinished:", nsrc.indexOf("id: updateNetworkName"));
const nameRead = readExpression(nsrc, nameAt + "onStreamFinished:".length).expr;
const states = { network: { trusted: [], untrustedWired: [] } };
const net = { active: null, ethernet: true, networkName: "", wiredName: "", splitTerse: l => l.split(":") };
const nscope = { root: net, Persistent: { states }, Vpn: { applyRule: () => vpn.applyRule() } };
inScope(nscope, "text", nameRead.replace(/^\{|\}$/g, ""))("Proton:wireguard\nWired connection 1:802-3-ethernet\nHome:802-11-wireless\n");
check("the cable's own profile is read, past a VPN and the Wi-Fi", net.wiredName === "Wired connection 1", JSON.stringify(net.wiredName));
for (const name of ["isTrusted", "isWiredTrusted", "setWiredTrusted"]) {
  const f = untyped(qmlFunction(nsrc, name));
  if (f) net[name] = inScope(nscope, f.params, f.body);
}

const commands = [];
const vpn = { connections: [{ name: "Proton", kind: "wireguard", active: false }], busy: false, ruleSkipped: false, connecting: "", downing: false,
  pendingConnect: "", lastError: "", ruleTriedAt: 0, refresh() {} };
Object.defineProperty(vpn, "autoVpn", { get: () => "Proton" });
Object.defineProperty(vpn, "active", { get: () => vpn.connections.find(c => c.active) ?? null });
const timer = { restart() {}, stop() {}, start() {} };
const vscope = { root: vpn, Network: net, Translation: { tr: s => s }, Date: { now: () => 1000 }, waitTimer: timer, ruleLater: timer,
  refreshLater: timer, dropCheck: timer, actionProc: { exec: cmd => commands.push(cmd.join(" ")) } };
// each nmcli run ends at once here, as its Process's onExited would leave it
const settle = () => { vpn.busy = false; vpn.connecting = ""; };
for (const name of ["applyRule", "connect", "disconnect", "start"]) {
  const f = untyped(qmlFunction(vsrc, name));
  if (f) vpn[name] = inScope(vscope, f.params, f.body);
}
const upped = () => commands.some(c => /connection up .*Proton|up id Proton|up Proton/.test(c));
const downed = () => commands.some(c => /connection down/.test(c));

vpn.applyRule();
check("plugged in, a cable is trusted by default: the VPN stays down, as before", !upped() && commands.length === 0, commands.join(" | ") || "nothing ran");
if (net.setWiredTrusted) net.setWiredTrusted("Wired connection 1", false);
else vpn.applyRule();
check("marked not trusted, the cable brings the auto VPN up", upped(), commands.join(" | ") || "nothing ran");
check("and that is kept by the cable's profile", (states.network.untrustedWired ?? []).includes("Wired connection 1"), JSON.stringify(states.network));
settle();
vpn.connections[0].active = true;
commands.length = 0;
net.setWiredTrusted?.("Wired connection 1", true);
check("trusted again, the auto VPN goes down", downed(), commands.join(" | ") || "nothing ran");

// Settings > Network's Wired row: its line and its menu
console.log("== Settings > Network's Wired row (tacit-settings.qml)");
const ssrc = read("tacit-settings.qml");
const rowAt = ssrc.lastIndexOf("SettingRow {", ssrc.indexOf('label: "Wired"'));
const row = ssrc.slice(rowAt, matchBrace(ssrc, ssrc.indexOf("{", rowAt)) + 1);
const expr = key => { const m = new RegExp(`\\n\\s*${key}:\\s*`).exec(row); return m ? readExpression(row, m.index + m[0].length).expr : null; };
const sscope = { Network: net };
const line = () => inScope(sscope, "", `return (${expr("description")});`)();
const itemsAt = row.indexOf("items:");
const items = itemsAt < 0 ? [] : inScope(sscope, "", `return (${readExpression(row, itemsAt + "items:".length).expr});`)();
const trust = items.find(i => /Trusted/.test(i.label));
check("the row says the cable is trusted", line() === "Connected · Trusted", `"${line()}"`);
check("its menu has the Wi-Fi rows' \"Trusted: home or work\", checked", trust?.label === "Trusted: home or work" && trust.checked === true,
  JSON.stringify(trust ?? items));
settle();
commands.length = 0;
vpn.connections[0].active = false;
trust?.run();
check("unchecked there, the cable is not trusted and the VPN comes up", line() === "Connected" && upped(), `"${line()}", ${commands.join(" | ") || "nothing ran"}`);
done();
