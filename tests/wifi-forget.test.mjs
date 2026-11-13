// Settings > Network, "Forget this network" on the Wi-Fi network you are on (tacit-settings.qml), for a network whose
// profile NetworkManager did not name like it ("Home 1" for the network Home): the menu's own run and
// services/Network.qml's forgetWifiNetwork() run under node, with the nmcli script it would run written down. The device
// goes down first, or NetworkManager hops to another saved network, and every profile for the network goes.
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Forget the Wi-Fi network you are on (tacit-settings.qml, Network.qml)");
const app = read("tacit-settings.qml");
const f = qmlFunction(read("services/Network.qml"), "forgetWifiNetwork");
const forget = { params: f.params.replace(/:\s*[\w.<>]+/g, ""), body: f.body };
const menu = app.match(/\{ label: "Forget this network", run: \(\) => (Network\.forgetWifiNetwork\(netPage\.[^\n]*?\)) \}/)?.[1];

function forgetOnIt() {
  const ran = [];
  const Network = {
    ethernet: false, networkName: "Home 1", active: { ssid: "Home" }, wifiDevice: "wlan0",
    savedConnections: [{ name: "Home 1", ssid: "Home" }, { name: "Home", ssid: "Home" }, { name: "Cafe", ssid: "Cafe" }],
    run: (cmd, done, env) => ran.push({ script: cmd[2], env }), update() {},
  };
  Network.forgetWifiNetwork = inScope({ root: Network, Translation: { tr: s => s }, getNetworks: {} }, forget.params, forget.body);
  const netPage = {};
  const scope = { Network, netPage };
  for (const n of ["wifiName", "wifiSsid"])
    Object.defineProperty(netPage, n, { get: () => inScope(scope, "", `return (${qmlProperty(app, n)});`)() });
  inScope(scope, "", `${menu};`)();
  return { down: /nmcli device disconnect "\$DEV"/.test(ran[0]?.script ?? ""), names: (ran[0]?.env.NAMES ?? "").split("\n") };
}

check("the row's Forget menu is there", !!menu);
{
  const r = forgetOnIt();
  check("Forget on the network you are on takes the Wi-Fi down first", r.down, "the profiles are deleted with the link up");
  check("and forgets every profile saved for Home, not only the one named Home 1", r.names.sort().join() === "Home,Home 1", r.names.join(", "));
}
done();
