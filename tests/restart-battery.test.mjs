// Restart for an update on a nearly flat battery: session/updates/tacit-update now under bash (its system paths moved into
// a folder of its own, a pretend /sys/class/power_supply, systemctl and pacman), then what Updates.qml's restartProc
// makes of the refusal (its onExited, with failureCause) and the words Settings > About > Updates' row shows for it.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("Restart on a battery under 20 % (tacit-update now, Updates.qml, Settings' row)");

const dir = mkdtempSync(join(tmpdir(), "tacit-restart-battery-"));
let refusal = "";
try {
  const bin = join(dir, "bin"), state = join(dir, "state"), power = join(dir, "power"), log = join(dir, "calls"), link = join(dir, "system-update");
  for (const d of [bin, state]) mkdirSync(d);
  writeFileSync(join(dir, "tacit-update"), read("session/updates/tacit-update")
    .replaceAll("/var/lib/tacit", state).replaceAll("/var/lib/pacman/db.lck", join(dir, "db.lck"))
    .replaceAll("/system-update", link).replaceAll("/sys/class/power_supply", power));
  for (const t of ["systemctl", "pacman"]) {
    writeFileSync(join(bin, t), `#!/bin/bash\necho "${t} $*" >> "${log}"\nexit 0\n`);
    chmodSync(join(bin, t), 0o755);
  }
  // supplies: { name: { type, capacity, online, scope } }
  const now = supplies => {
    rmSync(power, { recursive: true, force: true });
    mkdirSync(power);
    for (const [name, p] of Object.entries(supplies)) {
      mkdirSync(join(power, name));
      for (const [k, v] of Object.entries(p)) writeFileSync(join(power, name, k), `${v}\n`);
    }
    writeFileSync(log, "");
    rmSync(link, { force: true });
    rmSync(join(state, "download.log"), { force: true });
    let code = 0;
    try {
      execFileSync("bash", [join(dir, "tacit-update"), "now"], { stdio: "pipe", env: { ...process.env, PATH: `${bin}:${process.env.PATH}` } });
    } catch (e) {
      code = e.status;
    }
    const f = join(state, "download.log");
    return { code, linked: existsSync(link), calls: readFileSync(log, "utf8").trim().split("\n").filter(Boolean),
      said: existsSync(f) ? readFileSync(f, "utf8") : "" };
  };
  const line = r => `exit ${r.code}, ${r.linked ? "linked" : "not linked"}, asked ${JSON.stringify(r.calls)}, download.log ${JSON.stringify(r.said)}`;
  const bat = capacity => ({ type: "Battery", capacity }), ac = online => ({ type: "Mains", online });

  const low = now({ BAT0: bat(12), AC: ac(0) });
  refusal = low.said;
  check("at 12 % on battery Restart is refused before anything downloads, and the level is written for the shell",
    low.code === 1 && !low.linked && !low.calls.some(c => c.startsWith("pacman")) && /^tacit: battery 12$/m.test(low.said), line(low));
  for (const [name, supplies] of [
    ["at 12 % plugged in", { BAT0: bat(12), AC: ac(1) }],
    ["at 12 % on a USB-C charger", { BAT0: bat(12), ucsi: { type: "USB", online: 1 } }],
    ["at 20 % on battery", { BAT0: bat(20), AC: ac(0) }],
    ["on a computer without a battery", { AC: ac(1) }],
    ["with only a wireless mouse's battery low", { BAT0: bat(80), AC: ac(0), mouse: { type: "Battery", capacity: 5, scope: "Device" } }],
  ]) {
    const r = now(supplies);
    check(`${name} it goes ahead`, r.code === 0 && r.linked && r.calls.some(c => c.startsWith("pacman -Suw")), line(r));
  }
  const two = now({ BAT0: bat(60), BAT1: bat(15), AC: ac(0) });
  check("with two batteries the lower one counts, as tacit-fetch-updates reads it", two.code === 1 && /battery 15/.test(two.said), line(two));
} finally {
  rmSync(dir, { recursive: true, force: true });
}

// ---- what the shell makes of it: the notch and Settings say why, with the level
{
  const src = read("services/Updates.qml");
  const at = src.indexOf("id: restartProc");
  const procAt = src.lastIndexOf("Process {", at);
  const proc = src.slice(procAt, matchBrace(src, procAt + "Process ".length) + 1);
  const exited = readExpression(proc, proc.indexOf("onExited:") + "onExited:".length).expr;
  const cause = qmlFunction(src, "failureCause");
  const outcome = (code, text) => {
    const root = { restartFailed: "", restartCause: "", restartBattery: 0 }, said = [];
    root.failureCause = inScope({ root }, cause.params.replace(/:\s*\w+/g, ""), cause.body);
    inScope({ root, restartOut: { text }, IslandController: { request: (n, d) => said.push(d.text) } }, "", `return (${exited});`)()(code, 0);
    return { ...root, said };
  };
  const r = outcome(1, refusal || "tacit: battery 12\n");
  check("the notch says to plug in, with the level", r.said.join() === "Plug in to restart: the battery is at 12%", JSON.stringify(r.said));
  check("and the restart is marked refused for the battery", r.restartFailed === "battery" && r.restartBattery === 12,
    `restartFailed ${JSON.stringify(r.restartFailed)}, restartBattery ${r.restartBattery}`);
  const off = outcome(1, "error: failed retrieving file 'qt6-base.pkg.tar.zst'\n");
  check("a download that failed is still said as one", off.restartFailed === "prepare" && /^Couldn't download the update · check the connection$/.test(off.said.join()), JSON.stringify(off));

  const settings = read("tacit-settings.qml");
  const rowAt = settings.indexOf('glyph: "system_update"');
  const descAt = settings.indexOf("description:", rowAt);
  const desc = readExpression(settings, descAt + "description:".length).expr;
  const groupAt = settings.indexOf("id: updatesGroup");
  const causeLine = qmlFunction(settings.slice(groupAt), "causeLine");
  const updatesGroup = { restartFailed: r.restartFailed, restarting: false, tonight: false, ready: true, waiting: 3, checkedText: "" };
  updatesGroup.causeLine = inScope({}, causeLine.params, causeLine.body);
  const words = inScope({ updatesGroup, Updates: { phase: "", lastCheckFailed: false, restartWarning: "", restartBattery: r.restartBattery, restartCause: r.restartCause, nightSkipped: "" } },
    "", `return (${desc});`)();
  check("Settings' row says the same", words === "Plug in to restart: the battery is at 12%", JSON.stringify(words));
}

done();
