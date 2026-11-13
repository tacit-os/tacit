// How long bin/tacit-app waits for one of the desktop's apps to start, run under sh with a pretend qs: an app that
// fails as it starts (a QML error, a missing module) and one that takes a moment and then answers.
import { spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== waiting for an app to start (bin/tacit-app)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-app-"));
const pidFile = join(tmp, "qs.pid");
try {
  const bin = join(tmp, "bin"), notes = join(tmp, "notes");
  mkdirSync(bin); mkdirSync(join(tmp, "run"));
  // the launch (no "ipc"): FAIL exits at once, as a QML error does; otherwise it answers once READY is there
  writeFileSync(join(bin, "qs"), `#!/bin/sh
case " $* " in
*" ipc "*) [ -f "$READY" ] ;;
*) echo $$ > "${pidFile}"; [ -n "$FAIL" ] && { echo "qml error" >&2; exit 1; }; sleep 1; touch "$READY"; exec sleep 30 ;;
esac
`, { mode: 0o755 });
  for (const f of ["hyprctl", "notify-send"]) writeFileSync(join(bin, f), `#!/bin/sh\necho "${f} $*" >> "${notes}"\n`, { mode: 0o755 });
  const ensure = fail => {
    rmSync(notes, { force: true });
    const t = Date.now();
    const r = spawnSync("sh", [join(tree, "bin/tacit-app"), "ensure", "graphis"], { encoding: "utf8", timeout: 15000,
      env: { PATH: `${bin}:${process.env.PATH}`, HOME: tmp, XDG_RUNTIME_DIR: join(tmp, "run"), TACIT_SHELL: tmp, READY: join(tmp, "ready"), FAIL: fail ? "1" : "" } });
    let said = "";
    try { said = readFileSync(notes, "utf8"); } catch {}
    return { status: r.status, out: r.stdout.trim(), secs: (Date.now() - t) / 1000, said };
  };

  const failed = ensure(true);
  check("an app that fails as it starts is reported within seconds, not after 20", failed.status === 1 && failed.secs < 8,
    `exit ${failed.status} after ${failed.secs.toFixed(1)} s`);
  check("and says it did not start", /notify-send -u critical Graphis did not start/.test(failed.said), failed.said);
  const slow = ensure(false);
  check("an app that takes a moment to start is waited for", slow.status === 0 && slow.out === "started", `exit ${slow.status}, "${slow.out}"`);
} finally {
  try { process.kill(parseInt(readFileSync(pidFile, "utf8"))); } catch {}
  rmSync(tmp, { recursive: true, force: true });
}
done();
