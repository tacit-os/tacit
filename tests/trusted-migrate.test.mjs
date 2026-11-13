// Trusted networks saved under a profile's name before 1.2.15 (Known networks' Trusted switch stored "MyWifi 1", the
// VPN's rule asks for "MyWifi"): moved to the network's name, once (services/Network.qml). Network's own
// publishProfiles(), migrateTrusted(), isTrusted() and its Persistent onReadyChanged run under node on a states.json
// read the way modules/common/Persistent.qml's adapter reads it; then the Settings app's own Trusted menus
// (tacit-settings.qml), which must keep trust under the same name, or the moved entries read untrusted there.
import { adapterDefaults, inScope, loadInto, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== trusted networks saved under a profile's name move to the network's name (Network.qml)");
const src = read("services/Network.qml");
const persistentSrc = read("modules/common/Persistent.qml");
const untyped = f => f && { params: f.params.replace(/:\s*[\w.<>]+/g, ""), body: f.body };

// a 1.2.14 states.json, as the adapter of this tree loads it; profiles: [name, ssid]
function computer(trusted, { ready = true, clean = true } = {}) {
  const states = loadInto(adapterDefaults(persistentSrc), { network: { trusted, autoVpn: "Proton" } });
  const Persistent = { ready, loadedCleanly: clean, states };
  const Vpn = { ruled: 0, applyRule() { Vpn.ruled++; } };
  const net = { listedProfiles: [], profileSsids: {}, savedConnections: [], savedProfiles: [] };
  const scope = { root: net, Persistent, Vpn };
  for (const name of ["publishProfiles", "migrateTrusted", "isTrusted"]) {
    const f = untyped(qmlFunction(src, name));
    if (f) net[name] = inScope(scope, f.params, f.body);
  }
  const onReady = untyped(qmlFunction(src, "onReadyChanged"));
  const profiles = list => {
    net.listedProfiles = list.map(([name], i) => ({ name, uuid: `u${i}`, lastUsed: 0 }));
    net.profileSsids = Object.fromEntries(list.map(([, ssid], i) => [`u${i}`, ssid]));
    net.publishProfiles();
  };
  net.setTrusted = inScope(scope, ...Object.values(untyped(qmlFunction(src, "setTrusted"))));
  return { net, Persistent, Vpn, profiles, trusted: () => Array.from(states.network.trusted),
    loaded: () => { Persistent.ready = true; Persistent.loadedCleanly = true; if (onReady) inScope(scope, onReady.params, onReady.body)(); } };
}
const show = c => JSON.stringify(c.trusted());

{
  const c = computer(["MyWifi 1"]);
  c.profiles([["MyWifi 1", "MyWifi"], ["Cafe", "Cafe"]]);
  check("home, trusted under its profile's name, is trusted by its network's name once the profiles are read",
    c.trusted().join() === "MyWifi" && c.net.isTrusted("MyWifi"), show(c));
  check("and the VPN's rule is run again at once", c.Vpn.ruled === 1, `${c.Vpn.ruled} times`);
  // later: the switch above the list trusts "Office" by its network's name; a profile named Office is another network's
  c.Persistent.states.network.trusted = ["MyWifi", "Office"];
  c.profiles([["MyWifi 1", "MyWifi"], ["Office", "Office-Guest"]]);
  check("it happens once: a later read leaves the list as the person set it", show(c) === JSON.stringify(["MyWifi", "Office"]), show(c));
}
{
  const c = computer(["Home", "Old"]);
  c.profiles([["Home", "Home-5G"], ["Home 1", "Home"]]);
  check("a profile's name that is also a saved network's own stays, beside the network the profile is for, and one no profile has is left",
    show(c) === JSON.stringify(["Home", "Home-5G", "Old"]), show(c));
}
{
  const c = computer(["MyWifi 1"]);
  c.profiles([]);                          // NetworkManager not answering yet: no profiles
  check("with no profiles read, nothing is moved and it is not marked done", show(c) === JSON.stringify(["MyWifi 1"]) && !c.Persistent.states.network.trustedBySsid, show(c));
  c.profiles([["MyWifi 1", "MyWifi"]]);
  check("and the next read moves it", c.trusted().join() === "MyWifi", show(c));
}
{
  const c = computer(["MyWifi 1"], { ready: false, clean: false });
  c.profiles([["MyWifi 1", "MyWifi"]]);    // the profiles read before states.json
  const before = show(c);
  c.loaded();
  check("profiles read before states.json: nothing until it is loaded, then moved", before === JSON.stringify(["MyWifi 1"]) && c.trusted().join() === "MyWifi",
    `${before} then ${show(c)}`);
  const d = computer(["MyWifi 1"], { clean: false });
  d.profiles([["MyWifi 1", "MyWifi"]]);
  check("a states.json that did not load cleanly is not touched", show(d) === JSON.stringify(["MyWifi 1"]), show(d));
}
{
  const c = computer([]);
  c.profiles([["MyWifi 1", "MyWifi"]]);
  check("a new computer: nothing to move, marked done, the rule left alone", c.Persistent.states.network.trustedBySsid === true && c.Vpn.ruled === 0);
}
// the Settings app: the network you are on (with the scan's access point, and before the scan has named it), the
// saved ones out of range, the ones nearby; its profile is "MyWifi 1" for the network MyWifi
{
  const app = read("tacit-settings.qml");
  const menus = [...app.matchAll(/label: "Trusted: home or work", checked: ([^\n]+),\s*run: \(\) => ([^\n]+?) \},/g)].map(m => ({ checked: m[1], run: m[2] }));
  const props = Object.fromEntries(["wifiName", "wifiSsid"].map(n => [n, qmlProperty(app, n)]));
  const rows = [];
  for (const scanned of [true, false]) {
    for (let i = 0; i < menus.length; i++) {
      const c = computer([]);
      c.profiles([["MyWifi 1", "MyWifi"]]);
      const Network = Object.assign(c.net, { ethernet: false, networkName: "MyWifi 1", active: scanned ? { ssid: "MyWifi" } : null });
      const netPage = {};
      const scope = { Network, netPage, net: { modelData: Network.savedConnections[0] }, joinLine: { ssid: "MyWifi" } };
      for (const [n, e] of Object.entries(props))
        if (e !== null) Object.defineProperty(netPage, n, { get: () => inScope(scope, "", `return (${e});`)() });
      inScope(scope, "", `${menus[i].run};`)();          // turned on in Settings
      const stored = c.trusted().join();
      const shows = inScope(scope, "", `return (${menus[i].checked});`)();
      rows.push({ i, scanned, stored, shows });
    }
  }
  const wrong = rows.filter(r => r.stored !== "MyWifi" || r.shows !== true);
  check("each of the Settings app's Trusted menus keeps trust under the network's name and reads it back so",
    menus.length === 3 && wrong.length === 0, `${menus.length} menus; ` + JSON.stringify(wrong));
}
done();
