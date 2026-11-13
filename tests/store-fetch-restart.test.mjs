// An app's package fetched again after a first try stopped part way (scripts/store/bundle.py fetch), from Tacit's one
// mirror: one that cannot resume gets the file again from its start in the same try, rather than ending it as "offline";
// one that can still goes on from what came. bundle.py's own fetch() in a home of its own, with curl replaced by a mirror
// that has the package, and gpgv by one that accepts it (tests/lib/store_cases.py fetch-*).
import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { check, done, tree } from "./lib/check.mjs";

const fetched = c => {
  const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "store_cases.py"), tree, c], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(r.stderr);
  return JSON.parse(r.stdout);
};
const pkg = "blender-4.5-1-x86_64.pkg.tar.zst";

console.log("== a package fetched again from a mirror that cannot resume (scripts/store/bundle.py)");
const no = fetched("fetch-no-resume");
check("the mirror cannot resume: the package comes whole from its start, checked, in the same try", no.said === "ok", JSON.stringify(no));
check("asked once to go on, then once from the start, then its signature",
  JSON.stringify(no.calls) === JSON.stringify([[true, pkg], [false, pkg], [false, pkg + ".sig"]]), JSON.stringify(no.calls));
const yes = fetched("fetch-resume");
check("a mirror that can resume still goes on from what came", yes.said === "ok" && JSON.stringify(yes.calls) === JSON.stringify([[true, pkg], [false, pkg + ".sig"]]),
  JSON.stringify(yes));
done();
