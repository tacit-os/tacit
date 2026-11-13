// Activity's tray lookup (scripts/activity/sample.py tray_owners) with a tray icon whose app is hung: its Id is asked
// once and again only after a minute, not at every sample, each of which waited the 2 s timeout. sample.py's own
// tray_owners() runs under python3 with a pretend busctl: two icons, one app that never answers, and a clock moved by hand.
import { spawnSync } from "child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== a hung tray app does not hold up every Activity sample (scripts/activity/sample.py)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-tray-hung-"));
const busctl = join(tmp, "busctl"), log = join(tmp, "asked");
writeFileSync(busctl, `#!/bin/bash
case " $* " in
  *" RegisteredStatusNotifierItems "*) echo '{"type":"as","data":[":1.50/StatusNotifierItem",":1.60/StatusNotifierItem"]}' ;;
  *" GetConnectionUnixProcessID s :1.50 "*) echo '{"type":"u","data":[4242]}' ;;
  *" GetConnectionUnixProcessID s :1.60 "*) echo '{"type":"u","data":[4343]}' ;;
  *" get-property :1.50 "*) echo hung >> "$ASKED"; exec sleep 5 ;;
  *" get-property :1.60 "*) echo ok >> "$ASKED"; echo '{"type":"s","data":"chrome_status_icon_1"}' ;;
esac
`);
chmodSync(busctl, 0o755);
const driver = `
import importlib.machinery, importlib.util, json, sys, time, types
loader = importlib.machinery.SourceFileLoader("sample", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("sample", loader))
loader.exec_module(m)
now = [1000.0]
m.time = types.SimpleNamespace(monotonic=lambda: now[0], time=time.time, sleep=time.sleep)
out = []
for step in (0, 2, 2, 61):   # samples 2 s apart, then one a minute later
    now[0] += step
    t = time.time(); got = m.tray_owners(); out.append({"s": round(time.time() - t, 1), "got": {str(k): v for k, v in got.items()}})
print(json.dumps(out))
`;

try {
  const r = spawnSync("python3", ["-I", "-c", driver, join(tree, "scripts/activity/sample.py")],
    { encoding: "utf8", env: { PATH: `${tmp}:${process.env.PATH}`, HOME: tmp, ASKED: log }, timeout: 60000 });
  let runs = [];
  try { runs = JSON.parse(r.stdout); } catch (e) {}
  const asked = () => spawnSync("grep", ["-c", "hung", log], { encoding: "utf8" }).stdout.trim();
  check("the lookup runs", runs.length === 4, (r.stderr || r.stdout).trim().split("\n").slice(-3).join(" | "));
  if (runs.length === 4) {
    check("the first sample waits for the hung app once", runs[0].s >= 1.5, `${runs[0].s} s`);
    check("the next two samples do not wait for it again", runs[1].s < 1 && runs[2].s < 1, `${runs[1].s} s, ${runs[2].s} s`);
    check("a minute later it is asked again (it may answer by then)", runs[3].s >= 1.5 && asked() === "2", `${runs[3].s} s, asked ${asked()} times`);
    check("the app that answers keeps its icon at every sample, the hung one has none",
      runs.every(x => JSON.stringify(x.got) === '{"4343":"chrome_status_icon_1"}'), JSON.stringify(runs.map(x => x.got)));
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
