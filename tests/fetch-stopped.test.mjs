// A download stopped halfway (session/updates/tacit-fetch-updates): a shutdown or a restart stops the unit with SIGINT
// to each of its processes (KillSignal=SIGINT), and pacman lets go of its lock on SIGINT. The script runs under bash,
// its system paths moved into a folder of its own, with a pretend pacman first on PATH that works as pacman 7.1.0 does
// (src/pacman/sighandler.c, sync.c): it holds the lock, and on SIGINT says so on stderr and lets the transaction end,
// then prints its errors and lets go of the lock; SIGPIPE is left as it comes, as pacman leaves it.
import { spawn } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, read } from "./lib/check.mjs";

const src = read("session/updates/tacit-fetch-updates");

console.log("A download stopped halfway (session/updates/tacit-fetch-updates)");

const dir = mkdtempSync(join(tmpdir(), "tacit-fetch-stopped-"));
const lock = join(dir, "db.lck"), bin = join(dir, "bin"), power = join(dir, "power"), state = join(dir, "state");
const started = join(dir, "started");
try {
  for (const d of [bin, join(dir, "cache"), join(power, "AC")]) mkdirSync(d, { recursive: true });
  writeFileSync(join(power, "AC", "type"), "Mains\n");
  writeFileSync(join(power, "AC", "online"), "1\n");
  writeFileSync(join(dir, "tacit-fetch-updates"), src
    .replaceAll("/var/lib/pacman/db.lck", lock)
    .replaceAll("/var/cache/pacman/pkg", join(dir, "cache"))
    .replaceAll("/var/lib/tacit", state)
    .replaceAll("/sys/class/power_supply", power));
  const tool = (name, body) => { writeFileSync(join(bin, name), `#!/bin/bash\n${body}\n`); chmodSync(join(bin, name), 0o755); };
  tool("nmcli", "exit 0");
  tool("systemctl", "exit 0");
  tool("pacman", `[ "$1" = -Syuw ] || exit 0
( set -C; : > "${lock}" ) 2>/dev/null || exit 1
stop=
trap 'echo "Interrupt signal received" >&2; stop=1' INT
touch "${started}"
while [ -z "$stop" ]; do echo "downloading..."; sleep 0.05; done
sleep 0.3
echo "error: failed to commit transaction (failed to retrieve some files)" >&2
rm -f "${lock}"
exit 1`);

  // stopped as systemd stops the unit: SIGINT to every process in it (here its process group)
  const stopped = args => new Promise(res => {
    for (const f of [lock, started]) rmSync(f, { force: true });
    const p = spawn("bash", [join(dir, "tacit-fetch-updates"), ...args], {
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}` }, stdio: "ignore", detached: true });
    const t = setInterval(() => { if (existsSync(started)) { clearInterval(t); process.kill(-p.pid, "SIGINT"); } }, 50);
    const kill = setTimeout(() => { clearInterval(t); try { process.kill(-p.pid, "SIGKILL"); } catch {} }, 15000);
    p.on("exit", (c, s) => { clearInterval(t); clearTimeout(kill); res(s || c); });
  });

  const background = await stopped([]);
  check("the background download stopped halfway leaves no pacman lock", !existsSync(lock),
    `ended ${background}, and the lock is still there: the next Get in Apps says another update is running`);
  const now = await stopped(["now"]);
  const log = existsSync(join(state, "fetch.log")) ? readFileSync(join(state, "fetch.log"), "utf8") : "";
  check("Settings' check stopped halfway leaves no lock, and fetch.log keeps pacman's words",
    !existsSync(lock) && log.includes("failed to commit transaction"),
    `ended ${now}, ${existsSync(lock) ? "the lock is still there" : "no lock"}, fetch.log ${JSON.stringify(log)}`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}

done();
