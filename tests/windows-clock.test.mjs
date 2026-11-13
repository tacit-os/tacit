// The hardware clock beside Windows (scripts/setup/windows-utc, and tacit-install's windows_clock() over a throwaway
// root): local time, as Windows keeps it, unless Windows was set to UTC (RealTimeIsUniversal in its registry), which
// Setup gave local time all the same, so that Windows showed the time off by the zone's offset
import { spawnSync } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { tree } from "./lib/check.mjs";
console.log("== the clock beside Windows (scripts/setup/windows-utc, tacit-install)");
const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "windows_utc.py"), join(tree, "scripts/setup")], { encoding: "utf8" });
process.stdout.write(r.stdout + r.stderr);
process.exit(r.status ?? 1);
