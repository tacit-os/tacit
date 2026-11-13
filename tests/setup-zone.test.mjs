// The time zone Setup hands tacit-install (scripts/setup/setupd.py, under python with the network faked): it was looked
// up once, seconds after the stick started, so a cable that connected a little later left the installed system on UTC
// with nothing said. Where none is found at all (never online), the Ready page says so: setup.qml's own receive() and
// zoneNote run under node on setupd's answers.
import { spawnSync } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { tree, check, done, read } from "./lib/check.mjs";
import { inScope, qmlFunction } from "./lib/qml.mjs";
console.log("== Setup's time zone (scripts/setup/setupd.py)");
const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "setupd_cases.py"), join(tree, "scripts/setup/setupd.py"), "zone"], { encoding: "utf8" });
process.stdout.write(r.stdout + r.stderr);
check("setupd's cases", r.status === 0);

console.log("== the Ready page on the zone setupd found (setup.qml)");
const src = read("setup.qml");
const receive = qmlFunction(src, "receive");
const note = src.match(/readonly property string zoneNote:\s*([^\n]*)/)?.[1];
const ready = src.slice(src.indexOf('root.shownPage === "ready" ? ("Restart now.'), src.indexOf("root.a11yNote)"));
for (const [name, answer, says] of [
  ["never online: the installed system is on UTC, and the page says where to set it", '{"ev":"answers","ok":true,"zone":""}', " Time zone: UTC; set it in Settings once online."],
  ["a zone found: nothing about it", '{"ev":"answers","ok":true,"zone":"Europe/Stockholm"}', ""],
  ["a practice run, which looks up no zone: nothing about it", '{"ev":"answers","ok":true}', ""],
]) {
  const setup = { zone: null };
  const scope = { setup, backend: {}, root: {} };
  if (receive) inScope(scope, receive.params, receive.body)(answer);
  const got = note ? inScope(scope, "", `return (${note});`)() : undefined;
  check(name, got === says, `zoneNote ${JSON.stringify(got)} with zone ${JSON.stringify(setup.zone)}`);
}
check("the Ready page's sentence carries it", ready.includes("root.zoneNote"));
done();
