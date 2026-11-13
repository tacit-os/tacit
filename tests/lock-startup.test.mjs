// "Lock when you log in" (modules/common/panels/lock/LockScreen.qml): the startup lock's own test run by bash, with
// a runtime folder of its own and a pretend pgrep and pidof first on PATH. A login that already asked for the password
// must not be asked again; one that did not is locked.
import { execFileSync } from "child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { adapterDefaults, inScope, loadInto, readExpression, runMigrate } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Lock when you log in (LockScreen.qml)");
const src = read("modules/common/panels/lock/LockScreen.qml");
const at = src.indexOf("command:", src.indexOf("id: startupLockProc"));
const cmd = inScope({}, "", `return (${readExpression(src, at + "command:".length).expr});`)();
const tmp = mkdtempSync(join(tmpdir(), "tacit-startlock-"));
try {
  // the boot lock is running when BOOTLOCK is set; hyprlock never is
  writeFileSync(join(tmp, "pgrep"), '#!/bin/sh\n[ -n "$BOOTLOCK" ] && echo 4242\n');
  writeFileSync(join(tmp, "pidof"), "#!/bin/sh\nexit 1\n");
  for (const f of ["pgrep", "pidof"]) chmodSync(join(tmp, f), 0o755);
  const locks = ({ marker, bootlock }) => {
    rmSync(join(tmp, "martida-lock-ready"), { force: true });
    if (marker) writeFileSync(join(tmp, "martida-lock-ready"), "");
    try {
      execFileSync(cmd[0], cmd.slice(1), { env: { PATH: `${tmp}:${process.env.PATH}`, XDG_RUNTIME_DIR: tmp, ...(bootlock ? { BOOTLOCK: "1" } : {}) } });
      return true;
    } catch { return false; }
  };
  check("after the password at the boot lock or the login screen, no second lock", !locks({ marker: true, bootlock: false }));
  check("while the boot lock is asking, no lock over it", !locks({ marker: false, bootlock: true }));
  check("a login nothing asked a password for is locked", locks({ marker: false, bootlock: false }));
} finally {
  rmSync(tmp, { recursive: true, force: true });
}

// The switch is gone from Settings: Tacit's login always asks (the boot lock, or the login screen's password), so it
// changed nothing. A value saved with it is kept, and the lock above still reads it.
{
  const bound = /checked:\s*Config\.options\.lock\.launchOnStartup/;
  check("Settings and the old shell settings page have no row for it",
    !bound.test(read("tacit-settings.qml")) && !bound.test(read("modules/ii/settings/pages/InterfaceConfig.qml")));
  const config = read("modules/common/Config.qml");
  const kept = runMigrate(config, loadInto(adapterDefaults(config), { lock: { launchOnStartup: true } })).options.lock.launchOnStartup;
  check("a saved \"on\" is left as it is", kept === true, `became ${kept}`);
}
done();
