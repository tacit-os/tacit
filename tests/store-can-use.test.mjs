// The camera and the microphone in Apps: Discord and Element get them in the sandbox as Signal and Telegram do
// (assets/store/permissions.json, read by scripts/store/bundle.py run through tests/lib/bundle_run.py), and an app's page
// says so: stored.py info()'s "can" (tests/lib/store_cases.py can), and store.qml's line for it, its own bindings under node.
import { spawnSync } from "child_process";
import { rmSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { inScope, matchBrace, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== the camera and the microphone, in the sandbox and on the app's page (bundle.py, stored.py, store.qml)");
const lib = join(dirname(fileURLToPath(import.meta.url)), "lib");
const py = (...args) => {
  const r = spawnSync("python3", ["-I", ...args], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(r.stderr);
  return JSON.parse(r.stdout.trim().split("\n").pop());
};
const defaults = { network: true, files: "user-folders", devices: ["gpu", "audio"], x11: true, talk: [] }, cam = ["/dev/video0", "/dev/media0"];
for (const app of ["discord", "element-desktop"]) {
  const out = py(join(lib, "bundle_run.py"), join(tree, "scripts/store/bundle.py"), app, JSON.stringify(defaults), JSON.stringify(cam));
  rmSync(out.home, { recursive: true, force: true });
  const devs = out.argv.filter((a, i) => out.argv[i - 1] === "--dev-bind");
  const sound = out.argv.some(a => /pipewire-0$/.test(a));
  check(`${app} got with the defaults sees the camera, and the sound server its microphone goes through`, cam.every(d => devs.includes(d)) && sound,
    `--dev-bind ${JSON.stringify(devs)}, pipewire ${sound}`);
}

const can = py(join(lib, "store_cases.py"), tree, "can");
for (const app of ["signal-desktop", "telegram-desktop", "discord", "element-desktop", "obs-studio"])
  check(`${app}'s page is told it can use the camera and the microphone`, JSON.stringify(can[app]) === JSON.stringify(["camera", "microphone"]), JSON.stringify(can[app]));
check("an app with neither is told nothing", Array.isArray(can.gimp) && can.gimp.length === 0, JSON.stringify(can.gimp));

const store = read("store.qml");
const at = store.indexOf("Can use: ");
const smallAt = store.lastIndexOf("Small {", at);
const small = at < 0 ? "" : store.slice(smallAt, matchBrace(store, smallAt + "Small ".length) + 1);
const expr = key => { const m = new RegExp(`\\b${key}\\s*:\\s*`).exec(small); return m ? readExpression(small, m.index + m[0].length).expr : "false"; };
const shown = a => { const s = { appPage: { a } }; return inScope(s, "", `return (${expr("visible")});`)() ? inScope(s, "", `return (${expr("text")});`)() : ""; };
check("the page says it: \"Can use: camera, microphone\"", shown({ can: ["camera", "microphone"] }) === "Can use: camera, microphone", JSON.stringify(shown({ can: ["camera", "microphone"] })));
check("and nothing for an app with neither, or while the page loads", shown({ can: [] }) === "" && shown(null) === "");
done();
