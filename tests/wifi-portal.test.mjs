// The control panel's "Open network portal" button (modules/ii/sidebarRight/wifiNetworks/WifiSection.qml): its row's
// portal binding run under node. It follows NetworkManager's connectivity, as Settings does, not whether the network
// has a password. And what the button opens (Network.openPublicWifiPortal()): a page the sign-in page can stand in for.
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the Wi-Fi row's sign-in button (WifiSection.qml)");
const expr = qmlProperty(read("modules/ii/sidebarRight/wifiNetworks/WifiSection.qml"), "portal");
const portal = (security, connectivity, current = true) =>
  inScope({ row: { current, network: { security } }, Network: { connectivity } }, "", `return (${expr});`)() === true;

check("a hotel network with a password and a sign-in page shows the button", portal("WPA2", "portal"));
check("an open network with a sign-in page shows it", portal("", "portal"));
check("an open network already on the internet does not", !portal("", "full"));
check("a network you are not on does not", !portal("", "portal", false));

// a portal answers in place of a plain http page only: an https one meets its certificate or a closed port
{
  const f = qmlFunction(read("services/Network.qml"), "openPublicWifiPortal");
  const opened = [];
  inScope({ Quickshell: { execDetached: argv => opened.push(argv) } }, f.params, f.body)();
  const url = opened[0]?.[1] ?? "";
  check("the button opens a plain http page, which the network's sign-in page can take the place of",
    opened.length === 1 && opened[0][0] === "xdg-open" && /^http:\/\/[^/]+/.test(url), JSON.stringify(opened));
}
done();
