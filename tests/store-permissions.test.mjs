// Apps' sandbox (scripts/store/bundle.py run): the app's permissions as this release's catalogue gives them
// (assets/store/permissions.json), for an app got before they changed. VS Code got on 2026-10-20 has "user-folders" in
// its manifest; the catalogue gives it "home" since 1e48602. And the camera for the apps Apps offers for calls.
import { spawnSync } from "child_process";
import { rmSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== an app's permissions after they change (scripts/store/bundle.py)");
const helper = join(dirname(fileURLToPath(import.meta.url)), "lib", "bundle_run.py");
function start(app, perms, nodes) {
  const r = spawnSync("python3", ["-I", helper, join(tree, "scripts/store/bundle.py"), app, JSON.stringify(perms),
    ...(nodes ? [JSON.stringify(nodes)] : [])], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(r.stderr);
  const out = JSON.parse(r.stdout);
  rmSync(out.home, { recursive: true, force: true });
  const binds = []; for (let i = 0; i < out.argv.length - 2; i++) if (out.argv[i] === "--bind") binds.push([out.argv[i + 1], out.argv[i + 2]]);
  const devs = []; for (let i = 0; i < out.argv.length - 1; i++) if (out.argv[i] === "--dev-bind") devs.push(out.argv[i + 1]);
  return { home: out.home, binds, devs, argv: out.argv };
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
{
  // Apps offers Signal and Telegram for calls ("Talk to people"): a video call needs the webcam, a computer with one has
  // /dev/video0 and /dev/media0. Got with the defaults, as every app but OBS was
  const cam = ["/dev/video0", "/dev/media0"], defaults = { network: true, files: "user-folders", devices: ["gpu", "audio"], x11: true, talk: [] };
  for (const app of ["signal-desktop", "telegram-desktop"]) {
    const s = start(app, defaults, cam);
    check(`${app} sees the camera`, cam.every(d => s.devs.includes(d)), `--dev-bind ${JSON.stringify(s.devs)}`);
  }
  check("an app with no call in it does not", start("gimp", defaults, cam).devs.length === 0);
}
done();
