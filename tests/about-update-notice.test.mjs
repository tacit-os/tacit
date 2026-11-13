// Settings > About's update button (modules/ii/settings/pages/About.qml, runSystemUpdate): the command it starts, run by
// bash with apps.update set to a missing terminal, to a terminal whose pkexec could not get a password (it exits 127,
// as foot passes on pkexec's status), and to ones that exit 0 and 126, with a pretend notify-send first on PATH that notes
// the notice instead of showing it.
import { spawnSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Settings > About's update and its 'Update didn't start' notice (About.qml)");
const fn = qmlFunction(read("modules/ii/settings/pages/About.qml"), "runSystemUpdate");
const esc = qmlFunction(read("modules/common/functions/StringUtils.qml"), "shellSingleQuoteEscape");
const StringUtils = { shellSingleQuoteEscape: inScope({}, esc.params, esc.body) };

const dir = mkdtempSync(join(tmpdir(), "tacit-update-"));
try {
  const bin = join(dir, "bin"), log = join(dir, "notices");
  mkdirSync(bin);
  writeFileSync(join(bin, "notify-send"), `#!/bin/bash\necho "$1" >> "${log}"\n`);
  writeFileSync(join(bin, "fake-term"), `#!/bin/bash\nexit "$1"\n`);
  for (const f of ["notify-send", "fake-term"]) chmodSync(join(bin, f), 0o755);

  // the notices the button gives with this apps.update
  function update(command) {
    rmSync(log, { force: true });
    const started = [];
    const scope = { Config: { options: { apps: { update: command } } }, StringUtils, Translation: { tr: s => s },
      Quickshell: { execDetached: a => started.push(a) }, Qt: { callLater() {} }, GlobalStates: {} };
    inScope(scope, fn.params, fn.body)();
    for (const a of started)
      spawnSync(a[0], a.slice(1), { env: { PATH: `${bin}:/usr/bin:/bin` }, stdio: "ignore", timeout: 10000 });
    return existsSync(log) ? readFileSync(log, "utf8").trim().split("\n") : [];
  }
  const said = n => (n.length ? `said ${JSON.stringify(n)}` : "said nothing");
  {
    const n = update("no-such-terminal --hold fish -i -c 'pkexec pacman -Syu'");
    check("a terminal that is not on this computer: the notice says the update didn't start", n.length === 1 && n[0] === "Update didn't start", said(n));
  }
  {
    const n = update("fake-term 127");
    check("pkexec could not get a password (the terminal exits 127): no notice, the update did start", n.length === 0, said(n));
  }
  for (const code of [0, 126]) {
    const n = update(`fake-term ${code}`);
    check(`an update that ends with ${code}: no notice`, n.length === 0, said(n));
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}
done();
