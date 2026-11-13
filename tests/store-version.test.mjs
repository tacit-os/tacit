// The Version on an installed app's page is the one in its folder (scripts/store/stored.py info): an app got here as a
// bundle keeps its version until a start brings it up to date, while the lists may already name a newer one. stored.py's
// own info() in a home of its own with two bundles behind the lists (tests/lib/store_cases.py version).
import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { check, done, tree } from "./lib/check.mjs";

const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "store_cases.py"), tree, "version"], { encoding: "utf8" });
if (r.status !== 0) throw new Error(r.stderr);
const v = JSON.parse(r.stdout);

console.log("== an installed app's page gives the version it has (scripts/store/stored.py)");
check("Krita 5.2.1 got here, 5.2.3 in the lists: its page says 5.2.1", v.krita === "5.2.1", JSON.stringify(v.krita));
check("Discord 1:0.0.111-1 got here: 0.0.111, worded as the lists' versions are", v.discord === "0.0.111", JSON.stringify(v.discord));
check("an app installed with pacman, and one not installed, keep the lists' version", v.gimp === "3.0.4" && v.pinta === "2.1", JSON.stringify(v));
done();
