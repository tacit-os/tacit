// Settings > Network > Known networks (modules/ii/settings/pages/NetworkConfig.qml): a saved profile's "connected" and
// its Trusted switch, for a profile NetworkManager did not name like its network. The row's bindings and its switch,
// Network.qml's isTrusted() and setTrusted(), and the VPN's rule (Vpn.qml's applyRule()) run under node.
import { inScope, matchBrace, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== known networks by their SSID (NetworkConfig.qml)");
const page = read("modules/ii/settings/pages/NetworkConfig.qml");
const network = read("services/Network.qml");
const vpn = read("services/Vpn.qml");
const untyped = f => ({ params: f.params.replace(/:\s*[\w.<>]+/g, ""), body: f.body });

// the Known networks row (netRow), from its id to its end
const rowAt = page.indexOf("id: netRow");
const row = page.slice(rowAt, matchBrace(page, page.lastIndexOf("{", rowAt)));
const switchAt = row.indexOf("onClicked: {", row.indexOf("checked: netRow.trusted"));
const switchClick = row.slice(row.indexOf("{", switchAt) + 1, matchBrace(row, row.indexOf("{", switchAt)));
const thisConnection = qmlProperty(page, "trusted");   // the switch beside the network in use, above the list

function settings({ profile, ssid, on }) {
  const persistent = { states: { network: { trusted: [], autoVpn: "Proton" } } };
  const Network = { active: on ? { ssid: on } : null, ethernet: false };
  for (const name of ["isTrusted", "setTrusted"]) {
    const f = untyped(qmlFunction(network, name));
    Network[name] = inScope({ root: Network, Persistent: persistent }, f.params, f.body);
  }
  const netRow = { modelData: { name: profile, ssid, lastUsed: 1 } };
  const rowScope = { netRow, modelData: netRow.modelData, Network };
  for (const name of ["current", "trusted"]) {
    const e = qmlProperty(row, name);
    Object.defineProperty(netRow, name, { get: () => inScope(rowScope, "", `return (${e});`)() });
  }
  const toggle = inScope({ ...rowScope, checked: false, Qt: { binding: f => f } }, "", switchClick);
  // the VPN's rule on this network: what it would do
  const v = { autoVpn: "Proton", busy: false, active: null, did: "nothing", connect() { v.did = "up"; }, disconnect() { v.did = "down"; } };
  const rule = qmlFunction(vpn, "applyRule");
  const applyRule = inScope({ root: v, Network }, rule.params, rule.body);
  const upper = () => inScope({ Network, ipSection: { ap: Network.active } }, "", `return (${thisConnection});`)();
  return { netRow, toggle, persistent, vpnDoes: () => { v.did = "nothing"; applyRule(); return v.did; }, upper };
}

{
  const s = settings({ profile: "MyWifi 1", ssid: "MyWifi", on: "MyWifi" });
  check(`the profile "MyWifi 1" for the network in use, MyWifi, reads connected`, s.netRow.current, "it does not");
  s.toggle();
  check(`its Trusted switch, turned on, trusts the network MyWifi`, s.persistent.states.network.trusted.includes("MyWifi"),
    `it stored ${JSON.stringify(s.persistent.states.network.trusted)}`);
  check("the switch then reads on", s.netRow.trusted, "it reads off");
  check("the switch beside the network in use reads trusted too", s.upper(), "it reads untrusted");
  check(`the "on when not trusted" VPN stays down on MyWifi`, s.vpnDoes() === "nothing", `the VPN rule brings it ${s.vpnDoes()}`);
}
{
  const s = settings({ profile: "MyWifi", ssid: "MyWifi", on: "Cafe" });
  check("a known network that is not the one in use does not read connected", !s.netRow.current, "it reads connected");
  check(`the VPN comes up on an untrusted Cafe`, s.vpnDoes() === "up", `it does ${s.vpnDoes()}`);
}

done();
