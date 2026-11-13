// Setup's "Plug in the charger" line (the disk page) goes by setupd.py's power(), run here under python on made-up
// /sys/class/power_supply trees. Every battery counted as the computer's, so a desktop with a wireless mouse, keyboard or
// controller was told to plug in a charger it does not have; a laptop on a USB-C charger was told the same.
import { spawnSync } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { check, done, tree } from "./lib/check.mjs";

console.log("== Setup's charger line (scripts/setup/setupd.py)");
const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "setupd_cases.py"),
  join(tree, "scripts/setup/setupd.py"), "power"], { encoding: "utf8" });
process.stdout.write(r.stdout + r.stderr);
check("setupd says on the charger for a desktop with a device's battery and a laptop on USB-C", r.status === 0);
done();
