// A locked-out account (services/Faillock.qml, scripts/lock/faillock.py): faillock.py run over a pretend tally folder
// and settings, as pam_faillock's preauth decides, then the words Faillock.qml's own bindings make of its answer and the
// lock's, the boot lock's and an app's password request's fields showing them. While the account is locked the right
// password fails too, and all three said only "Incorrect password".
import { spawnSync } from "child_process";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlProperty } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== a locked-out account (Faillock.qml, faillock.py)");
const script = join(tree, "scripts/lock/faillock.py");
const tmp = mkdtempSync(join(tmpdir(), "tacit-faillock-"));
try {
  // faillock.h's struct tally, one per failure: source[52], reserved, status (1: valid), time
  const tally = (...agesInSeconds) => {
    const now = Math.floor(Date.now() / 1000), buf = Buffer.alloc(64 * agesInSeconds.length);
    agesInSeconds.forEach((age, i) => {
      buf.write("/dev/tty1", i * 64);
      buf.writeUInt16LE(0x1, i * 64 + 54);
      buf.writeBigUInt64LE(BigInt(now - age), i * 64 + 56);
    });
    writeFileSync(join(tmp, "sam"), buf);
  };
  const ask = (conf = "", pam = "auth required pam_faillock.so preauth\n") => {
    if (!existsSync(script)) return null;
    writeFileSync(join(tmp, "faillock.conf"), `dir = ${tmp}\n${conf}`);
    writeFileSync(join(tmp, "system-auth"), pam);
    const r = spawnSync("python3", ["-I", script, "sam", join(tmp, "faillock.conf"), join(tmp, "system-auth")], { encoding: "utf8" });
    try { return JSON.parse(r.stdout); } catch { return null; }
  };
  const said = r => JSON.stringify(r);
  tally(120, 60, 5);
  check("three wrong passwords in a row: locked, for faillock's 10 minutes after 3", said(ask()) === '{"locked":true,"deny":3,"minutes":10}', said(ask()));
  check("the length comes from faillock.conf", ask("unlock_time = 300\n")?.minutes === 5 && ask("unlock_time = 300\n")?.locked === true);
  check("and the preauth line's own arguments win over the file", said(ask("deny = 5\n", "auth required pam_faillock.so preauth deny=3 unlock_time=900\n")) === '{"locked":true,"deny":3,"minutes":15}',
    said(ask("deny = 5\n", "auth required pam_faillock.so preauth deny=3 unlock_time=900\n")));
  check("with deny = 5 three are not enough", ask("deny = 5\n")?.locked === false);
  check("unlock_time = never: locked until it is reset", said(ask("unlock_time = never\n")) === '{"locked":true,"deny":3,"minutes":0}');
  tally(60, 5);
  check("two wrong passwords: not locked", ask()?.locked === false);
  tally(1300, 700, 5);
  check("three spread wider than fail_interval: not locked", ask()?.locked === false);
  tally(800, 750, 700);
  check("three whose lock has run out: not locked", ask()?.locked === false);
  rmSync(join(tmp, "sam"));
  check("no failures recorded: not locked", ask()?.locked === false);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}

// Faillock.qml's words, and what each password field says once a password has failed
const src = existsSync(join(tree, "services/Faillock.qml")) ? read("services/Faillock.qml") : "";
const Translation = { tr: s => Object.assign(new String(s), { arg(a) { const t = String(this).replace(/%\d/, a); return Object.assign(new String(t), { arg: this.arg }); } }) };
function faillock(state) {
  const root = { ...state };
  for (const name of ["words", "failure"]) {
    const expr = qmlProperty(src, name);
    root[name] = expr === null ? undefined : String(inScope({ root, Translation }, "", `return (${expr});`)());
  }
  return root;
}
const lockedOut = faillock({ locked: true, reading: false, deny: 3, minutes: 10 });
check("locked: \"Locked for 10 minutes after 3 tries\"", lockedOut.failure === "Locked for 10 minutes after 3 tries", lockedOut.failure);
check("one minute, and until reset", faillock({ locked: true, reading: false, deny: 5, minutes: 1 }).words === "Locked for 1 minute after 5 tries"
  && faillock({ locked: true, reading: false, deny: 3, minutes: 0 }).words === "Locked after 3 tries");
check("not locked: \"Incorrect password\"", faillock({ locked: false, reading: false, deny: 3, minutes: 10 }).failure === "Incorrect password");
check("while the tally is read: nothing, so the wrong words never flash up", faillock({ locked: true, reading: true, deny: 3, minutes: 10 }).failure === "");

// the placeholder blocks, with a password that has just failed on a locked account
for (const [name, file, scope] of [
  ["the lock", "modules/ii/lock/LockSurface.qml", { GlobalStates: { screenUnlockFailed: true }, root: { context: { authUnavailable: false, refusedAction: "" }, armedPower: 0 }, LockContext: { ActionEnum: { Unlock: 0, Poweroff: 1, Reboot: 2 } } }],
  ["the boot lock", "modules/ii/lock/BootLockSurface.qml", { root: { context: { authUnavailable: false, unlockFailed: true, refusedAction: "" }, armedPower: 0 }, BootLockContext: { ActionEnum: { Unlock: 0, Poweroff: 1, Reboot: 2 } } }],
]) {
  const s = read(file);
  const at = s.indexOf("{", s.indexOf("placeholderText:", s.indexOf("id: passwordBox")));
  const body = s.slice(at + 1, s.indexOf("\n                }", at));
  const shown = String(inScope({ ...scope, Faillock: lockedOut, Translation }, "", body)());
  check(`${name} says it`, shown === "Locked for 10 minutes after 3 tries", shown);
}
{
  const expr = qmlProperty(read("modules/ii/polkit/PolkitContent.qml"), "placeholderText") ??
    /placeholderText:\s*([^\n]+)/.exec(read("modules/ii/polkit/PolkitContent.qml"))[1];
  const shown = String(inScope({ root: { failed: true }, Faillock: lockedOut, Translation, PolkitService: { cleanPrompt: "Password" } }, "", `return (${expr});`)());
  check("an app's password request says it", shown === "Locked for 10 minutes after 3 tries", shown);
}
done();
