// Cancel tonight: session/updates/tacit-update cancel-tonight under bash (its system paths moved into a folder of its
// own, a pretend systemctl first on PATH), the polkit rule that lets the person start it run under node, Updates.qml's
// cancelTonight() and its Process, and Settings > About > Updates' row of buttons (tacit-settings.qml), each button's
// visible, label and onPressed run with Tonight chosen or not.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("Cancel tonight (tacit-update cancel-tonight, 50-tacit-updates.rules, Updates.cancelTonight, Settings' row)");

// ---- the step
const dir = mkdtempSync(join(tmpdir(), "tacit-cancel-tonight-"));
try {
  const bin = join(dir, "bin"), state = join(dir, "state"), log = join(dir, "calls"), held = join(dir, "held");
  for (const d of [bin, state]) mkdirSync(d);
  writeFileSync(join(dir, "tacit-update"), read("session/updates/tacit-update")
    .replaceAll("/var/lib/tacit", state).replaceAll("/run/tacit-update-held", held).replaceAll("/system-update", join(dir, "system-update")));
  writeFileSync(join(bin, "systemctl"), `#!/bin/bash\necho "systemctl $*" >> "${log}"\n[ "$FAIL" = 1 ] && exit 1\nexit 0\n`);
  chmodSync(join(bin, "systemctl"), 0o755);
  const run = (fail = false) => {
    writeFileSync(log, "");
    writeFileSync(join(state, "tonight"), "");
    writeFileSync(held, "1789000000\n");
    let code = 0;
    try {
      execFileSync("bash", [join(dir, "tacit-update"), "cancel-tonight"], { stdio: "pipe", env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, FAIL: fail ? "1" : "0" } });
    } catch (e) {
      code = e.status;
    }
    return { code, calls: readFileSync(log, "utf8").trim().split("\n").filter(Boolean), tonight: existsSync(join(state, "tonight")), held: existsSync(held) };
  };
  const line = r => `exit ${r.code}, asked ${JSON.stringify(r.calls)}, tonight ${r.tonight ? "kept" : "gone"}, held ${r.held ? "kept" : "gone"}`;
  const r = run();
  check("cancel-tonight turns the night's timer off and leaves nothing of the choice", r.code === 0 && r.calls.includes("systemctl disable --now tacit-update-night.timer")
    && !r.tonight && !r.held, line(r));
  const f = run(true);
  check("a timer systemd would not turn off: it fails, and keeps when Tonight was chosen", f.code !== 0 && f.tonight, line(f));
} finally {
  rmSync(dir, { recursive: true, force: true });
}

// ---- the polkit rule: the person at the computer starts it without a password, and nothing more
{
  let rule = null;
  new Function("polkit", read("session/updates/50-tacit-updates.rules"))({ addRule: f => { rule = f; }, Result: { YES: "yes" } });
  const ask = (unit, verb = "start", wheel = true) => rule({ id: "org.freedesktop.systemd1.manage-units", lookup: k => ({ unit, verb })[k] },
    { local: true, active: true, isInGroup: g => wheel && g === "wheel" });
  check("the rule lets the person start tacit-update@cancel-tonight", ask("tacit-update@cancel-tonight.service") === "yes",
    `start answered ${JSON.stringify(ask("tacit-update@cancel-tonight.service"))}`);
  check("and only start, only for wheel, only that unit", ask("tacit-update@cancel-tonight.service", "stop") !== "yes"
    && ask("tacit-update@cancel-tonight.service", "start", false) !== "yes" && ask("tacit-update@install.service") !== "yes");
}

// ---- Updates.cancelTonight(): it starts that unit, and Tonight is off once systemd has done it
{
  const src = read("services/Updates.qml");
  const f = qmlFunction(src, "cancelTonight");
  const at = src.indexOf("id: cancelTonightProc");
  const proc = at < 0 ? "" : src.slice(src.lastIndexOf("Process {", at), matchBrace(src, src.lastIndexOf("Process {", at) + "Process ".length) + 1);
  const cmd = proc ? inScope({}, "", `return ${readExpression(proc, proc.indexOf("command:") + "command:".length).expr};`)() : [];
  check("cancelTonight() starts tacit-update@cancel-tonight.service", !!f && JSON.stringify(cmd) === JSON.stringify(["systemctl", "start", "tacit-update@cancel-tonight.service"]),
    f ? `it runs ${JSON.stringify(cmd)}` : "Updates.qml has no cancelTonight()");
  if (f && proc) {
    const exited = readExpression(proc, proc.indexOf("onExited:") + "onExited:".length).expr;
    const outcome = code => {
      const root = { tonightSet: true }, said = [];
      const proc = { running: false };
      const scope = { root, cancelTonightProc: proc, IslandController: { request: (n, d) => said.push(d.text) } };
      inScope(scope, f.params, f.body)();
      inScope(scope, "", `return (${exited});`)()(code, 0);
      return { started: proc.running, tonight: root.tonightSet, said };
    };
    const ok = outcome(0), no = outcome(1);
    check("once it went through, Tonight is off; one that failed keeps it and says so", ok.started && !ok.tonight && no.tonight && no.said.length === 1,
      `ok: ${JSON.stringify(ok)}; failed: ${JSON.stringify(no)}`);
  }
}

// ---- Settings' row: Cancel beside "Tonight at 03:00 ...", and Restart still there
{
  const src = read("tacit-settings.qml");
  const rowAt = src.lastIndexOf("control: Row {", src.indexOf("onPressed: Updates.tonight()"));
  const row = src.slice(rowAt, matchBrace(src, src.indexOf("{", rowAt)) + 1);
  const key = (block, k) => {
    const m = new RegExp(`\\n\\s*${k}\\s*:\\s*`).exec(block);
    return m ? readExpression(block, m.index + m[0].length).expr : null;
  };
  const buttons = [];
  for (let i = row.indexOf("TextButton {"); i >= 0; i = row.indexOf("TextButton {", i + 1)) {
    const b = row.slice(i, matchBrace(row, i + "TextButton ".length) + 1);
    buttons.push({ visible: key(b, "visible") ?? "true", label: key(b, "label"), pressed: key(b, "onPressed") });
  }
  const shown = (tonight, ready) => {
    const scope = { updatesGroup: { tonight, ready }, Updates: { restarting: false, restartWarning: "", tonightSet: tonight } };
    const ev = e => inScope(scope, "", `return (${e});`)();
    if (!ev(key(row, "visible"))) return [];
    return buttons.filter(b => ev(b.visible)).map(b => ({ label: ev(b.label), pressed: b.pressed }));
  };
  const words = list => JSON.stringify(list.map(b => b.label));
  const set = shown(true, true), waiting = shown(true, false), none = shown(false, true);
  const cancel = list => list.find(b => /Updates\.cancelTonight\(\)/.test(b.pressed ?? ""));
  check("with Tonight chosen the row has a Cancel that calls Updates.cancelTonight(), and Restart", !!cancel(set) && /^Cancel/.test(cancel(set).label)
    && set.some(b => /Updates\.restartNow\(\)/.test(b.pressed ?? "")), `it shows ${words(set)}`);
  check("Cancel stays while a newer update is still downloading", !!cancel(waiting), `it shows ${words(waiting)}`);
  check("without Tonight there is no Cancel, and Tonight is offered", !cancel(none) && none.some(b => /Updates\.tonight\(\)/.test(b.pressed ?? "")), `it shows ${words(none)}`);
}

done();
