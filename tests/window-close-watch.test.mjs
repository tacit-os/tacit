// What is said after Super+Q (bin/window-close-watch): only a window really still there is offered Force quit, and the
// note goes when the window does. The script runs under sh with a pretend hyprctl whose windows change with a pretend
// clock (sleep moves it on), a notify-send that writes down what it was asked and answers or waits to be closed, and a
// gdbus that writes down the close. The app is a real sleep process, so Force quit can be seen to stop it.
import { execFileSync, spawn } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== what Super+Q says when a window has not closed (bin/window-close-watch)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-close-watch-"));
const bin = join(tmp, "bin");
mkdirSync(bin);
const stub = (name, body) => { writeFileSync(join(bin, name), `#!/bin/bash\n${body}\n`); chmodSync(join(bin, name), 0o755); };
// the windows at a time: clients-<t> of the largest t not after the clock
stub("hyprctl", `t=$(cat "$DIR/t"); b=0; for f in "$DIR"/clients-*; do n=\${f##*-}; [ "$n" -le "$t" ] && [ "$n" -ge "$b" ] && b=$n; done; cat "$DIR/clients-$b"`);
stub("sleep", `echo $(( $(cat "$DIR/t") + \${1%.*} )) > "$DIR/t"`);
stub("notify-send", `printf '%s\\n' "$*" >> "$DIR/notes"; [[ " $* " == *" -p "* ]] && echo 41
[ -n "$ANSWER" ] && { echo "$ANSWER"; exit 0; }
for i in $(seq 100); do [ -e "$DIR/closed" ] && exit 0; /usr/bin/sleep 0.05; done`);
stub("gdbus", `printf '%s\\n' "$*" >> "$DIR/closes"; touch "$DIR/closed"`);

const app = spawn("sleep", ["60"], { detached: true, stdio: "ignore" });
const win = (addr, pid, stableId, more = {}) => ({ address: addr, pid, stableId, mapped: true, class: "Discord", ...more });
const other = win("0xbbb2", 99999, "2000", { class: "foot" });

// states: { time: [windows] }; returns what was said and closed
function run(name, states, answer = "") {
  const dir = join(tmp, name);
  mkdirSync(dir);
  writeFileSync(join(dir, "t"), "0");
  for (const [t, list] of Object.entries(states)) writeFileSync(join(dir, `clients-${t}`), JSON.stringify(list));
  execFileSync("sh", [join(tree, "bin/window-close-watch"), "0xaaa1", String(app.pid), "Discord"], { encoding: "utf8", timeout: 20000,
    env: { PATH: `${bin}:${process.env.PATH}`, DIR: dir, ANSWER: answer } });
  const lines = f => existsSync(join(dir, f)) ? readFileSync(join(dir, f), "utf8").trim().split("\n") : [];
  return { notes: lines("notes"), closes: lines("closes") };
}

try {
  const main = win("0xaaa1", app.pid, "1000");
  let r = run("closed", { 0: [main, other], 1: [other] });
  check("a window that closed says nothing", r.notes.length === 0, JSON.stringify(r.notes));

  r = run("reused", { 0: [main, other], 1: [other, win("0xaaa1", 99998, "1001", { class: "Files" })] });
  check("its address taken by another app's new window says nothing", r.notes.length === 0, JSON.stringify(r.notes));

  r = run("reopened", { 0: [main, other], 1: [other, win("0xaaa1", app.pid, "1002")] });
  check("its address taken by the same app's next window says nothing", r.notes.length === 0, JSON.stringify(r.notes));

  r = run("asking", { 0: [main, win("0xaaa3", app.pid, "1003")], 1: [main, win("0xaaa3", app.pid, "1003"), win("0xaaa4", app.pid, "1004", { title: "Save changes?" })] });
  check("an app asking in a window of its own (Save changes?) says nothing", r.notes.length === 0, JSON.stringify(r.notes));

  r = run("late", { 0: [main, other], 8: [other] });
  check("a window still there after six seconds is said to be open, not to have failed",
    r.notes.length === 1 && /Discord is still open/.test(r.notes[0]) && !/did not close/.test(r.notes[0]), JSON.stringify(r.notes));
  check("and the note goes when it closes after all", r.closes.length === 1 && /CloseNotification 41$/.test(r.closes[0]), JSON.stringify(r.closes));

  r = run("stuck", { 0: [main, other] }, "kill");
  let gone = false;
  // stopped and not yet reaped by node (whose loop is not running here) is a zombie
  for (let i = 0; i < 40 && !gone; i++) {
    gone = !existsSync(`/proc/${app.pid}`) || readFileSync(`/proc/${app.pid}/stat`, "utf8").split(") ")[1][0] === "Z";
    if (!gone) execFileSync("/usr/bin/sleep", ["0.05"]);
  }
  check("a window that stays is offered Force quit, which stops the app", r.notes.length === 1 && /Force quit/.test(r.notes[0]) && gone,
    `${JSON.stringify(r.notes)}, stopped ${gone}`);
} finally {
  try { process.kill(app.pid, "SIGKILL"); } catch {}
  rmSync(tmp, { recursive: true, force: true });
}
done();
