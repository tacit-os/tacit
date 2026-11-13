// Activity's Disk page after Clear while a scan is still running (scripts/activity/sample.py disk_scan): the scan that
// was running measured the caches before they went, so the one Clear asks for afterwards must still run, not be dropped
// as "busy". sample.py runs under python3 in a home of its own with 2 MB in ~/.cache/pip; the first scan is held just
// before its end until Clear has finished, and what the page is sent last is read.
import { spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== Clear during a disk scan is measured again (scripts/activity/sample.py)");
const home = mkdtempSync(join(tmpdir(), "tacit-disk-rescan-"));
mkdirSync(join(home, ".cache/pip"), { recursive: true });
mkdirSync(join(home, "Documents"));
writeFileSync(join(home, ".cache/pip/wheel"), Buffer.alloc(2_000_000));
writeFileSync(join(home, "Documents/a.txt"), "x");
const driver = `
import importlib.machinery, importlib.util, json, sys, threading, time
loader = importlib.machinery.SourceFileLoader("sample", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("sample", loader))
loader.exec_module(m)
events = []
m.emit = events.append
gate, held = threading.Event(), threading.Event()
real = m.old_downloads
def old_downloads():
    if not held.is_set():      # the first scan, its home folders measured: wait here until Clear is over
        held.set(); gate.wait(20)
    return real()
m.old_downloads = old_downloads
m.disk_start()                 # Activity opens: no result yet, a scan starts
held.wait(20)
m.act({"op": "clearCaches"})
for _ in range(200):
    if any(e.get("ev") == "done" for e in events): break
    time.sleep(0.05)
gate.set()
for t in threading.enumerate():
    if t is not threading.main_thread(): t.join(30)
scans = [e["disk"] for e in events if e.get("ev") == "disk"]
print(json.dumps({"done": [e for e in events if e.get("ev") == "done"],
                  "caches": [next(f["size"] for f in s["folders"] if f["name"] == "Caches") for s in scans]}))
`;

try {
  const r = spawnSync("python3", ["-I", "-c", driver, join(tree, "scripts/activity/sample.py")],
    { encoding: "utf8", env: { PATH: process.env.PATH, HOME: home }, timeout: 60000 });
  let out = null;
  try { out = JSON.parse(r.stdout); } catch (e) {}
  check("the scan and Clear run", out !== null && out.done.length === 1 && out.done[0].ok === true,
    out ? JSON.stringify(out.done) : (r.stderr || r.stdout).trim().split("\n").slice(-3).join(" | "));
  if (out) {
    const last = out.caches.at(-1);
    check("the scan running during Clear measured the 2 MB of caches", out.caches[0] >= 2_000_000, JSON.stringify(out.caches));
    check("the last sizes the page is sent are measured after Clear", last !== undefined && last < 1_000_000,
      `Caches as sent, in order: ${JSON.stringify(out.caches)}`);
  }
} finally {
  rmSync(home, { recursive: true, force: true });
}
done();
