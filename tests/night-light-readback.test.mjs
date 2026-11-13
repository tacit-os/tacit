// The night light's read-back (services/Hyprsunset.qml's fetchProc, which the control panel's switch runs 400 ms after
// a click): the Process's own command runs with a pretend hyprctl and pidof first on PATH, answering as hyprsunset
// 0.4.0's IPC does ("temperature" gives the last temperature set, which "identity" keeps; "identity get" gives true or
// false), and its stdout handler runs under node on what it printed.
import { spawnSync } from "child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the night light's read-back (Hyprsunset.qml)");
const src = read("services/Hyprsunset.qml");
const proc = objectWith(src, "id: fetchProc");
const command = inScope({}, "", `return (${readExpression(proc, proc.indexOf("command:") + 8).expr});`)();
const at = proc.indexOf("onStreamFinished:"), open = proc.indexOf("{", at);
const handler = proc.slice(open + 1, matchBrace(proc, open));

const bin = mkdtempSync(join(tmpdir(), "tacit-hyprsunset-"));
writeFileSync(join(bin, "hyprctl"), `#!/bin/bash
[ "$1" = hyprsunset ] || exit 1
shift
case "$*" in
temperature) printf '%s' "$HS_KELVIN" ;;
"identity get") printf '%s' "$HS_IDENTITY" ;;
*) printf ok ;;
esac
`);
writeFileSync(join(bin, "pidof"), `#!/bin/bash\n[ -n "$HS_RUNNING" ]\n`);
for (const f of ["hyprctl", "pidof"]) chmodSync(join(bin, f), 0o755);

// what the switch says after the read-back, with hyprsunset in this state (null: not running) and the switch as it was
function readBack(state, was) {
  const env = { PATH: `${bin}:${process.env.PATH}`, HS_RUNNING: state ? "1" : "", HS_KELVIN: String(state?.kelvin ?? ""), HS_IDENTITY: String(state?.identity ?? "") };
  const out = spawnSync(command[0], command.slice(1), { encoding: "utf8", env }).stdout;
  const root = { temperatureActive: was };
  const quiet = { error() {} };
  inScope({ root, stateCollector: { text: out }, console: quiet }, "", handler)();
  return root.temperatureActive;
}
try {
  check("Warmth at 6200 K switched on reads as on", readBack({ kelvin: 6200, identity: false }, true) === true, "it reads as off");
  check("switched off after a tint at 5800 K reads as off", readBack({ kelvin: 5800, identity: true }, false) === false, "it reads as on");
  check("on at 4500 K reads as on", readBack({ kelvin: 4500, identity: false }, true) === true, "it reads as off");
  check("with no hyprsunset running it reads as off", readBack(null, true) === false, "it reads as on");
} finally {
  rmSync(bin, { recursive: true, force: true });
}
done();
