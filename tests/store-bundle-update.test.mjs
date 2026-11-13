// An app got from Apps is brought up to date at its first start after Tacit's updates (scripts/store/bundle.py run()),
// as Your apps promises ("They update with Tacit's system updates"): when the app's own package is newer in the system's
// lists, not only when a system package it shares changed. run() itself, in a home of its own, with the install, the
// shell and the start replaced (tests/lib/store_cases.py).
import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { check, done, tree } from "./lib/check.mjs";

const helper = join(dirname(fileURLToPath(import.meta.url)), "lib", "store_cases.py");
function store(name) {
  const r = spawnSync("python3", ["-I", helper, tree, name], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(r.stderr);
  return JSON.parse(r.stdout);
}

console.log("== an app's own update (scripts/store/bundle.py run)");
{
  const r = store("start-newer");
  check("Discord 0.0.112 in the lists: the bundle of 0.0.111 is updated before it starts", r.installed.join() === "discord",
    JSON.stringify(r));
  check("on today's package list, not one older than the system's", r.lists.includes(0), `lists refreshed: ${JSON.stringify(r.lists)}`);
  check("and the notch is told it is getting ready", JSON.stringify(r.told[0]) === '["preparing","discord",0]', JSON.stringify(r.told));
}
{
  const r = store("start-same");
  check("Discord as it was got: nothing is fetched, and the start is quick again next time",
    r.installed.length === 0 && r.lists.length === 0 && r.told.length === 0 && r.host_stamp, JSON.stringify(r));
}
{
  // no mirror answers: the bundle's own list is older than the one that named the update, so nothing can be got now
  const r = store("start-newer-offline");
  check("offline then: it starts as it is, and the update is tried again at a start ten minutes on",
    r.installed.length === 0 && !r.host_stamp && r.tried, JSON.stringify(r));
}
done();
