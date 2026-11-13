// The radio cycled after a wake (scripts/network/wifi-after-sleep.sh): out of range of every saved network the script
// still switches Wi-Fi off and on, as some adapters wake wedged, but the notch said "Wi-Fi off." for it, which the person
// did not do. The script runs under bash with a pretend nmcli, qs and sleep that write down what they were asked, in
// order; IslandController's own requestNetwork() and its `island wifiCycle` handler run under node with a pretend clock.
import { spawnSync } from "child_process";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== the notch stays quiet while Wi-Fi is cycled after a wake (wifi-after-sleep.sh, IslandController.qml)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-wifi-quiet-"));
const did = join(tmp, "did");
writeFileSync(join(tmp, "nmcli"), `#!/bin/bash
case "$*" in
  "-t -g WIFI radio") echo enabled ;;
  "-t -f DEVICE,TYPE device") printf 'wlan0:wifi\\nlo:loopback\\n' ;;
  "-t -g GENERAL.AUTOCONNECT device show wlan0") echo yes ;;
  "-t -f TYPE,AUTOCONNECT connection show") printf '802-11-wireless:yes\\n' ;;
  "-t -f TYPE,STATE device") printf 'wifi:disconnected\\n' ;;
  "radio wifi off"|"radio wifi on") echo "nmcli $*" >> "$DID" ;;
esac
`);
writeFileSync(join(tmp, "qs"), '#!/bin/bash\necho "qs $*" >> "$DID"\n');
writeFileSync(join(tmp, "sleep"), "#!/bin/sh\n");
for (const f of ["nmcli", "qs", "sleep"]) chmodSync(join(tmp, f), 0o755);
let steps = [];
try {
  spawnSync("bash", [join(tree, "scripts/network/wifi-after-sleep.sh")],
    { encoding: "utf8", env: { PATH: `${tmp}:/usr/bin:/bin`, DID: did, TACIT_SHELL: "/usr/share/tacit/shell", TACIT_WIFI_WAIT: "2" }, timeout: 20000 });
  steps = existsSync(did) ? readFileSync(did, "utf8").trim().split("\n") : [];
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
const told = steps.indexOf("qs -p /usr/share/tacit/shell ipc call island wifiCycle"), off = steps.indexOf("nmcli radio wifi off");
check("the script tells the notch before it switches Wi-Fi off, and still cycles it", told >= 0 && off > told && steps.at(-1) === "nmcli radio wifi on",
  steps.join(" | ") || "nothing");

const src = read("services/IslandController.qml");
function notch() {
  const clock = { now: 1_800_000_000_000 };
  const said = [];
  const root = { lastWifiConnected: false, wifiCycleUntil: 0, request: (name, data) => said.push(data.text) };
  const net = { ethernet: false, wifiEnabled: true, wifiStatus: "disconnected", materialSymbol: "wifi", active: null, networkName: "" };
  const scope = { root, Network: net, Date: { now: () => clock.now } };
  const fn = name => { const f = qmlFunction(src, name); return f ? inScope(scope, f.params.replace(/:\s*\w+/g, ""), f.body) : () => {}; };
  return { clock, said, net, request: fn("requestNetwork"), cycle: fn("wifiCycle") };
}
{
  const n = notch();
  n.cycle();
  n.net.wifiEnabled = false;
  n.request();                    // the radio off
  n.clock.now += 3000;
  n.net.wifiEnabled = true;
  n.request();                    // and on again, still with nothing joined
  check("the cycle's off and on say nothing", n.said.length === 0, JSON.stringify(n.said));
}
{
  const n = notch();
  n.net.wifiEnabled = false;
  n.request();
  check("Wi-Fi switched off otherwise still says \"Wi-Fi off.\"", n.said.join() === "Wi-Fi off.", JSON.stringify(n.said));
  const m = notch();
  m.cycle();
  m.clock.now += 60000;           // long after the cycle
  m.net.wifiEnabled = false;
  m.request();
  check("and so does one a minute after a cycle", m.said.join() === "Wi-Fi off.", JSON.stringify(m.said));
}
done();
