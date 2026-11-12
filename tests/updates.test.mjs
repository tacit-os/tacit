// The updater's reading of pacman (services/Updates.qml): the list read's own handler run under node on pacman's
// output, and the download watch's own command run by bash with a pretend pacman and systemctl first on PATH.
import { execFileSync } from "child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("services/Updates.qml");
// the text of "<key>: ..." first found after "id: <id>"
function after(id, key) {
  const at = src.indexOf(`id: ${id}`);
  const k = src.indexOf(`${key}:`, at);
  return { at: k + key.length + 1 };
}
function handler(id) {
  const open = src.indexOf("{", after(id, "onStreamFinished").at);
  return src.slice(open + 1, matchBrace(src, open));
}

// the Updates singleton as far as the list read touches it
function updates() {
  const root = { available: true, count: 0, downloaded: false, tacitVersion: "", lastCheckFailed: false, fetchFailed: false,
    lastChecked: 0, tonightSet: false, nextNotes: [], phase: "", totalMB: 0, doneMB: 0, progress: 0, quietTicks: 0, asked: false,
    ending: false, announced: [], announce(k) { this.announced.push(k); }, refresh() {} };
  const ready = qmlProperty(src, "ready");
  Object.defineProperty(root, "ready", { get: () => inScope({ root }, "", `return (${ready});`)() });
  const scope = { root, stateFile: { setText() {} }, nextNotesProc: {}, waitingProc: { running: false } };
  const read = inScope(scope, "text", handler("waitingProc"));
  const watch = inScope(scope, "text", handler("watchProc"));
  return { root, read, watch };
}

// pacman -Qu, then -Sup's files, then when the list was fetched, then the night timer: what waitingProc's command prints.
// hyprland is held back (IgnorePkg): pacman -Qu still lists it, with " [ignored]", and -Sup never downloads it.
const QU = "linux 6.17.1.arch1-1 -> 6.17.2.arch1-1\ntacit 1.2.14-2 -> 1.2.15-1\nhyprland 0.57.0-1 -> 0.57.1-1 [ignored]\n";
const listed = `${QU}---\nfile:///var/cache/pacman/pkg/linux-6.17.2.arch1-1-x86_64.pkg.tar.zst\nfile:///var/cache/pacman/pkg/tacit-1.2.15-1-any.pkg.tar.zst\n---\n1762950000\n---\ninactive\n`;

console.log("The updater's reading of pacman (services/Updates.qml)");

// before b1016d5 a held package counted as waiting
{
  const u = updates();
  u.read(listed);
  const r = u.root;
  check("a package held back with IgnorePkg is not counted; the two downloaded are ready, Tacit 1.2.15 among them",
    r.count === 2 && r.downloaded && r.ready && r.tacitVersion === "1.2.15" && r.announced.length === 1,
    `count ${r.count}, downloaded ${r.downloaded}, ready ${r.ready}, tacit "${r.tacitVersion}"`);
}

// the download watch's own command, with pacman and systemctl answering as they would mid-download
{
  const bin = mkdtempSync(join(tmpdir(), "tacit-updates-"));
  try {
    writeFileSync(join(bin, "pacman"), `#!/bin/bash
case "$*" in
  -Qu) printf '%s' '${QU}' ;;
  "-Sup --print-format %s %l") printf '%s\\n' ':: Synchronizing package databases...' '150000000 https://mirror.example/linux-6.17.2.arch1-1-x86_64.pkg.tar.zst' '9000000 file:///var/cache/pacman/pkg/tacit-1.2.15-1-any.pkg.tar.zst' ;;
  *) exit 1 ;;
esac
`);
    writeFileSync(join(bin, "systemctl"), `#!/bin/bash
case "$1" in
  is-active) shift; for u; do [ "$u" = tacit-fetch-updates-now.service ] && echo activating || echo inactive; done ;;
  show) echo success ;;
esac
`);
    chmodSync(join(bin, "pacman"), 0o755);
    chmodSync(join(bin, "systemctl"), 0o755);
    const cmd = inScope({ full: true }, "", `return (${readExpression(src, after("watchProc", "command").at).expr});`)();
    const out = execFileSync(cmd[0], cmd.slice(1), { encoding: "utf8", env: { ...process.env, PATH: `${bin}:${process.env.PATH}` } });
    const u = updates();
    u.watch(out);
    const r = u.root;
    check("the download watch counts 2 waiting, not the held one, and 9 of 159 MB here",
      r.count === 2 && r.phase === "downloading" && r.doneMB === 9 && r.totalMB === 159,
      `count ${r.count}, phase "${r.phase}", ${r.doneMB} of ${r.totalMB} MB (the command printed: ${JSON.stringify(out.split("\n").find(l => l.startsWith("waiting")))})`);
  } finally {
    rmSync(bin, { recursive: true, force: true });
  }
}

// before 7c58cc0 every later read copied a failed check back, and Settings said it failed for good
{
  const u = updates();
  u.root.fetchFailed = true;           // a check asked for offline: its download failed
  u.read(listed);
  const first = u.root.lastCheckFailed;
  u.read(listed);                      // the half-hourly read, later, with the update downloaded since
  check("a failed check is said by the read that ends it, and the next read no longer says it",
    first === true && u.root.lastCheckFailed === false, `first read ${first}, next read ${u.root.lastCheckFailed}`);
}

// after an install: until the first read, Settings shows the updates.json the start before the install wrote
{
  const timers = [];
  for (let at = src.indexOf("Timer {"); at >= 0; at = src.indexOf("Timer {", at + 1)) {
    const open = src.indexOf("{", at), body = src.slice(open + 1, matchBrace(src, open));
    const prop = k => (body.match(new RegExp(`\\b${k}:\\s*([^\\n]+)`)) ?? [])[1]?.trim();
    timers.push({ interval: inScope({}, "", `return (${prop("interval")});`)(), running: prop("running"),
      refreshes: /root\.refresh\(\)/.test(body) });
  }
  const first = Math.min(...timers.filter(t => t.running === "Config.ready" && t.refreshes).map(t => t.interval));
  check("the first read comes within seconds of the shell's start", first <= 10000, `after ${first / 1000} s`);
  const u = updates();
  let written = null;
  const scope = { root: u.root, stateFile: { setText(t) { written = JSON.parse(t); } }, nextNotesProc: {}, waitingProc: { running: false } };
  inScope(scope, "text", handler("waitingProc"))("---\n---\n1762950000\n---\ninactive\n");   // nothing waits any more
  check("and it rewrites updates.json: nothing ready", written?.ready === false && written?.count === 0, JSON.stringify(written));
}

done();
