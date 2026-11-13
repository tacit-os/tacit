// What the notch says as Wi-Fi changes (services/IslandController.qml requestNetwork()), run under node over a run of
// NetworkManager states: a network still joined whose internet check fails is not a drop.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
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

// a network that wants its sign-in page (connectivity "portal", a hotel's with a password too): requestPortal() as
// NetworkManager's check goes, and the pill pressed
{
  const src = read("services/IslandController.qml");
  const portal = qmlFunction(src, "requestPortal");
  const lines = [], opened = [];
  const net = { connectivity: "full", openPublicWifiPortal: () => opened.push("sign-in page") };
  const state = { portalSaid: false, warmedUp: false, request: (name, data) => lines.push({ name, ...data }) };
  const go = c => { net.connectivity = c; const n = lines.length; if (portal) inScope({ root: state, Network: net }, portal.params, portal.body)(); return lines.length > n; };
  go("portal");
  check("before the start has settled it waits", lines.length === 0);
  state.warmedUp = true;
  const timer = src.indexOf("id: startupTimer"), fired = src.indexOf("{", src.indexOf("onTriggered:", timer));
  const startup = timer >= 0 && /root\.requestPortal\(\)/.test(src.slice(fired, matchBrace(src, fired)));
  const saidAtStart = go("portal");
  check("and the start says it once it has", startup && saidAtStart);
  const line = lines[0] ?? {};
  check("a quiet line with Open sign-in page", line.text === "Sign in to use this network" && line.pill === "Open sign-in page" && line.icon !== "error",
    JSON.stringify(line));
  line.run?.();
  check("which opens the page Settings' row opens", opened.length === 1);
  check("NetworkManager saying portal again on the same network says nothing more", !go("portal"));
  go("full");
  check("signed in, then wanting it again (the hotel's day pass ran out): said again", go("portal") && lines.length === 2);
  check("a network on the internet says nothing", !go("full") && !go("limited"));
}
done();
