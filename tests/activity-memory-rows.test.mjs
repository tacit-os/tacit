// Activity's Now page: its rows add up to the memory in use above them. The kernel's in use (MemTotal - MemAvailable)
// is more than the cgroups hold (graphics, drivers and the kernel's own belong to no process); that rest is its own row,
// Graphics and kernel, named apart from Tacit itself's part "The system" and never part of Tacit itself. sample.py's own
// sample() runs under python3 with a pretend /proc/meminfo, cgroups and no processes, windows or agents host; then
// Data.qml's makeNow() runs under node on what it gave.
import { spawnSync } from "child_process";
import { mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== Activity's rows add up to the memory in use (scripts/activity/sample.py, modules/activity/Data.qml)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-memory-rows-"));
const MB = 1048576, GiB = 1073741824;
// cgroups by path, in MB: the user's 3000 (of which the desktop's session 1200), the system's 600, init 10
const driver = `
import importlib.machinery, importlib.util, json, os, sys
loader = importlib.machinery.SourceFileLoader("sample", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("sample", loader))
loader.exec_module(m)
MB = 1048576
user = f"/user.slice/user-{m.UID}.slice"
cg = {"/user.slice": 3000, "/system.slice": 600, "/init.scope": 10, f"{user}/session-2.scope": 1200}
m.CG = sys.argv[2]
os.makedirs(m.CG + user + "/session-2.scope", exist_ok=True)
m.cg_mem = lambda path, ratio: cg.get(path, 0) * MB
m.zram_ratio = lambda: 0.0
m.scan = lambda: {}
m.hypr_clients = lambda: []
m.tray_owners = lambda: {}
m.host = lambda req: None
m.battery = lambda: None
real = m.read
fake = {"/proc/meminfo": "MemTotal: 8000000 kB\\nMemAvailable: 3000000 kB\\nSwapTotal: 0 kB\\nSwapFree: 0 kB\\n",
        "/proc/stat": "cpu 10 0 10 100 0 0 0 0 0 0\\n"}
m.read = lambda path, default="": fake.get(path, "some avg10=0.00 avg60=0.00 avg300=0.00 total=0\\n" if path.startswith("/proc/pressure/") else real(path, default))
print(json.dumps(m.sample()))
`;

try {
  const r = spawnSync("python3", ["-I", "-c", driver, join(tree, "scripts/activity/sample.py"), join(tmp, "cgroup")],
    { encoding: "utf8", env: { PATH: process.env.PATH, HOME: tmp }, timeout: 30000 });
  let s = null;
  try { s = JSON.parse(r.stdout); } catch (e) {}
  check("the sampler runs", s !== null, (r.stderr || r.stdout).trim().split("\n").slice(-3).join(" | "));
  if (s) {
    const used = s.mem.total - s.mem.avail, held = s.groups.reduce((n, g) => n + g.mem, 0);
    const tacit = s.groups.find(g => g.kind === "tacit");
    check("Tacit itself holds what the cgroups hold, nothing more", tacit?.mem === 3610 * MB, `${tacit?.mem / MB} MB`);
    check("and its parts are its own", (tacit?.tacitParts ?? []).every(p => p.name !== "Graphics and kernel") &&
      (tacit?.tacitParts ?? []).reduce((n, p) => n + p.mem, 0) <= tacit.mem, JSON.stringify(tacit?.tacitParts));
    check("what no process holds is given apart, and the groups and it add up to what is in use",
      held + (s.mem.system ?? 0) === used, `in use ${(used / MB).toFixed(0)} MB, groups ${(held / MB).toFixed(0)} MB, apart ${s.mem.system ?? "none"}`);

    // ---- the page
    const data = read("modules/activity/Data.qml");
    const d = { snap: s, gib: GiB, memAlarm: false, quit: null, letFinish: {}, byProcessor: false,
      apps: () => [], agents: () => [], windowless: () => [], trayOf: () => null, group: () => null };
    for (const name of ["gb", "pct", "both", "dur", "makeNow"]) {
      const f = qmlFunction(data, name);
      if (f) d[name] = inScope({ d, DesktopEntries: { applications: { values: [] } } }, f.params, f.body);
    }
    const page = d.makeNow();
    const rows = page.tacit ?? [];
    const sys = rows.find(i => i.kind === "system"), self = rows.find(i => i.kind === "tacit");
    const parts = (s.groups.find(g => g.kind === "tacit")?.tacitParts ?? []).map(p => p.name);
    check("the Now page lists Graphics and kernel as a row of its own, said in plain words", sys !== undefined
      && sys.n === "Graphics and kernel" && sys.detail === "what the graphics driver and the kernel hold"
      && sys.quit === "" && !sys.open, JSON.stringify(rows));
    const word = n => n.toLowerCase().replace(/^the /, "");
    check("and its name is not taken by one of Tacit itself's parts (The system)", parts.includes("The system")
      && !parts.some(n => word(sys?.n ?? "").includes(word(n))), JSON.stringify(parts));
    check("Tacit itself shows its own total", self?.c1 === d.gb(3610 * MB), self?.c1);
    check("Graphics and kernel shows the rest of what is in use", sys?.c1 === d.gb(used - 3610 * MB), sys?.c1);
    d.byProcessor = true;
    check("the processor view, which cannot measure it, leaves the row out", !(d.makeNow().tacit ?? []).some(i => i.kind === "system"));
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
