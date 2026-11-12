// The install at the start (session/updates/tacit-update install, what tacit-system-update.service runs): the script
// itself under bash, with its system paths moved into a folder of its own and a pretend pacman and systemctl first on
// PATH. The console is a file there, so what the screen would say, and when, can be read.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, read } from "./lib/check.mjs";

const src = read("session/updates/tacit-update");

console.log("The install at the start (session/updates/tacit-update install)");

const dir = mkdtempSync(join(tmpdir(), "tacit-update-"));
try {
  const bin = join(dir, "bin"), state = join(dir, "state");
  mkdirSync(bin);
  const at = { console: join(dir, "console"), log: join(dir, "calls") };
  writeFileSync(at.console, "");
  const script = src
    .replaceAll("/var/lib/tacit", state)
    .replaceAll("/var/lib/pacman/db.lck", join(dir, "db.lck"))
    .replaceAll("/system-update", join(dir, "system-update"))
    .replaceAll("/dev/console", at.console);
  writeFileSync(join(dir, "tacit-update"), script);
  writeFileSync(join(dir, "system-update"), "");
  // pacman -Su notes what the console said when the install began; the versions change, as an install's do
  writeFileSync(join(bin, "pacman"), `#!/bin/bash
case "$1" in
  -Q) [ -e "${dir}/installed" ] && echo "tacit 1.2.16-1" || echo "tacit 1.2.15-1" ;;
  -Su) printf 'pacman -Su, the console saying: %s\\n' "$(tr '\\n' ' ' < "${at.console}")" >> "${at.log}"; touch "${dir}/installed" ;;
  -Sc) ;;
esac
`);
  writeFileSync(join(bin, "systemctl"), `#!/bin/bash\necho "systemctl $*" >> "${at.log}"\n`);
  chmodSync(join(bin, "pacman"), 0o755);
  chmodSync(join(bin, "systemctl"), 0o755);
  execFileSync("bash", [join(dir, "tacit-update"), "install"], { env: { ...process.env, PATH: `${bin}:${process.env.PATH}` } });

  const calls = readFileSync(at.log, "utf8").trim().split("\n");
  const su = calls.find(l => l.startsWith("pacman -Su")) ?? "";
  check("the screen says updates are being installed before pacman starts on them",
    /Installing updates/.test(su), su ? `when pacman -Su ran the console said: "${su.replace(/^.*saying: /, "").trim()}"` : "pacman -Su never ran");
  check("in plain ASCII, which the console's own font draws", /^[\x00-\x7f]*$/.test(readFileSync(at.console, "utf8")),
    JSON.stringify(readFileSync(at.console, "utf8")));
  const result = existsSync(join(state, "update-result")) ? JSON.parse(readFileSync(join(state, "update-result"), "utf8")) : {};
  check("the install itself goes on as before: the result written, the link gone, and the restart at the end",
    result.ok === true && result.version === "1.2.16-1" && !existsSync(join(dir, "system-update")) && calls.at(-1) === "systemctl reboot",
    `result ${JSON.stringify(result)}, last call "${calls.at(-1)}"`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}

done();
