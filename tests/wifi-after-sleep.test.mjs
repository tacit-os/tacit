// Wi-Fi after a wake (scripts/network/wifi-after-sleep.sh, hypridle's after_sleep_cmd): the radio is cycled once when
// Wi-Fi does not come back by itself, and never for an adapter the person disconnected on purpose, whose
// NetworkManager autoconnect is off until they join again. The script runs under bash with a pretend nmcli that
// answers as NetworkManager 1.58 does under LC_ALL=C and writes down what it was asked to do, and a sleep that does not wait.
import { spawnSync } from "child_process";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== Wi-Fi after a wake is cycled only when it can help (scripts/network/wifi-after-sleep.sh)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-wifi-wake-"));
const did = join(tmp, "did");
writeFileSync(join(tmp, "nmcli"), `#!/bin/bash
case "$*" in
  "-t -g WIFI radio") echo enabled ;;
  "-t -f TYPE device") printf 'wifi\\nloopback\\nwifi-p2p\\n' ;;
  "-t -f DEVICE,TYPE device") printf 'wlan0:wifi\\nlo:loopback\\n/net/connman/iwd/0:wifi-p2p\\n' ;;
  "-t -g GENERAL.AUTOCONNECT device show wlan0") echo "$AUTO" ;;
  "-t -f TYPE,AUTOCONNECT connection show") printf '802-11-wireless:yes\\nloopback:no\\n' ;;
  "-t -f TYPE,STATE device") printf 'wifi:%s\\nloopback:connected (externally)\\n' "$STATE" ;;
  "radio wifi off"|"radio wifi on") echo "$*" >> "$DID" ;;
esac
`);
writeFileSync(join(tmp, "sleep"), "#!/bin/sh\n");
for (const f of ["nmcli", "sleep"]) chmodSync(join(tmp, f), 0o755);

try {
  const wake = (auto, state) => {
    rmSync(did, { force: true });
    const r = spawnSync("bash", [join(tree, "scripts/network/wifi-after-sleep.sh")],
      { encoding: "utf8", env: { PATH: `${tmp}:${process.env.PATH}`, AUTO: auto, STATE: state, DID: did, TACIT_WIFI_WAIT: "3" }, timeout: 20000 });
    return { rc: r.status, did: existsSync(did) ? readFileSync(did, "utf8").trim().split("\n").join(", ") : "nothing" };
  };
  let r = wake("yes", "disconnected");
  check("an adapter that wakes and does not join is cycled once", r.rc === 0 && r.did === "radio wifi off, radio wifi on", `${r.did} (exit ${r.rc})`);
  r = wake("no", "disconnected");
  check("one the person disconnected before the sleep is left as it is", r.rc === 0 && r.did === "nothing", `${r.did} (exit ${r.rc})`);
  r = wake("yes", "connected");
  check("one that joined by itself is left as it is", r.rc === 0 && r.did === "nothing", `${r.did} (exit ${r.rc})`);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
