// A Shut down or Restart confirmed with the password on the lock, which the system refuses (a program holds a shutdown
// block): the lock's and the boot lock's own handlers and their context's own functions run under node, then the
// field's placeholder binding. The field and the fingerprint reader must come back, and the field must say so.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const ActionEnum = { Unlock: 0, Poweroff: 1, Reboot: 2 };
const tr = s => Object.assign(new String(s), { arg: x => s.replace("%1", x) });

function lock({ screen, contextFile, surfaceFile, enumName }) {
  const ctxSrc = read(contextFile), screenSrc = read(screen), surfaceSrc = read(surfaceFile);
  const calls = [];
  const timer = () => ({ restart() {}, stop() {} });
  const pam = { active: false, start() { this.active = true; return true; }, abort() { this.active = false; } };
  const fingerPam = { active: false, start() { this.active = true; return true; }, abort() { this.active = false; } };
  const GlobalStates = { screenLocked: true, screenUnlockFailed: false };
  const ctx = { currentText: "", unlockInProgress: false, showFailure: false, authUnavailable: false, unlockFailed: false,
    refusedAction: "", fingerprintsConfigured: true, fingerErrors: 0, fingerErrorLimit: 3, targetAction: 0, alsoInhibitIdle: false,
    shouldReFocus() {} };
  const scope = { root: ctx, pam, fingerPam, fingerRetryTimer: timer(), passwordClearTimer: timer(), GlobalStates,
    [enumName]: { ActionEnum }, Date };
  for (const name of ["resetTargetAction", "clearText", "forgetAttempt", "reset", "tryUnlock", "tryFingerUnlock",
    "noteFingerError", "stopFingerPam"]) {
    const f = qmlFunction(ctxSrc, name);
    if (f) ctx[name] = scope[name] = inScope(scope, f.params, f.body);
  }
  const Session = { poweroff() { calls.push("poweroff"); }, reboot() { calls.push("reboot"); } };
  const outer = { lockContext: ctx, Session, GlobalStates, [enumName]: { ActionEnum }, Config: { options: { lock: { security: {} } } },
    lock: {}, root: { xrayOff() {}, unlockKeyring() {} }, unlockKeyringProc: {}, readyMarkerProc: {}, quitGuard: { start() {} },
    Idle: {} };
  const at = screenSrc.indexOf("onUnlocked:");
  const onUnlocked = inScope(outer, "", `return (${readExpression(screenSrc, at + "onUnlocked:".length).expr});`)();
  const failed = qmlFunction(screenSrc, "onActionFailed");
  const onActionFailed = failed ? inScope(outer, failed.params, failed.body) : () => {};
  const ph = surfaceSrc.indexOf("placeholderText:", surfaceSrc.indexOf("id: passwordBox"));
  const block = readExpression(surfaceSrc, ph + "placeholderText:".length).expr;
  const placeholder = () => String(inScope({ root: { context: ctx }, GlobalStates, Translation: { tr },
    [enumName]: { ActionEnum } }, "", block.slice(1, -1))());
  return { ctx, calls, fingerPam, onUnlocked, onActionFailed, placeholder };
}

for (const l of [
  { screen: "modules/common/panels/lock/LockScreen.qml", contextFile: "modules/common/panels/lock/LockContext.qml",
    surfaceFile: "modules/ii/lock/LockSurface.qml", enumName: "LockContext" },
  { screen: "bootlock.qml", contextFile: "modules/common/panels/lock/BootLockContext.qml",
    surfaceFile: "modules/ii/lock/BootLockSurface.qml", enumName: "BootLockContext" },
]) {
  console.log(`== a refused Shut down on the lock (${l.screen.split("/").pop()})`);
  const c = lock(l);
  c.ctx.targetAction = ActionEnum.Poweroff;
  c.ctx.currentText = "hunter2";
  c.ctx.tryUnlock();
  c.ctx.stopFingerPam();          // the password was right: the reader stops ...
  c.onUnlocked(ActionEnum.Poweroff);
  c.onActionFailed("Shut down", 1); // ... and logind refuses
  check("Shut down was asked for", c.calls.join() === "poweroff", c.calls.join());
  check("the field takes a password again", c.ctx.unlockInProgress === false);
  check("the fingerprint reader listens again", c.fingerPam.active === true);
  check("the field says the Shut down failed", c.placeholder() === "Shut down failed", `it says "${c.placeholder()}"`);
  check("the armed Shut down is disarmed", c.ctx.targetAction === ActionEnum.Unlock);
  c.ctx.currentText = "hunter2";
  c.ctx.tryUnlock();
  check("a new try forgets it", c.ctx.refusedAction === "" || c.ctx.refusedAction === undefined);
}
done();
