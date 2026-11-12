// The wallpaper strip's thumbnails (scripts/thumbnails/thumbgen.py) with its workers started as Python 3.14 starts them
// (forkserver), through tests/lib/thumbgen_run.py with stand-ins for GnomeDesktop and the rest: every picture gets its
// thumbnail, and a run where none can be made fails, so Wallpapers.qml's magick fallback runs.
import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { check, done, tree } from "./lib/check.mjs";

console.log("== thumbnails under Python 3.14's forkserver (scripts/thumbnails/thumbgen.py)");
const helper = join(dirname(fileURLToPath(import.meta.url)), "lib", "thumbgen_run.py");
const run = mode => {
  const r = spawnSync("python3", ["-I", "-B", helper, join(tree, "scripts/thumbnails"), mode], { encoding: "utf8" });
  const line = r.stdout.trim().split("\n").pop();
  try { return JSON.parse(line); } catch { throw new Error(r.stdout + r.stderr); }
};
{
  const r = run("ok");
  check("every picture in the folder gets a thumbnail", r.made.join() === "a.png,b.png,c.png" && !r.failed, JSON.stringify(r));
}
{
  const r = run("fail");
  check("a folder where no thumbnail can be made ends in a failure", r.failed === true, JSON.stringify(r));
}
done();
