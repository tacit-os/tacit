// The bar's Updates widget (modules/ii/bar/UpdatesCount.qml): its update command, as Settings > About's, said "Update
// didn't start" for any exit 127, and pkexec exits 127 when it could not get a password, after the terminal had opened
// and asked. The widget's own command runs under bash as Quickshell runs it, with apps.update set to a missing terminal,
// to a terminal ending 127, and to ones ending 0 and 126, with a pretend notify-send first on PATH that notes the notice
// instead of showing it; the Process's onExited runs under node with each exit.
import { spawnSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the bar's Updates widget and its 'Update didn't start' notice (UpdatesCount.qml)");
const src = read("modules/ii/bar/UpdatesCount.qml");
const procAt = src.indexOf("id: updateProc");
const commandExpr = readExpression(src, src.indexOf("command:", procAt) + "command:".length).expr;
const exitedExpr = readExpression(src, src.indexOf("onExited:", procAt) + "onExited:".length).expr;
const esc = qmlFunction(read("modules/common/functions/StringUtils.qml"), "shellSingleQuoteEscape");
const StringUtils = { shellSingleQuoteEscape: inScope({}, esc.params, esc.body) };

const dir = mkdtempSync(join(tmpdir(), "tacit-bar-update-"));
try {
  const bin = join(dir, "bin"), log = join(dir, "notices");
  mkdirSync(bin);
  writeFileSync(join(bin, "notify-send"), `#!/bin/bash\necho "$1" >> "${log}"\n`);
  writeFileSync(join(bin, "fake-term"), `#!/bin/bash\nexit "$1"\n`);
  for (const f of ["notify-send", "fake-term"]) chmodSync(join(bin, f), 0o755);

  // the notices this apps.update gives: the command's own, then the widget's on its exit
  function update(command) {
    rmSync(log, { force: true });
    const scope = { Config: { options: { apps: { update: command } } }, StringUtils, Translation: { tr: s => s } };
    const argv = inScope(scope, "", `return (${commandExpr});`)();
    const r = spawnSync(argv[0], argv.slice(1), { env: { PATH: `${bin}:/usr/bin:/bin` }, stdio: "ignore", timeout: 10000 });
    const said = existsSync(log) ? readFileSync(log, "utf8").trim().split("\n") : [];
    const started = [];
    const after = { Quickshell: { execDetached: a => started.push(a) }, Translation: { tr: s => s }, Updates: { refresh() {} },
      notifyTimer: { restart() {} } };
    inScope(after, "", `return (${exitedExpr});`)()(r.status, 0);
    for (const a of started) if (a[0] === "notify-send") said.push(a[1]);
    return { exit: r.status, said };
  }
  const told = u => `exit ${u.exit}, ${u.said.length ? `said ${JSON.stringify(u.said)}` : "said nothing"}`;
  {
    const u = update("no-such-terminal --hold fish -i -c 'pkexec pacman -Syu'");
    check("a terminal that is not on this computer: the notice says the update didn't start, once", u.said.length === 1 && u.said[0] === "Update didn't start", told(u));
  }
  {
    const u = update("fake-term 127");
    check("pkexec could not get a password (the terminal exits 127): no notice, the update did start", u.exit === 127 && u.said.length === 0, told(u));
  }
  for (const code of [0, 126]) {
    const u = update(`fake-term ${code}`);
    check(`an update that ends with ${code}: no notice`, u.exit === code && !u.said.includes("Update didn't start"), told(u));
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}
done();
