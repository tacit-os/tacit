// The lock's fingerprint reader (modules/common/panels/lock/LockContext.qml and BootLockContext.qml): the context's own
// functions and fingerPam's own handlers run under node, with a pretend PamContext that ends rounds the way Quickshell
// 0.3's does (an error emits error, then completed with PamResult.Error) and a clock the test moves.
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const PamResult = { Success: 0, Failed: 1, Error: 2, MaxTries: 3 };

function context(file) {
  const src = read(file);
  const t = { now: 0 };
  const timer = { armed: false, restart() { this.armed = true; }, stop() { this.armed = false; } };
  const fingerPam = { active: false, start() { this.active = true; return true; }, abort() { this.active = false; } };
  const root = { fingerprintsConfigured: true, fingerErrors: 0, fingerErrorLimit: +qmlProperty(src, "fingerErrorLimit"),
    fingerStartedAt: 0, targetAction: 0, unlockedWith: null, unlocked(a) { this.unlockedWith = a; } };
  const scope = { root, fingerPam, fingerRetryTimer: timer, PamResult, Date: { now: () => t.now } };
  for (const name of ["tryFingerUnlock", "noteFingerError", "fingerRoundEnded", "stopFingerPam"]) {
    const f = qmlFunction(src, name);
    if (f) root[name] = scope[name] = inScope(scope, f.params, f.body);
  }
  const at = src.indexOf("id: fingerPam");
  const handler = key => {
    const k = src.indexOf(`${key}:`, at);
    return k < 0 || k > src.indexOf("\n    }", at) ? null
      : inScope(scope, "", `return (${readExpression(src, k + key.length + 1).expr});`)();
  };
  const onCompleted = handler("onCompleted"), onError = handler("onError");
  // the round that start() began ends after ms with result; then, if the reader was armed again, its 2 s timer fires
  function round(ms, result) {
    t.now += ms;
    fingerPam.active = false;
    timer.armed = false;
    if (result === PamResult.Error && onError) onError(1);
    onCompleted(result);
    if (!timer.armed) return false;
    t.now += 2000;
    root.tryFingerUnlock();
    return true;
  }
  root.tryFingerUnlock();   // the lock comes up
  return { root, round };
}

for (const file of ["modules/common/panels/lock/LockContext.qml", "modules/common/panels/lock/BootLockContext.qml"]) {
  console.log(`== the fingerprint reader on the lock (${file.split("/").pop()})`);
  {
    // nobody touches the reader for 10 minutes: pam_fprintd gives up after its 30 s each time, the worst case being an error
    const c = context(file);
    let rounds = 0;
    while (rounds < 20 && c.round(30000, PamResult.Error)) rounds++;
    check("an idle lock keeps the reader listening for 10 minutes", rounds === 20 && c.root.fingerprintsConfigured,
      `it stopped after ${rounds} rounds of 30 s`);
  }
  {
    // fifteen swipes with the wrong finger: five rounds that each end out of tries
    const c = context(file);
    let rounds = 0;
    while (rounds < 5 && c.round(3000, PamResult.MaxTries)) rounds++;
    check("wrong fingers do not turn the reader off", rounds === 5 && c.round(1500, PamResult.Success) === false &&
      c.root.unlockedWith === 0, `it stopped after ${rounds} rounds`);
  }
  {
    // fprintd down: every round fails at once
    const c = context(file);
    let rounds = 0;
    while (rounds < 50 && c.round(50, PamResult.Error)) rounds++;
    check("a reader that fails at once is asked a few times, then its icon goes", rounds <= c.root.fingerErrorLimit + 1 &&
      !c.root.fingerprintsConfigured, `${rounds} rounds, icon ${c.root.fingerprintsConfigured ? "still shown" : "gone"}`);
  }
}
done();
