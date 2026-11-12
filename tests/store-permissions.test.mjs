// Apps' sandbox (scripts/store/bundle.py run): the app's permissions as this release's catalogue gives them
// (assets/store/permissions.json), for an app got before they changed. VS Code got on 2026-10-20 has "user-folders" in
// its manifest; the catalogue gives it "home" since 1e48602.
import { spawnSync } from "child_process";
import { rmSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== an app's permissions after they change (scripts/store/bundle.py)");
const helper = join(dirname(fileURLToPath(import.meta.url)), "lib", "bundle_run.py");
function start(app, perms) {
  const r = spawnSync("python3", ["-I", helper, join(tree, "scripts/store/bundle.py"), app, JSON.stringify(perms)], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(r.stderr);
  const out = JSON.parse(r.stdout);
  rmSync(out.home, { recursive: true, force: true });
  const binds = []; for (let i = 0; i < out.argv.length - 2; i++) if (out.argv[i] === "--bind") binds.push([out.argv[i + 1], out.argv[i + 2]]);
  return { home: out.home, binds, argv: out.argv };
}
const catalogue = JSON.parse(read("assets/store/permissions.json"));
check("the catalogue gives VS Code the whole home", catalogue.apps.code?.files === "home");
{
  const s = start("code", { network: true, files: "user-folders", devices: ["gpu", "audio"], x11: true, talk: [] });
  check("VS Code got before that sees the whole home", s.binds.some(([a, b]) => a === s.home && b === s.home),
    `binds ${JSON.stringify(s.binds.map(([a]) => a.replace(s.home, "~")))}`);
}
{
  // gnome-mines has no network and no files in the catalogue; an old manifest that had them must not keep them
  const s = start("gnome-mines", { network: true, files: "home", devices: ["gpu", "audio"], x11: true, talk: [] });
  check("an app the catalogue narrows is narrowed too", !s.argv.includes("--share-net") && !s.binds.some(([a]) => a === s.home));
}
done();
