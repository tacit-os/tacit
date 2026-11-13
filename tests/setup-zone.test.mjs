// The time zone Setup hands tacit-install (scripts/setup/setupd.py, under python with the network faked): it was looked
// up once, seconds after the stick started, so a cable that connected a little later left the installed system on UTC
// with nothing said
import { spawnSync } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { tree } from "./lib/check.mjs";
console.log("== Setup's time zone (scripts/setup/setupd.py)");
const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "setupd_cases.py"), join(tree, "scripts/setup/setupd.py"), "zone"], { encoding: "utf8" });
process.stdout.write(r.stdout + r.stderr);
process.exit(r.status ?? 1);
