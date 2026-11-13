// Setup's Wi-Fi page on an 802.1X network (a university's, an office's): setupd.py's list under python, its nmcli
// faked, and setup.qml's own pickNetwork(), forward() and pwFieldShown for it. Setup asks no user name, so it offered a
// password box that could never join, and every try said "Could not connect to X. Try again, or connect later."
import { spawnSync } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== Setup's Wi-Fi on an 802.1X network (scripts/setup/setupd.py, setup.qml)");
const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "setupd_cases.py"),
  join(tree, "scripts/setup/setupd.py"), "enterprise"], { encoding: "utf8" });
process.stdout.write(r.stdout + r.stderr);
check("setupd tells an 802.1X network from one a password joins", r.status === 0);

const src = read("setup.qml");
const pick = qmlFunction(src, "pickNetwork"), forward = qmlFunction(src, "forward"), shown = qmlProperty(src, "pwFieldShown");
// a block binding ({ ...; return ... }) runs as a function's body
const shownBody = shown.startsWith("{") ? shown.slice(1, -1) : `return (${shown});`;
const wifi = [{ ssid: "eduroam", secure: true, inUse: false, enterprise: true, signal: 70 },
  { ssid: "Home", secure: true, inUse: false, enterprise: false, signal: 80 }];
function choose(ssid) {
  const sent = [], pages = [];
  const setup = { network: "", otherNet: false, joining: false, joined: "", joinError: "", go: p => pages.push(p) };
  const scope = { shownPage: "wifi", setup, backend: { wifi, send: m => sent.push(m) }, root: { pwFieldRef: { text: "" } } };
  inScope(scope, pick.params, pick.body)(wifi.find(n => n.ssid === ssid));
  const box = inScope(scope, "", shownBody)();
  const said = setup.joinError;
  inScope(scope, forward.params, forward.body)();
  return { box, said, sent, pages };
}
const uni = choose("eduroam");
check("eduroam chosen: no password box", uni.box === false, `password box ${uni.box}`);
check("and the page says why it can't be joined here, and where it can",
  /user name/.test(uni.said) && /Settings/.test(uni.said), `"${uni.said}"`);
check("Continue moves on without a join that can't work", uni.sent.length === 0 && JSON.stringify(uni.pages) === '["where"]',
  `sent ${JSON.stringify(uni.sent)}, went to ${JSON.stringify(uni.pages)}`);
const home = choose("Home");
check("a WPA2 network still gets the password box and is joined", home.box === true && home.said === ""
  && home.sent.length === 1 && home.sent[0].op === "join" && home.pages.length === 0,
  `password box ${home.box}, "${home.said}", sent ${JSON.stringify(home.sent)}`);
done();
