// Settings > About > Updates' Restart (tacit-settings.qml): it closes every app, so it asks in place before it calls
// Updates.restartNow(), as the kit's confirm does. The row's own TextButton, with the component's functions, handlers
// and the bindings of its glyph and words, runs under node: clicks, keys, the pointer leaving and its timer. And with
// Tonight chosen the row still offers Restart, which session/updates/tacit-update now turns into a restart instead.
import { execFileSync } from "child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("tacit-settings.qml");
const compAt = src.indexOf("component TextButton:");
const comp = src.slice(compAt, matchBrace(src, src.indexOf("{", compAt)) + 1);
const useAt = src.lastIndexOf("TextButton {", src.indexOf("onPressed: Updates.restartNow()"));
const use = src.slice(useAt, matchBrace(src, useAt + "TextButton ".length) + 1);
// "<key>: <expression>" in a block, the first after "<inside>" when given; null when there is none
function expr(block, key, inside = "") {
  const re = new RegExp(`(^|\\n)\\s*${key.replace(/\./g, "\\.")}\\s*:\\s*`, "g");
  re.lastIndex = inside ? block.indexOf(inside) : 0;
  const m = re.exec(block);
  return m ? readExpression(block, m.index + m[0].length).expr : null;
}

function aboutRestart() {
  const updates = { restartWarning: "", ran: 0, restartNow() { this.ran++; } };
  const Tacit = { risk: "risk", inkMain: "main", inkSec: "sec", motion: { confirmWait: { ms: 4000 } } };
  const askWait = { running: false, restart() { this.running = true; }, start() { this.running = true; }, stop() { this.running = false; } };
  const btn = { enabled: true, _focus: false };
  const scope = { btn, Updates: updates, Tacit, askWait, Appearance: { colors: { colInkFaint: "faint" } } };
  const run = (body, params = "") => inScope(scope, params, body);
  const bind = e => run(`return (${e});`);
  // the component's own properties, its readonly ones as bindings; the row's label and confirm as bindings too
  for (const m of comp.matchAll(/^\s*(readonly\s+)?property\s+[\w.<>]+\s+(\w+)\s*:\s*(.+)$/gm)) {
    if (m[1]) { const f = bind(m[3]); Object.defineProperty(btn, m[2], { get: f }); } else btn[m[2]] = bind(m[3])();
  }
  for (const key of ["label", "confirm"]) { const e = expr(use, key); if (e) { const f = bind(e); Object.defineProperty(btn, key, { get: f }); } }
  for (const m of comp.matchAll(/\bfunction\s+(\w+)\s*\(/g)) { const f = qmlFunction(comp, m[1]); btn[m[1]] = run(f.body, f.params); }
  btn.pressed = run(expr(use, "onPressed"));
  const focusChanged = expr(comp, "onActiveFocusChanged");
  Object.defineProperty(btn, "activeFocus", { get: () => btn._focus, set: v => { if (v === btn._focus) return; btn._focus = v; if (focusChanged) run(focusChanged)(); } });
  btn.forceActiveFocus = () => { btn.activeFocus = true; };
  const statement = key => { const e = expr(comp, key); return e ? run(e) : () => {}; };
  const timer = statement("onTriggered");
  const clicked = statement("onClicked"), exited = statement("onExited"), enter = statement("Keys.onReturnPressed");
  const escExpr = expr(comp, "Keys.onEscapePressed");
  // a handler written "event => { ... }" is a function to call with the event; a statement runs as it is
  const esc = () => { const ev = { accepted: true }; if (escExpr) { const e = escExpr.trim(); if (/^\(?\s*event\s*\)?\s*=>/.test(e)) bind(e)()(ev); else run(e)(); } else ev.accepted = false; return ev.accepted; };
  // what is drawn: the glyph's and the words' own bindings
  const symbol = comp.indexOf("MaterialSymbol {"), words = comp.indexOf("StyledText {");
  const shown = () => ({
    words: bind(expr(comp, "text", "StyledText {") ?? "btn.label")(),
    ink: bind(expr(comp.slice(words), "color"))(),
    glyph: bind(expr(comp.slice(symbol), "visible"))() ? bind(expr(comp.slice(symbol), "text"))() : "",
  });
  return { updates, btn, askWait, shown, clicked, exited, enter, esc, wait: () => { if (askWait.running) { askWait.running = false; timer(); } } };
}

console.log("Settings > About > Restart (tacit-settings.qml)");

{
  const a = aboutRestart();
  a.clicked();
  const s = a.shown();
  check("one click on Restart does not restart: the words ask, in the risk ink after the warning glyph",
    a.updates.ran === 0 && s.words !== "Restart" && s.words.length > 0 && s.ink === "risk" && s.glyph === "warning",
    `${a.updates.ran ? "it restarted" : "it did not restart"}, it shows ${s.glyph ? `${s.glyph} ` : ""}"${s.words}" in the ${s.ink} ink`);
  a.clicked();
  check("a second click restarts", a.updates.ran === 1, `restartNow() ran ${a.updates.ran} times`);
  check("then the words are Restart again", a.shown().words === "Restart", `"${a.shown().words}"`);
}
{
  const a = aboutRestart();
  a.enter();
  const asked = a.updates.ran === 0 && a.shown().ink === "risk";
  a.enter();
  check("from the keyboard the same: Enter asks, Enter again restarts", asked && a.updates.ran === 1, `ran ${a.updates.ran} times, asked ${asked}`);
}
for (const [what, undo] of [["Esc", a => a.esc()], ["the pointer leaving", a => a.exited()], ["4 s untouched", a => a.wait()], ["the keyboard leaving", a => { a.btn.activeFocus = false; }]]) {
  const a = aboutRestart();
  a.clicked();
  undo(a);
  const back = a.shown().words === "Restart";
  a.clicked();
  check(`${what} takes the question back, and the next click asks again`, back && a.updates.ran === 0,
    `${back ? "" : `it still shows "${a.shown().words}", `}restartNow() ran ${a.updates.ran} times`);
}
{
  const a = aboutRestart();
  check("Esc with nothing asked goes on to the page, which closes Settings", a.esc() === false, "the button kept it");
}
{
  const a = aboutRestart();
  a.updates.restartWarning = "An agent is still working: Fix the build";
  a.clicked();
  check("after a warning, one click on Restart anyway restarts: the warning was the question", a.updates.ran === 1 && a.btn.label === "Restart anyway",
    `"${a.btn.label}", restartNow() ran ${a.updates.ran} times`);
}

// before this, choosing Tonight took both buttons away until three o'clock: no way to have them now from Settings
{
  const rowAt = src.lastIndexOf("control: Row {", useAt);
  const row = src.slice(rowAt, matchBrace(src, src.indexOf("{", rowAt)) + 1);
  const scope = { updatesGroup: { ready: true, tonight: true }, Updates: { restarting: false, restartWarning: "" } };
  const shown = e => e === null || inScope(scope, "", `return (${e});`)();
  const buttons = [...row.matchAll(/\bTextButton\s*\{/g)].map(m => row.slice(m.index, matchBrace(row, m.index + m[0].length - 1) + 1))
    .filter(b => shown(expr(b, "visible"))).map(b => inScope(scope, "", `return (${expr(b, "label")});`)());
  const offered = shown(expr(row, "visible")) ? buttons : [];
  check("with Tonight chosen, the row still offers Restart, and not Tonight again", offered.join() === "Restart",
    offered.length ? `it offers ${offered.join(", ")}` : "it offers nothing");

  // what that Restart starts (tacit-update@now), run by bash with its system paths in a folder of its own
  const dir = mkdtempSync(join(tmpdir(), "tacit-restart-"));
  try {
    const script = read("session/updates/tacit-update").replaceAll("/var/lib/tacit", join(dir, "state"))
      .replaceAll("/var/lib/pacman/db.lck", join(dir, "db.lck")).replaceAll("/system-update", join(dir, "system-update"));
    writeFileSync(join(dir, "tacit-update"), script);
    for (const t of ["systemctl", "pacman"]) { writeFileSync(join(dir, t), `#!/bin/bash\necho "${t} $*" >> "${join(dir, "calls")}"\n`); chmodSync(join(dir, t), 0o755); }
    execFileSync("bash", [join(dir, "tacit-update"), "now"], { env: { ...process.env, PATH: `${dir}:${process.env.PATH}` } });
    const calls = readFileSync(join(dir, "calls"), "utf8");
    check("and that Restart takes Tonight away: tacit-update now disables the night's timer", calls.includes("systemctl disable --now tacit-update-night.timer"), calls.trim());
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

done();
