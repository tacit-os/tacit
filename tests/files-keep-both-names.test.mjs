// "Keep both" names the second one before its extension, however long (modules/ii/files/SaveWindow.qml's keepName,
// scripts/files/job.sh's keep_name): Save As's own keepName runs under node, and a paste with Keep both runs job.sh
// under bash in a home of its own, on .markdown, .desktop, .tar.gz and .jpg files and a dotted folder name.
import { execFileSync } from "child_process";
import { mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== Keep both keeps the extension at the end (SaveWindow.qml, job.sh)");
const keepName = qmlFunction(read("modules/ii/files/SaveWindow.qml"), "keepName");
const here = ["notes.markdown", "movie.torrent", "app.desktop", "x.tar.gz", "photo.jpg", "Hyprland-0.56.2"];
const win = { names: Object.fromEntries(here.map(n => [n, true])), dirs: { "Hyprland-0.56.2": true } };
const saved = n => inScope({ win }, keepName.params, keepName.body)(n);
for (const [n, want] of [["notes.markdown", "notes 2.markdown"], ["movie.torrent", "movie 2.torrent"], ["app.desktop", "app 2.desktop"],
  ["x.tar.gz", "x 2.tar.gz"], ["photo.jpg", "photo 2.jpg"]])
  check(`Save As, Keep both: ${n} is saved as ${want}`, saved(n) === want, `saved as ${saved(n)}`);

const home = mkdtempSync(join(tmpdir(), "tacit-keep-"));
try {
  const src = join(home, "stick"), dest = join(home, "Documents");
  for (const d of [src, dest]) {
    mkdirSync(join(d, "Hyprland-0.56.2"), { recursive: true });
    for (const n of here.slice(0, 5)) writeFileSync(join(d, n), d);
  }
  const env = { PATH: process.env.PATH, HOME: home, XDG_STATE_HOME: join(home, ".local/state"), XDG_DATA_HOME: join(home, ".local/share") };
  execFileSync("bash", [join(tree, "scripts/files/job.sh"), "keep1", "copy", "keep", dest, ...here.map(n => join(src, n))], { env, encoding: "utf8" });
  const got = readdirSync(dest).sort();
  for (const want of ["notes 2.markdown", "movie 2.torrent", "app 2.desktop", "x 2.tar.gz", "photo 2.jpg", "Hyprland-0.56.2 2"])
    check(`a paste with Keep both makes ${want}`, got.includes(want), JSON.stringify(got.filter(n => !here.includes(n))));
} finally {
  rmSync(home, { recursive: true, force: true });
}
done();
