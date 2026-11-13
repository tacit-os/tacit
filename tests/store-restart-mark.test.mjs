// "Restart to finish the updates" until the restart: Apps' backend marks a Get X and the updates with this start's boot id
// (stored.py install_ with pacman's run replaced: tests/lib/store_cases.py restart-mark), Apps says it on Your apps from
// the backend's word (store.qml's own bindings under node), and the shell reads the same mark (Updates.qml's check under
// bash, against this computer's own boot id) for the notch's mark at rest (IslandController's ambientGlyph binding).
import { execFileSync, spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync, readFileSync } from "fs";
import { tmpdir } from "os";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { inScope, matchBrace, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== Restart to finish the updates, until the restart (stored.py, store.qml, Updates.qml, IslandController.qml)");
const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "store_cases.py"), tree, "restart-mark"], { encoding: "utf8" });
const seen = r.status === 0 ? JSON.parse(r.stdout.trim().split("\n").pop()) : {};
check("Get X and the updates leaves the restart mark, a plain Get does not", seen.plain === false && seen.everything === true && seen.mark === true,
  r.status === 0 ? JSON.stringify(seen) : r.stderr.trim().split("\n").pop());
check("and the backend stops saying it once the computer has restarted", seen["after restart"] === false, JSON.stringify(seen));

// ---- Apps: Your apps says it, from the backend's word, with Apps closed and opened again
const store = read("store.qml");
const restartNeeded = qmlProperty(store, "restartNeeded");
const fromHome = home => (restartNeeded ? inScope({ root: { home } }, "", `return (${restartNeeded});`)() : false);
check("Apps opened again after it reads the backend's word", fromHome({ restartNeeded: true }) === true && fromHome({ restartNeeded: false }) === false && fromHome(null) === false,
  `restartNeeded: ${restartNeeded}`);
const yoursAt = store.indexOf("id: yoursPage");
const yours = store.slice(yoursAt, matchBrace(store, store.lastIndexOf("{", yoursAt)));
const wordAt = yours.indexOf("Restart to finish the updates");
const word = wordAt < 0 ? "" : yours.slice(yours.lastIndexOf("Word {", wordAt), matchBrace(yours, yours.lastIndexOf("Word {", wordAt) + "Word ".length) + 1);
const key = k => { const m = new RegExp(`\\b${k}\\s*:\\s*`).exec(word); return m ? readExpression(word, m.index + m[0].length).expr : "false"; };
const shown = (needed, armed = false) => { const s = { root: { restartNeeded: needed, restartArmed: armed, inkSec: "sec", inkMain: "main" }, Tacit: { risk: "risk" } };
  return inScope(s, "", `return (${key("visible")});`)() ? { text: inScope(s, "", `return (${key("text")});`)(), ink: inScope(s, "", `return (${key("ink")});`)() } : null; };
check("Your apps has a quiet line for it, in the secondary ink, that restarts on a second press", shown(true)?.text === "Restart to finish the updates" && shown(true)?.ink === "sec"
  && /root\.restart\(\)/.test(key("onPicked")) && shown(true, true)?.text === "Press again" && shown(false) === null, JSON.stringify([shown(true), shown(false)]));

// ---- the shell: the same mark, against this start's boot id
const updates = read("services/Updates.qml");
const at = updates.indexOf("id: restartDueProc");
const proc = at < 0 ? "" : updates.slice(updates.lastIndexOf("Process {", at), matchBrace(updates, updates.lastIndexOf("Process {", at) + "Process ".length) + 1);
const tmp = mkdtempSync(join(tmpdir(), "tacit-restart-mark-"));
try {
  const due = mark => {
    rmSync(join(tmp, ".local"), { recursive: true, force: true });
    if (mark !== null) { mkdirSync(join(tmp, ".local/state/tacit"), { recursive: true }); writeFileSync(join(tmp, ".local/state/tacit/restart-needed"), mark); }
    if (!proc) return false;
    const cmd = inScope({ Directories: { home: tmp } }, "", `return (${readExpression(proc, proc.indexOf("command:") + "command:".length).expr});`)();
    const code = spawnSync(cmd[0], cmd.slice(1)).status;
    const root = { restartDue: null };
    inScope({ root }, "", `return (${readExpression(proc, proc.indexOf("onExited:") + "onExited:".length).expr});`)()(code, 0);
    return root.restartDue;
  };
  const boot = readFileSync("/proc/sys/kernel/random/boot_id", "utf8");
  check("the shell reads the mark made in this start as due", due(boot) === true, `restartDue ${due(boot)}`);
  check("and not one from before a restart, or none", due("0d4c2c8e-0000-4000-8000-000000000000\n") === false && due(null) === false);
  check("it is read with every look of Updates (and so after every pacman transaction)", /function refresh\(\)\s*\{[^}]*restartDueProc\.running = true/.test(updates));
} finally {
  rmSync(tmp, { recursive: true, force: true });
}

// ---- the notch at rest
const island = read("services/IslandController.qml");
const ambient = qmlProperty(island, "ambientGlyph");
const glyph = restartDue => inScope({
  root: { chargerFault: false, micLive: false, prReviews: [], activityAmbient: false, diskPct: 10, memoryFull: false, workUnsaved: false },
  AgentSessions: { waiting: false, justDone: false, sessions: [] }, Claude: { waiting: false }, Notifications: { silent: false, unread: 0 },
  Battery: { available: false, isCharging: false }, Vpn: { connected: false }, Idle: { inhibit: false }, Audio: { sink: { name: "alsa" }, source: null },
  DropShelf: { items: [] }, Hyprsunset: { temperatureActive: false }, Updates: { restartDue },
}, "", ambient.replace(/^\{|\}$/g, ""))();
check("the notch keeps a quiet mark at rest for it until then", glyph(true) === "restart_alt" && glyph(false) === "", `${JSON.stringify(glyph(true))}, without it ${JSON.stringify(glyph(false))}`);
const attention = read("modules/ii/island/IslandHeader.qml").match(/readonly property bool attention: (\[[^\]]*\])/)?.[1] ?? "[]";
check("a quiet one: not among the glyphs drawn in the attention colour", !JSON.parse(attention).includes("restart_alt"), attention);
done();
