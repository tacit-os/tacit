// The updater's reading of pacman (services/Updates.qml): the list read's own handler run under node on pacman's
// output, and the download watch's own command run by bash with a pretend pacman and systemctl first on PATH. And an
// install made elsewhere (Apps, a terminal): pacman's log changing brings the list read again.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
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
    ending: false, announced: [], announce(k) { this.announced.push(k); }, refresh() {}, nightSkipped: "", said: [],
    say(name, data, mark) { this.said.push({ name, data }); mark(); } };
  const ready = qmlProperty(src, "ready");
  Object.defineProperty(root, "ready", { get: () => inScope({ root }, "", `return (${ready});`)() });
  const words = qmlProperty(src, "nightWords"), last = qmlFunction(src, "lastNight");
  if (words) root.nightWords = inScope({}, "", `return (${words});`)();
  if (last) root.lastNight = inScope({ root }, last.params, last.body);
  let seen = "";
  const scope = { root, stateFile: { setText() {} }, nextNotesProc: {}, waitingProc: { running: false },
    nightSeenFile: { text: () => seen, setText: t => { seen = t; } } };
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

// what stopped a check or a download, from pacman's words (LC_ALL=C), said in Settings' row and the notch's note; every
// failure used to read "Check that this computer is online"
{
  const PACMAN = {
    busy: "error: failed to init transaction (unable to lock database)\nerror: could not lock database: File exists\n",
    offline: ":: Synchronizing package databases...\nerror: failed retrieving file 'core.db' from mirror.example : Could not resolve host: mirror.example\nerror: failed to synchronize all databases (download library error)\n",
    conflict: ":: hyprland-0.57.1-1 and hyprland-git-r1-1 are in conflict. Remove hyprland-git? [y/N]\nerror: unresolvable package conflicts detected\nerror: failed to prepare transaction (conflicting dependencies)\n",
    live: "tacit: live USB\n",
  };
  const f = /function failureCause\(log(?::\s*string)?\)(?::\s*string)?\s*\{/.exec(src);
  const cause = f ? inScope({}, "log", src.slice(f.index + f[0].length, matchBrace(src, f.index + f[0].length - 1))) : () => undefined;
  const got = Object.fromEntries(Object.entries(PACMAN).map(([k, t]) => [k, cause(t)]));
  check("pacman's words name the cause: busy, offline, a conflict, the live USB", Object.entries(got).every(([k, v]) => k === v), JSON.stringify(got));
  check("and words it does not know name none", cause("error: failed to commit transaction (invalid or corrupted package)\n") === "");

  // the watch's own command after a check that failed offline: the unit's result and what fetch.log holds
  const bin = mkdtempSync(join(tmpdir(), "tacit-updates-"));
  try {
    writeFileSync(join(bin, "fetch.log"), PACMAN.offline);
    writeFileSync(join(bin, "systemctl"), "#!/bin/bash\ncase \"$1\" in is-active) for u in \"${@:2}\"; do echo inactive; done ;; show) echo exit-code ;; esac\n");
    writeFileSync(join(bin, "pacman"), "#!/bin/bash\nexit 0\n");
    for (const n of ["systemctl", "pacman"]) chmodSync(join(bin, n), 0o755);
    const cmd = inScope({ full: false }, "", `return (${readExpression(src, after("watchProc", "command").at).expr});`)()
      .map(a => a.replaceAll("/var/lib/tacit/fetch.log", join(bin, "fetch.log")));
    const out = execFileSync(cmd[0], cmd.slice(1), { encoding: "utf8", env: { ...process.env, PATH: `${bin}:${process.env.PATH}` } });
    const u = updates();
    Object.assign(u.root, { asked: true, phase: "looking", quietTicks: 2, failureCause: cause });
    u.watch(out);
    check("a check that failed offline ends failed, with offline as its cause", u.root.fetchFailed === true && u.root.checkCause === "offline",
      `failed ${u.root.fetchFailed}, cause "${u.root.checkCause}"`);
  } finally {
    rmSync(bin, { recursive: true, force: true });
  }

  // Settings' row, its description binding with the check failed for each cause
  const settings = read("tacit-settings.qml");
  const at = settings.indexOf('description: Updates.phase === "looking"');
  const desc = at < 0 ? null : readExpression(settings, at + "description:".length).expr;
  const cl = /function causeLine\(cause\)\s*\{/.exec(settings);
  const causeLine = cl ? inScope({}, "cause", settings.slice(cl.index + cl[0].length, matchBrace(settings, cl.index + cl[0].length - 1))) : null;
  const row = (c, restartFailed = "") => desc && String(inScope({ Updates: { phase: "", lastCheckFailed: restartFailed === "", checkCause: c, restartCause: c, restartWarning: "" },
    updatesGroup: { causeLine, restarting: false, restartFailed, tonight: false, ready: false, waiting: 0, checkedText: "" } }, "", `return (${desc});`)());
  const lines = Object.keys(PACMAN).map(c => row(c));
  check("Settings says each in its own line", new Set(lines).size === 4 && row("offline") === "Check that this computer is online, then try again"
    && /package manager is busy/.test(row("busy")) && /conflict/.test(row("conflict")) && /live USB/.test(row("live")), JSON.stringify(lines));
  check("and the download before a restart the same", row("busy", "prepare") === "Couldn't finish the download · the package manager is busy, try again once it is done",
    row("busy", "prepare"));

  // the notch's note when the download before a restart fails
  const ex = readExpression(src, after("restartProc", "onExited").at).expr;
  const notes = [];
  const exited = inScope({ root: { failureCause: cause, says: true }, restartOut: { text: PACMAN.conflict },
    IslandController: { request: (k, d) => notes.push(d.text) } }, "", `return (${ex});`)();
  exited(1, 0);
  check("the notch says it too", notes[0] === "Couldn't download the update · a conflicting update", JSON.stringify(notes));
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

// Apps' "update everything" or pacman in a terminal: what is waiting is installed with nothing telling the shell, and
// pacman's log is the one thing every transaction writes
{
  const m = /FileView\s*\{[^{}]*path:\s*"\/var\/log\/pacman\.log"/.exec(src);
  const open = m ? src.indexOf("{", m.index) : -1, body = m ? src.slice(open + 1, matchBrace(src, open)) : "";
  const prop = (text, k) => (text.match(new RegExp(`\\b${k}:\\s*([^\\n]+)`)) ?? [])[1]?.trim();
  check("pacman's log is watched, and only watched (not read in)", prop(body, "watchChanges") === "true" && prop(body, "preload") === "false",
    m ? body.trim() : "nothing watches /var/log/pacman.log");
  // the log changing restarts a timer; the timer reads the list again, or waits behind a read already under way
  const timer = /(\w+)\.restart\(\)/.exec(prop(body, "onFileChanged") ?? "")?.[1];
  const at = timer ? src.indexOf(`id: ${timer}`) : -1;
  const fired = at < 0 ? "" : readExpression(src, src.indexOf("onTriggered:", at) + "onTriggered:".length).expr;
  let refreshed = 0, waited = 0;
  const fire = reading => fired && inScope({ root: { refresh() { refreshed++; } }, waitingProc: { running: reading }, fetchProc: { running: false },
    [timer]: { restart() { waited++; } } }, "", `${fired};`)();
  fire(false);
  fire(true);
  check("once the log has been quiet, the list is read again, after any read under way", refreshed === 1 && waited === 1,
    `read ${refreshed} times, waited ${waited} times`);
}

// Restart for an update: the notch said "Getting ready to restart" and nothing of the minutes the install takes at the start
{
  let said = null;
  const f = src.match(/\n    function go\(\) \{/);
  const at = f ? f.index + f[0].length - 1 : -1;
  const scope = { root: { restartWarning: "x", says: true }, disarmTimer: { stop() {} }, restartProc: { running: false },
    IslandController: { request: (name, p) => { said = p; } } };
  if (at >= 0) inScope(scope, "", src.slice(at + 1, matchBrace(src, at)))();
  check("the notch says from the press that the restart takes a few minutes, while it gets ready",
    said?.restarting === true && /^Getting ready to restart · [^·]*a few minutes$/.test(said?.text ?? "") && scope.restartProc.running === true,
    JSON.stringify(said));
}

// Tonight: a night that skipped (on battery, the screen not locked, Caffeine on, switched off) said nothing, and Settings
// went on saying "Tonight, on the charger". The list read gets the night's word, when Tonight was chosen and when this
// start began, after the timer's state.
{
  const now = Date.now(), three = new Date(now);
  three.setHours(3, 0, 0, 0);
  if (three.getTime() > now) three.setDate(three.getDate() - 1);
  const s = t => Math.floor(t / 1000), at = three.getTime(), hour = 3600 * 1000;
  const read = (timer, night, chosen, booted) => {
    const u = updates();
    const tail = `---\n${timer}\n---\n${night ? JSON.stringify(night) + "\n" : ""}---\n${chosen ? s(chosen) : ""}\n---\n${s(booted)}\n`;
    const text = listed.replace(/---\ninactive\n$/, tail);
    u.read(text);
    u.read(text);   // the next half-hourly read
    return u.root;
  };
  const shown = r => `nightSkipped ${JSON.stringify(r.nightSkipped)}, said ${JSON.stringify(r.said.map(x => x.data.text))}`;
  const battery = read("active", { at: s(at) + 20, skipped: "battery" }, at - 5 * hour, at - 30 * hour);
  check("a night on battery is said once, as why it didn't install, and Settings keeps it",
    battery.nightSkipped === "it wasn't plugged in" && battery.said.length === 1 && battery.said[0].name === "updated"
      && battery.said[0].data.text === "Didn't install last night · it wasn't plugged in" && battery.said[0].data.wide === true, shown(battery));
  const agent = read("active", { at: s(at) + 20, skipped: "agent" }, at - 5 * hour, at - 30 * hour);
  check("a night an agent was working through is said as that", agent.nightSkipped === "an agent was working" && agent.said.length === 1
    && agent.said[0].data.text === "Didn't install last night · an agent was working", shown(agent));
  const off = read("active", null, at - 5 * hour, at + 4 * hour);
  check("a computer started after three o'clock with nothing from the night was switched off", off.nightSkipped === "it was switched off" && off.said.length === 1, shown(off));
  for (const [name, timer, night, chosen, booted] of [
    ["the night went ahead", "active", { at: s(at) + 20, skipped: "" }, at - 5 * hour, at - 30 * hour],
    ["Tonight chosen after the last three o'clock", "active", null, at + hour, at + 4 * hour],
    ["on through the night, nothing written yet", "active", null, at - 5 * hour, at - 30 * hour],
    ["Tonight no longer set", "inactive", { at: s(at) + 20, skipped: "battery" }, at - 5 * hour, at - 30 * hour],
    ["a night before the last one", "active", { at: s(at) - 86400, skipped: "caffeine" }, at - 30 * hour, at - 30 * hour],
  ]) {
    const r = read(timer, night, chosen, booted);
    check(`${name}: nothing said`, r.nightSkipped === "" && r.said.length === 0, shown(r));
  }
}

// Tonight's confirmation names the time and what it needs, read rather than flashed: "Tonight, on the charger" for 1.2 s
{
  let said = null;
  const e = readExpression(src, after("tonightProc", "onExited").at).expr;
  const scope = { root: { says: true }, IslandController: { request: (name, p) => { said = { name, ...p }; } } };
  inScope(scope, "", `return (${e});`)()(0, 0);
  const settings = read("tacit-settings.qml");
  const wing = qmlFunction(read("services/IslandController.qml"), "wingFor");
  const width = p => inScope({ root: { payload: p, focusRunning: false } }, wing.params, wing.body)("updated");
  check("Tonight's notch line names 03:00, left on, plugged in, locked and Caffeine off, in a line as wide as the update's warning",
    said?.name === "updated" && /03:00/.test(said.text) && /left on/.test(said.text) && /plugged in/.test(said.text) && /locked/.test(said.text)
      && /Caffeine off/.test(said.text) && said.wide === true && width({ wide: true }) === 260 && width({}) === 204, `${JSON.stringify(said)}, ${width({ wide: true })} px`);
  check("Settings says why the last night didn't install, else the same conditions",
    settings.includes("`Didn't install last night: ${Updates.nightSkipped}`") && /"Tonight at 03:00 if it's left on, plugged in and locked, with Caffeine off"/.test(settings)
      && !settings.includes('"Tonight, on the charger"'), "the Updates row's description");
}

// Caffeine as root's night sees it: a mark in the person's runtime folder, there while it is on
{
  const idle = read("services/Idle.qml");
  const at = idle.indexOf("onInhibitChanged:");
  const e = at < 0 ? "" : readExpression(idle, at + "onInhibitChanged:".length).expr;
  const dir = mkdtempSync(join(tmpdir(), "tacit-caffeine-"));
  const run = on => {
    let cmd = null;
    inScope({ root: { inhibit: on }, Quickshell: { execDetached: c => { cmd = c; } } }, "", `${e};`)();
    if (cmd) execFileSync(cmd[0], cmd.slice(1), { env: { ...process.env, XDG_RUNTIME_DIR: dir } });
    return existsSync(join(dir, "tacit-caffeine"));
  };
  try {
    const on = at >= 0 && run(true), off = at >= 0 ? run(false) : true;
    check("Caffeine on leaves tacit-caffeine in the runtime folder, off takes it away", on === true && off === false, `on: ${on}, off: ${off}`);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

done();
