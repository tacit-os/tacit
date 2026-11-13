// Getting an app as a bundle: what the window is told while it downloads (scripts/store/stored.py bundle_install, over
// bundle.py's own install() with the download and unpacking replaced: tests/lib/store_cases.py). One big package must
// move the bar while it comes, and the words say how much is in.
import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { check, done, tree } from "./lib/check.mjs";

const helper = join(dirname(fileURLToPath(import.meta.url)), "lib", "store_cases.py");
const r = spawnSync("python3", ["-I", helper, tree, "progress"], { encoding: "utf8" });
if (r.status !== 0) throw new Error(r.stderr);
const said = JSON.parse(r.stdout);

console.log("== Blender's download, as the window hears it (scripts/store)");
// Blender: 3 MB coming over about 2.4 s, and 1 MB that is in at once
const downloading = said.filter(x => x.progress > 0.05 && x.progress < 0.8);
check("the bar moves while Blender's big package comes, not only when a package is done",
  new Set(downloading.map(x => x.progress)).size >= 2, JSON.stringify(said));
check("the words say how much is in: Downloading N of 4 MB", downloading.length > 0 && downloading.every(x => /^Downloading [1-3] of 4 MB$/.test(x.phase)),
  JSON.stringify(downloading.map(x => x.phase)));
check("and the bar never goes back", said.every((x, i) => i === 0 || x.progress >= said[i - 1].progress));
done();
