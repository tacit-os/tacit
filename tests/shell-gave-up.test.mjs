// What qs-supervise says on screen once the shell has died five times in a row (bin/qs-supervise): Hyprland and every
// window are still up, so the way back that keeps them, Ctrl+Super+R (keybinds.lua), must be in the notification, not
// only in ~/.cache/qs-crashloop.txt. The script runs under bash in a home of its own with a pretend qs that dies at once,
// a sleep that does not wait, a pgrep that finds no shell to stop, and a hyprctl and notify-send that write down what
// they were asked to show.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== the shell that could not restart itself says how to get it back (bin/qs-supervise)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-gave-up-"));
const bin = join(tmp, "bin"), home = join(tmp, "home"), run = join(tmp, "run"), calls = join(tmp, "calls");
for (const d of [bin, home, run]) mkdirSync(d);
const stub = (name, body) => { writeFileSync(join(bin, name), `#!/bin/bash\n${body}\n`); chmodSync(join(bin, name), 0o755); };
stub("qs", "exit 1");
stub("sleep", "exit 0");
stub("pgrep", "exit 1");
stub("hyprctl", `printf 'hyprctl %s\\n' "$*" >> "$CALLS"`);
stub("notify-send", `printf 'notify-send %s\\n' "$*" >> "$CALLS"`);

try {
  let rc = 0;
  try {
    execFileSync("bash", [join(tree, "bin/qs-supervise")], { encoding: "utf8", timeout: 20000,
      env: { PATH: `${bin}:${process.env.PATH}`, HOME: home, XDG_RUNTIME_DIR: run, TACIT_SHELL: join(tmp, "shell"),
        qsConfig: "tacit-test-gave-up", CALLS: calls } });
  } catch (e) { rc = e.status; }
  const said = existsSync(calls) ? readFileSync(calls, "utf8").trim().split("\n") : [];
  const hypr = said.find(l => l.startsWith("hyprctl notify")) ?? "", note = said.find(l => l.startsWith("notify-send")) ?? "";
  check("it gives up after the crashes, and both notifiers are asked", rc === 1 && hypr !== "" && note !== "",
    `exit ${rc}, ${JSON.stringify(said)}`);
  for (const [who, line] of [["Hyprland's notice", hypr], ["the notification", note]]) {
    check(`${who} names Ctrl+Super+R`, /Ctrl\+Super\+R/.test(line), line);
    check(`${who} says the windows are still open`, /windows are still open/.test(line), line);
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
