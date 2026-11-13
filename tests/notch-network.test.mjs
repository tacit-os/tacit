// What the notch says as Wi-Fi changes (services/IslandController.qml requestNetwork()), run under node over a run of
// NetworkManager states: a network still joined whose internet check fails is not a drop.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the notch's Wi-Fi lines (IslandController.qml)");
const f = qmlFunction(read("services/IslandController.qml"), "requestNetwork");
const said = [];
const Network = { ethernet: false, wifiEnabled: true, wifiStatus: "disconnected", active: null, networkName: "", materialSymbol: "wifi_find" };
const root = { lastWifiConnected: false, request: (name, data) => said.push(data.text) };
const requestNetwork = inScope({ root, Network }, f.params, f.body);
// one change of NetworkManager's state, as onWifiStatusChanged hands it over: what the notch said for it, if anything
function becomes(wifiStatus) {
  Network.wifiStatus = wifiStatus;
  Network.active = wifiStatus === "connected" || wifiStatus === "limited" ? { ssid: "Hotel" } : null;
  const before = said.length;
  requestNetwork();
  return said.length > before ? said[said.length - 1] : null;
}

check("joining says the network's name", becomes("connected") === "Hotel");
const limited = becomes("limited");
check("still joined with the internet check failing, it says there is no internet, not that Wi-Fi dropped",
  limited !== null && !/dropped/i.test(limited) && /no internet/i.test(limited), JSON.stringify(limited));
check("the check passing again says the name again", becomes("connected") === "Hotel");
becomes("limited");
check("and leaving the network from there is a drop", becomes("disconnected") === "Wi-Fi dropped.");
done();
