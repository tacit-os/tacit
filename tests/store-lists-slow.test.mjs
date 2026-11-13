// Apps' own package lists on a slow line (scripts/store/bundle.py refresh_sync): with none kept yet, Arch's extra list
// (9 MB) over a line of 1 Mbit/s comes whole, where a try that stops moving, or a mirror that never answers, still ends in
// a minute as "offline". bundle.py's own refresh_sync in a home of its own, with curl replaced by one that keeps to curl's
// limits on a clock of its own (tests/lib/store_cases.py lists-*), so nothing waits or is downloaded.
import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { check, done, tree } from "./lib/check.mjs";

const line = c => {
  const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "store_cases.py"), tree, c], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(r.stderr);
  return JSON.parse(r.stdout);
};

console.log("== Apps' package lists on a slow line (scripts/store/bundle.py)");
const slow = line("lists-slow");
check("1 Mbit/s: the 9 MB list comes in its 72 s, and the install goes on", slow.said === "ok", JSON.stringify(slow));
const stalled = line("lists-stalled");
check("a line that has all but stopped (500 bytes a second) is given up on in a minute: offline",
  stalled.said === "offline" && stalled.tries.every(([s]) => s <= 60), JSON.stringify(stalled));
const dead = line("lists-dead");
check("a mirror that never answers is given up on in a minute: offline", dead.said === "offline" && dead.tries.every(([s]) => s <= 60),
  JSON.stringify(dead));
done();
