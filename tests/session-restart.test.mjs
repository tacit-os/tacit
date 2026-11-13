// Restart from the session screen, the palette or Apps (modules/common/functions/Session.qml, reboot()) with updates
// downloaded: its own code under node gives the script it runs, and bash runs that script with PATH holding only pretend
// systemctl, reboot and loginctl (no real one can be reached), each noting its call and refusing or not.
import { execFileSync } from "child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Restart with updates downloaded (Session.reboot)");
const src = read("modules/common/functions/Session.qml");
const f = qmlFunction(src, "reboot");

// the script reboot() hands to runAction, with Updates.ready as given
function script(ready) {
  let ran = null;
  const root = { runAction: (label, s) => (ran = s) };
  inScope({ root, Updates: { ready }, Translation: { tr: s => s } }, f.params, f.body)();
  return ran;
}

// runs it with the restart refused or not: { calls, code }
function run(s, refused) {
  const dir = mkdtempSync(join(tmpdir(), "tacit-restart-"));
  try {
    const log = join(dir, "calls");
    writeFileSync(log, "");
    for (const [name, code] of [["systemctl", 0], ["reboot", refused ? 1 : 0], ["loginctl", refused ? 1 : 0]]) {
      writeFileSync(join(dir, name), `#!/bin/bash\necho "${name} $*" >> "${log}"\nexit ${code}\n`);
      chmodSync(join(dir, name), 0o755);
    }
    let code = 0;
    try { execFileSync("/bin/bash", ["-c", s], { env: { PATH: dir } }); } catch (e) { code = e.status; }
    return { calls: readFileSync(log, "utf8").split("\n").map(l => l.trimEnd()).filter(Boolean), code };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

{
  const r = run(script(true), true);
  check("refused: the readied install is taken back", r.calls.at(-1) === "systemctl start tacit-update@cancel.service", r.calls.join("; "));
  check("and the Restart still reads as refused", r.code !== 0, `exit ${r.code}`);
}
{
  const r = run(script(true), false);
  check("restarting: the install is readied and nothing takes it back",
    r.calls.join("; ") === "systemctl start tacit-update@now.service; reboot", r.calls.join("; "));
}
{
  const r = run(script(false), true);
  check("refused with no updates downloaded: no update unit is started", !r.calls.some(c => c.includes("tacit-update")) && r.code !== 0,
    `${r.calls.join("; ")}, exit ${r.code}`);
}

done();
