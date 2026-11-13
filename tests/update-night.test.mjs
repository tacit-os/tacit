// Tonight (session/updates/tacit-update tonight, night, and pre/post, the sleep hook): the script itself under bash, its
// system paths moved into a folder of its own, with a pretend clock, logind, pgrep, systemctl and pacman first on PATH
// and a pretend /sys/class/power_supply. What the night wrote (/var/lib/tacit/night) and what it asked of systemd are read.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, read } from "./lib/check.mjs";

const src = read("session/updates/tacit-update");

console.log("Tonight (session/updates/tacit-update tonight, night, pre and post)");

const dir = mkdtempSync(join(tmpdir(), "tacit-night-"));
try {
  const bin = join(dir, "bin"), state = join(dir, "state"), power = join(dir, "power"), run = join(dir, "run");
  for (const d of [bin, state, power, run]) mkdirSync(d);
  const log = join(dir, "calls");
  const script = src
    .replaceAll("/var/lib/tacit", state)
    .replaceAll("/var/lib/pacman/db.lck", join(dir, "db.lck"))
    .replaceAll("/system-update", join(dir, "system-update"))
    .replaceAll("/run/tacit-update-held", join(dir, "held"))
    .replaceAll("/sys/class/power_supply", power);
  writeFileSync(join(dir, "tacit-update"), script);
  const tool = (name, body) => { writeFileSync(join(bin, name), `#!/bin/bash\n${body}\n`); chmodSync(join(bin, name), 0o755); };
  // the clock: "now" is NOW, everything else the real date works out from it
  tool("date", `[ "$*" = "+%s" ] && { echo "$NOW"; exit 0; }\nexec /usr/bin/date "$@"`);
  // one person's session, as the case sets it
  tool("loginctl", `case "$1" in
  list-sessions) echo "  2 1000 someone seat0 tty2" ;;
  show-session) case "$4" in Class) echo user ;; Active) echo yes ;; Type) echo wayland ;; User) echo 1000 ;; LockedHint) echo "$LOCKED" ;; esac ;;
  show-user) echo "${run}" ;;
esac`);
  tool("pgrep", `case "$*" in *hyprlock*) [ "$HYPRLOCK" = 1 ] ;; *bootlock*) [ "$BOOTLOCK" = 1 ] ;; *) exit 1 ;; esac`);
  tool("systemctl", `echo "systemctl $*" >> "${log}"\n[ "$*" = "-q is-active tacit-update-night.timer" ] && { [ "$TIMER" = active ]; exit; }\nexit 0`);
  tool("pacman", `echo "pacman $*" >> "${log}"\n[ "$1" = -Suw ] && [ "$OFFLINE" = 1 ] && exit 1\nexit 0`);

  const at = (h, m, day = 14) => String(Date.UTC(2026, 10, day, h, m, 20) / 1000);
  const plug = on => {
    rmSync(power, { recursive: true, force: true });
    mkdirSync(join(power, "BAT0"), { recursive: true });
    mkdirSync(join(power, "AC"));
    writeFileSync(join(power, "BAT0", "type"), "Battery\n");
    writeFileSync(join(power, "AC", "type"), "Mains\n");
    writeFileSync(join(power, "AC", "online"), on ? "1\n" : "0\n");
  };
  function night(c) {
    writeFileSync(log, "");
    rmSync(join(state, "night"), { force: true });
    rmSync(join(run, "tacit-caffeine"), { force: true });
    if (c.caffeine) writeFileSync(join(run, "tacit-caffeine"), "");
    plug(c.charger ?? true);
    let code = 0;
    try {
      execFileSync("bash", [join(dir, "tacit-update"), c.cmd ?? "night"], { stdio: "pipe", env: { ...process.env, TZ: "UTC", PATH: `${bin}:${process.env.PATH}`,
        NOW: c.now ?? at(3, 0), LOCKED: c.locked ?? "yes", HYPRLOCK: c.hyprlock ? "1" : "0", BOOTLOCK: c.bootlock ? "1" : "0",
        TIMER: c.timer ?? "active", OFFLINE: c.offline ? "1" : "0" } });
    } catch (e) {
      code = e.status;
    }
    const f = join(state, "night");
    return { code, calls: readFileSync(log, "utf8").trim().split("\n").filter(Boolean),
      said: existsSync(f) ? JSON.parse(readFileSync(f, "utf8")) : null };
  }
  const restarted = r => r.calls.includes("systemctl reboot");
  const line = r => `exit ${r.code}, wrote ${JSON.stringify(r.said)}, asked ${JSON.stringify(r.calls)}`;

  // a night that goes ahead: it says so before the download, and restarts
  {
    const r = night({});
    check("at 03:00 on the charger with Tacit's lock up it installs, and says it went ahead", restarted(r) && r.said?.skipped === "" && r.said?.at === +at(3, 0), line(r));
  }
  // each skip says why, and none restarts
  for (const [name, c, why] of [
    ["on battery", { charger: false }, "battery"],
    ["with the screen not locked", { locked: "no" }, "unlocked"],
    ["with Caffeine on, even locked", { caffeine: true }, "caffeine"],
    ["woken at 08:15 (the timer came due while it slept)", { now: at(8, 15) }, "asleep"],
    ["at 02:10 two days on (the same)", { now: at(2, 10, 16) }, "asleep"],
  ]) {
    const r = night(c);
    check(`${name}: no restart, and the night says "${why}"`, !restarted(r) && r.code === 0 && r.said?.skipped === why, line(r));
  }
  // hyprlock and the boot lock are locks too: nobody is there
  for (const [name, c] of [["hyprlock", { locked: "no", hyprlock: true }], ["the boot lock", { locked: "no", bootlock: true }]]) {
    const r = night(c);
    check(`${name} up, which tells logind nothing: it installs`, restarted(r) && r.said?.skipped === "", line(r));
  }
  // offline at three: said, the timer kept for the next night
  {
    const r = night({ offline: true });
    check("a download that fails says so, restarts nothing and keeps the timer", r.code === 1 && r.said?.skipped === "download" && !restarted(r)
      && !r.calls.some(l => l.includes("disable")), line(r));
  }
  // Tonight notes when it was chosen, and fails as the timer does
  {
    const r = night({ cmd: "tonight" });
    check("Tonight enables the timer and notes when it was chosen", r.code === 0 && r.calls.includes("systemctl enable --now tacit-update-night.timer")
      && existsSync(join(state, "tonight")), line(r));
  }
  // the sleep hook: asleep on battery the timer never wakes the computer; started again on waking
  {
    rmSync(join(dir, "held"), { force: true });
    const pre = night({ cmd: "pre", charger: false, now: at(23, 30, 13) });
    const held = existsSync(join(dir, "held")) ? readFileSync(join(dir, "held"), "utf8").trim() : "";
    const post = night({ cmd: "post", charger: true, now: at(7, 40) });
    check("going to sleep on battery stops the timer until three o'clock is past; waking starts it and says the night was on battery",
      pre.calls.includes("systemctl stop tacit-update-night.timer") && held === String(Date.UTC(2026, 10, 14, 3, 0, 0) / 1000)
        && post.calls.includes("systemctl start --no-block tacit-update-night.timer") && post.said?.skipped === "battery" && !existsSync(join(dir, "held")),
      `held ${JSON.stringify(held)}; ${line(pre)}; then ${line(post)}`);
    night({ cmd: "pre", charger: false, now: at(23, 30, 13) });
    const early = night({ cmd: "post", now: at(1, 0) });
    check("woken before three: the timer is started again and nothing is said", early.calls.includes("systemctl start --no-block tacit-update-night.timer") && early.said === null, line(early));
    const plugged = night({ cmd: "pre", charger: true, now: at(23, 30, 13) });
    const idle = night({ cmd: "pre", charger: false, timer: "inactive", now: at(23, 30, 13) });
    check("on the charger, or with no Tonight, sleep leaves the timer alone", !plugged.calls.some(l => l.includes("stop")) && !idle.calls.some(l => l.includes("stop"))
      && !existsSync(join(dir, "held")), `${line(plugged)}; ${line(idle)}`);
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}

done();
