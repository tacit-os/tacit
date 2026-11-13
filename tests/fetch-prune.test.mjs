// The cache clean-up after the background download (session/updates/tacit-fetch-updates): the script itself under bash,
// its system paths moved into a folder of its own (pacman's lock, the package cache, /var/lib/tacit, the power supplies),
// with a pretend pacman, nmcli and systemctl first on PATH. The pretend pacman -Q, which the prune calls, is also a
// second pacman starting at that moment: it tries pacman's lock as libalpm does (made only if there is none) and notes
// whether it got it. An install from Apps can start as the download ends: it takes the lock and puts its package in the
// cache, as pacman -S does, and holds it a few seconds.
import { execFileSync, spawn } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, read } from "./lib/check.mjs";

const src = read("session/updates/tacit-fetch-updates");

console.log("The cache clean-up after the background download (session/updates/tacit-fetch-updates)");

const dir = mkdtempSync(join(tmpdir(), "tacit-fetch-"));
const lock = join(dir, "db.lck"), cache = join(dir, "cache"), probe = join(dir, "probe");
const bin = join(dir, "bin"), power = join(dir, "power");
try {
  for (const d of [bin, cache, join(power, "AC")]) mkdirSync(d, { recursive: true });
  writeFileSync(join(power, "AC", "type"), "Mains\n");
  writeFileSync(join(power, "AC", "online"), "1\n");
  writeFileSync(join(dir, "tacit-fetch-updates"), src
    .replaceAll("/var/lib/pacman/db.lck", lock)
    .replaceAll("/var/cache/pacman/pkg", cache)
    .replaceAll("/var/lib/tacit", join(dir, "state"))
    .replaceAll("/sys/class/power_supply", power));
  const tool = (name, body) => { writeFileSync(join(bin, name), `#!/bin/bash\n${body}\n`); chmodSync(join(bin, name), 0o755); };
  tool("nmcli", "exit 0");
  tool("systemctl", "exit 0");
  const app = join(cache, "app-1.0-1-x86_64.pkg.tar.zst");
  tool("pacman", `case "$1" in
  -Syuw)
    # Apps' install, starting as the download lets go of the lock: it holds the lock, its package lands in the cache
    if [ "$APPS" = 1 ]; then
      bash -c 'set -C; exec 9> "$1" || exit 1; : > "$2"; touch "$3"; sleep 4; rm -f "$1"' _ "${lock}" "${app}" "${dir}/apps-ready" >/dev/null 2>&1 &
      for _ in $(seq 100); do [ -e "${dir}/apps-ready" ] && break; sleep 0.05; done
    fi ;;
  -Sup) echo linux-6.17.2-1-x86_64.pkg.tar.zst ;;
  -Q)
    if ( set -C; : > "${lock}" ) 2>/dev/null; then rm -f "${lock}"; echo free >> "${probe}"; else echo held >> "${probe}"; fi
    [ "$SLOW" = 1 ] && { touch "${dir}/in-prune"; sleep 5; }
    printf '%s\\n' 'linux 6.17.1-1' 'tacit 1.2.15-1' ;;
esac
exit 0`);

  const files = ["linux-6.17.0-1-x86_64.pkg.tar.zst", "linux-6.17.0-1-x86_64.pkg.tar.zst.sig", "linux-6.17.1-1-x86_64.pkg.tar.zst",
    "linux-6.17.2-1-x86_64.pkg.tar.zst", "tacit-1.2.15-1-any.pkg.tar.zst"];
  const setUp = () => {
    for (const f of readdirSync(cache)) rmSync(join(cache, f));
    for (const f of files) writeFileSync(join(cache, f), "");
    for (const f of [probe, lock, join(dir, "apps-ready"), join(dir, "in-prune")]) rmSync(f, { force: true });
  };
  const env = extra => ({ ...process.env, PATH: `${bin}:${process.env.PATH}`, APPS: "0", SLOW: "0", ...extra });
  const left = () => readdirSync(cache).sort();
  const said = () => (existsSync(probe) ? readFileSync(probe, "utf8").trim() : "");

  // nobody else at work: the superseded version goes, the waiting and the installed ones stay, and no lock is left
  setUp();
  execFileSync("bash", [join(dir, "tacit-fetch-updates")], { env: env(), stdio: "pipe" });
  check("the clean-up still takes out only the superseded version and its signature",
    JSON.stringify(left()) === JSON.stringify(files.slice(2).sort()), `left ${JSON.stringify(left())}`);
  check("a pacman starting during the clean-up finds the lock held, and none is left after it", said() === "held" && !existsSync(lock),
    `the second pacman found the lock ${said() || "(never asked)"}; ${existsSync(lock) ? "a lock is left" : "no lock left"}`);

  // an install from Apps that started as the download ended: its package is neither installed nor waiting
  setUp();
  execFileSync("bash", [join(dir, "tacit-fetch-updates")], { env: env({ APPS: "1" }), stdio: "pipe" });
  check("an app's package downloaded by Apps meanwhile is left alone, and so is Apps' lock",
    existsSync(app) && existsSync(lock), `${existsSync(app) ? "the package is there" : "the package was deleted"}, ${existsSync(lock) ? "Apps' lock is there" : "Apps' lock is gone"}`);
  for (let i = 0; i < 100 && existsSync(lock); i++) execFileSync("sleep", ["0.05"]);

  // stopped in the middle of the clean-up (a restart, Settings' own check): SIGINT to the unit's processes
  setUp();
  const code = await new Promise(res => {
    const p = spawn("bash", [join(dir, "tacit-fetch-updates")], { env: env({ SLOW: "1" }), stdio: "ignore", detached: true });
    const t = setInterval(() => { if (existsSync(join(dir, "in-prune"))) { clearInterval(t); process.kill(-p.pid, "SIGINT"); } }, 50);
    p.on("exit", (c, s) => { clearInterval(t); res(s || c); });
    setTimeout(() => { clearInterval(t); try { process.kill(-p.pid, "SIGKILL"); } catch {} }, 15000);
  });
  check("stopped during the clean-up, it leaves no lock behind", !existsSync(lock), `ended ${code}, the lock is still there`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}

done();
