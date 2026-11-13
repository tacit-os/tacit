// The lock screen's status glyph (session/hypr/hyprlock/glyph.sh): it took the night light as on whenever hyprsunset's
// temperature was not 6500 K, but the shell turns the tint off with "identity", and hyprsunset 0.4 keeps the last
// temperature through it, so a night light turned off at 5800 K still showed its moon on the lock. The script runs under
// bash with pretend fc-list, pidof and hyprctl on PATH answering as hyprsunset 0.4's IPC does, and a pretend battery
// folder in place of /sys/class/power_supply.
import { spawnSync } from "child_process";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, read } from "./lib/check.mjs";

console.log("== the lock screen's night-light glyph (glyph.sh)");
const dir = mkdtempSync(join(tmpdir(), "tacit-glyph-"));
try {
  const bin = join(dir, "bin"), ps = join(dir, "power_supply"), bat = join(ps, "BAT0");
  mkdirSync(bin);
  mkdirSync(bat, { recursive: true });
  writeFileSync(join(bat, "type"), "Battery\n");
  writeFileSync(join(bat, "scope"), "System\n");
  const script = join(dir, "glyph.sh");
  writeFileSync(script, read("session/hypr/hyprlock/glyph.sh").replaceAll("/sys/class/power_supply", ps));
  writeFileSync(join(bin, "fc-list"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(bin, "pidof"), '#!/bin/sh\n[ -n "$SUNSET" ]\n');
  // hyprctl hyprsunset as 0.4.0 answers: temperature keeps the last one, identity get says whether the tint is off
  writeFileSync(join(bin, "hyprctl"), `#!/bin/bash
[ -n "$SUNSET" ] || { echo "Couldn't connect to hyprsunset"; exit 1; }
case "$2 $3" in
  "temperature ") echo "$KELVIN" ;;
  "identity get") echo "$IDENTITY" ;;
  *) echo "unknown request" ;;
esac
`);
  for (const f of ["fc-list", "pidof", "hyprctl"]) chmodSync(join(bin, f), 0o755);
  const glyph = (status, env) => {
    writeFileSync(join(bat, "status"), `${status}\n`);
    return spawnSync("bash", [script], { env: { PATH: `${bin}:/usr/bin:/bin`, ...env }, encoding: "utf8" }).stdout.trim();
  };
  const cases = [
    ["a night light on at 5800 K shows the moon", "Discharging", { SUNSET: 1, KELVIN: 5800, IDENTITY: "false" }, "bedtime"],
    ["one turned off after 5800 K shows nothing", "Discharging", { SUNSET: 1, KELVIN: 5800, IDENTITY: "true" }, ""],
    ["one on at a Warmth of 6500 K shows the moon", "Discharging", { SUNSET: 1, KELVIN: 6500, IDENTITY: "false" }, "bedtime"],
    ["with no hyprsunset running, nothing", "Discharging", {}, ""],
    ["charging still comes first", "Charging", { SUNSET: 1, KELVIN: 5800, IDENTITY: "false" }, "bolt"],
  ];
  for (const [name, status, env, want] of cases) {
    const got = glyph(status, env);
    check(name, got === want, `glyph.sh said ${JSON.stringify(got)}`);
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}
done();
