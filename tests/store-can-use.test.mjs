// What an app can reach, in Apps: Discord and Element get the camera and the microphone in the sandbox as Signal and
// Telegram do (assets/store/permissions.json, read by scripts/store/bundle.py run through tests/lib/bundle_run.py), and an
// app's page says what its sandbox reaches of the whole home folder, the network, the camera and the microphone:
// stored.py info()'s "can" (tests/lib/store_cases.py can), held against the sandbox bundle.py starts the app in, and
// store.qml's line for it, its own bindings under node.
import { spawnSync } from "child_process";
import { rmSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { inScope, matchBrace, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== what an app can reach, in the sandbox and on the app's page (bundle.py, stored.py, store.qml)");
const lib = join(dirname(fileURLToPath(import.meta.url)), "lib");
const py = (...args) => {
  const r = spawnSync("python3", ["-I", ...args], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(r.stderr);
  return JSON.parse(r.stdout.trim().split("\n").pop());
};
const defaults = { network: true, files: "user-folders", devices: ["gpu", "audio"], x11: true, talk: [] }, cam = ["/dev/video0", "/dev/media0"];
const sandbox = (app, nodes = []) => {
  const out = py(join(lib, "bundle_run.py"), join(tree, "scripts/store/bundle.py"), app, JSON.stringify(defaults), JSON.stringify(nodes));
  rmSync(out.home, { recursive: true, force: true });
  return { ...out, home: out.argv.some((a, i) => a === "--bind" && out.argv[i + 1] === out.home && out.argv[i + 2] === out.home) };
};
for (const app of ["discord", "element-desktop"]) {
  const out = sandbox(app, cam);
  const devs = out.argv.filter((a, i) => out.argv[i - 1] === "--dev-bind");
  const sound = out.argv.some(a => /pipewire-0$/.test(a));
  check(`${app} got with the defaults sees the camera, and the sound server its microphone goes through`, cam.every(d => devs.includes(d)) && sound,
    `--dev-bind ${JSON.stringify(devs)}, pipewire ${sound}`);
}

const can = py(join(lib, "store_cases.py"), tree, "can");
const is = (app, words) => JSON.stringify(can[app]) === JSON.stringify(words);
for (const app of ["signal-desktop", "telegram-desktop", "discord", "element-desktop", "obs-studio"])
  check(`${app}'s page is told it can use the network, the camera and the microphone`, is(app, ["the network", "camera", "microphone"]), JSON.stringify(can[app]));
for (const app of ["code", "libreoffice-fresh", "libreoffice-still"])
  check(`${app}'s page is told it can use your home folder and the network`, is(app, ["your home folder", "the network"]), JSON.stringify(can[app]));
check("an app with the defaults is told the network", is("gimp", ["the network"]), JSON.stringify(can.gimp));
check("an app with none of them is told nothing", is("gnome-mines", []), JSON.stringify(can["gnome-mines"]));
// the words claim only what the sandbox gives: the home folder bound whole, the network shared
for (const app of ["code", "gimp", "gnome-mines"]) {
  const s = sandbox(app), net = s.argv.includes("--share-net"), said = can[app] ?? [];
  check(`${app}'s words are its sandbox's (whole home ${s.home}, network ${net})`, said.includes("your home folder") === s.home && said.includes("the network") === net,
    JSON.stringify(said));
}

const store = read("store.qml");
const at = store.indexOf("Can use: ");
const smallAt = store.lastIndexOf("Small {", at);
const small = at < 0 ? "" : store.slice(smallAt, matchBrace(store, smallAt + "Small ".length) + 1);
const expr = key => { const m = new RegExp(`\\b${key}\\s*:\\s*`).exec(small); return m ? readExpression(small, m.index + m[0].length).expr : "false"; };
const shown = a => { const s = { appPage: { a } }; return inScope(s, "", `return (${expr("visible")});`)() ? inScope(s, "", `return (${expr("text")});`)() : ""; };
check("VS Code's page says \"Can use: your home folder, the network\"", shown({ can: can.code }) === "Can use: your home folder, the network", JSON.stringify(shown({ can: can.code })));
check("Discord's \"Can use: the network, camera, microphone\"", shown({ can: can.discord }) === "Can use: the network, camera, microphone", JSON.stringify(shown({ can: can.discord })));
check("and nothing for an app with none of them, or while the page loads", shown({ can: can["gnome-mines"] }) === "" && shown(null) === "");
done();
