// Settings > Keyboard & touchpad > Shortcuts records the key that was pressed on other layouts too
// (modules/settings/ShortcutRow.qml's capture, services/Shortcuts.qml's keyName): the row's own key handler runs under
// node with the events Qt gives for keys on US, Russian and Greek (second to US, as Setup and Settings write them),
// AZERTY, Dvorak and Turkish layouts (Qt names a key by what the layout types; nativeScanCode is its place, the evdev
// code + 8). Each shortcut it records goes through Shortcuts.forHypr and tacit/shortcuts.lua's normalize to the key
// Hyprland binds, which fires on the key pressed when it is that key's code:NN or names the first layout's unshifted
// keysym there (Hyprland 0.56.2, KeybindManager.cpp 367-369 and 690-691): `first` below, from xkb's keymaps. A key with
// no name says so in the row instead of passing for a modifier.
import { execFileSync } from "child_process";
import { join } from "path";
import { inScope, matchBrace, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { logged, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== shortcuts record the key pressed on other layouts (ShortcutRow.qml, Shortcuts.qml, tacit/shortcuts.lua)");
const src = read("services/Shortcuts.qml"), page = read("modules/settings/ShortcutsPage.qml");
const capture = objectWith(read("modules/settings/ShortcutRow.qml"), "id: capture");
const open = capture.indexOf("{", capture.indexOf("Keys.onPressed: event =>"));
const handler = capture.slice(open + 1, matchBrace(capture, open));

// Qt's own values for the keys and modifiers the code and these events name
const names = [...new Set(`${src} ${handler} Qt.Key_S Qt.Key_O Qt.Key_A Qt.Key_1 Qt.Key_Exclam Qt.Key_Period Qt.Key_Underscore
  Qt.Key_Ampersand Qt.Key_Colon Qt.Key_Ugrave Qt.Key_Dead_Circumflex Qt.Key_Meta Qt.Key_AltGr`.match(/\bQt\.(Key_\w+|\w+Modifier)\b/g))];
const Qt = logged(runScene({ "qt.qml": `import QtQuick
Item { Component.onCompleted: { console.log("QT " + JSON.stringify({ ${names.map(n => `${n.slice(3)}: ${n}`).join(", ")} })); Qt.quit() } }
` }), "QT");

// the singleton with the tree's own tables and functions; nothing held by the compositor
const S = { changed: {}, apps: [], live: [], listen() {} };
const value = expr => /^\{[\s\S]*\breturn\b/.test(expr) ? inScope({ root: S, Qt }, "", expr.slice(1, -1))() : inScope({ root: S, Qt }, "", `return (${expr});`)();
for (const name of ["groups", "rowIndex", "modOrder", "capNames", "qtKeys", "shiftKeys", "usPlaces"]) {
  const e = qmlProperty(src, name);
  if (e) S[name] = value(e);
}
for (const name of ["keyName", "modsOf", "problem", "norm", "holder", "slotsOf", "keysOf", "capName", "said", "forHypr"]) {
  const f = qmlFunction(src, name);
  S[name] = inScope({ root: S, Qt }, f.params.replace(/:\s*\w+/g, ""), f.body);
}

// the key with Super held, as the row takes it: { keys } when it records a combination, { held } when it waits for more
function press(key, scan, shift = false, mods = Qt.MetaModifier) {
  const got = {};
  const r = { mode: "listening", capturedKeys: (combo, held) => Object.assign(got, { keys: combo, held }), capturedHeld: held => (got.held = held),
    cancelled() {}, chooseOther() {} };
  const event = { key, nativeScanCode: scan, modifiers: mods | (shift ? Qt.ShiftModifier : 0), accepted: false };
  inScope({ r, Qt, Shortcuts: S }, "event", handler)(event);
  return got;
}
// what the page does with it, for the Terminal's row: { mode, line, held, saved }
function captured(combo, held) {
  const p = { held: "", mode: "listening", clashText: "", pend: null, cancel() { p.mode = "same"; }, commit: (id, c) => (p.saved = c) };
  const f = qmlFunction(page, "captured");
  inScope({ page: p, Shortcuts: S }, f.params, f.body)("term", combo, held);
  return { mode: p.mode, line: p.clashText, held: p.held, saved: p.saved };
}
// the key part Hyprland is given for each combination: Settings' file says forHypr(combo), tacit/shortcuts.lua binds it
function bound(combos) {
  const lua = `local M = dofile(${JSON.stringify(join(tree, "session/hypr/tacit/shortcuts.lua"))})
for _, c in ipairs({ ${combos.map(c => JSON.stringify(S.forHypr(c))).join(", ")} }) do local _, keys = M.normalize(c); print(keys) end`;
  return execFileSync("lua", ["-e", lua], { encoding: "utf8" }).trim().split("\n").map(k => k.split(" + ").pop());
}

// [layout, what is pressed, Qt's key, its place, Shift, the first layout's unshifted keysym there, what the row shows];
// Qt's keys are what its QXkbCommon makes of xkb's keysyms (a letter it has no name for is its upper-case code point)
const keys = [
  ["us", "Super+S", Qt.Key_S, 39, false, "s", "Super S"],
  ["us", "Super+Shift+1", Qt.Key_Exclam, 10, true, "1", "Super Shift 1"],
  ["us", "Super+.", Qt.Key_Period, 60, false, "period", "Super ."],
  ["us", "Super+Shift+-", Qt.Key_Underscore, 20, true, "minus", "Super Shift -"],
  ["us,ru", "Super+ф (the A key)", 0x424, 38, false, "a", "Super A"],
  ["us,ru", "Super+х (the [ key)", 0x425, 34, false, "bracketleft", "Super ["],
  ["us,ru", "Super+Shift+№ (the 3 key)", 0x2116, 12, true, "3", "Super Shift 3"],
  ["us,gr", "Super+ψ (the C key)", 0x3a8, 54, false, "c", "Super C"],
  ["us,gr", "Super+ς (the W key)", 0x3a3, 25, false, "w", "Super W"],
  ["fr", "Super+& (the 1 key)", Qt.Key_Ampersand, 10, false, "ampersand", "Super 1"],
  ["fr", "Super+_ (the 8 key)", Qt.Key_Underscore, 17, false, "underscore", "Super 8"],
  ["fr", "Super+Shift+1", Qt.Key_1, 10, true, "ampersand", "Super Shift 1"],
  ["fr", "Super+A", Qt.Key_A, 24, false, "a", "Super A"],
  ["us(dvorak)", "Super+S", Qt.Key_S, 47, false, "s", "Super S"],
  ["us(dvorak)", "Super+O (where QWERTY has S)", Qt.Key_O, 39, false, "o", "Super O"],
  ["us(dvorak)", "Super+.", Qt.Key_Period, 26, false, "period", "Super ."],
  ["tr", "Super+S", Qt.Key_S, 39, false, "s", "Super S"],
];
const got = keys.map(([, , key, scan, shift]) => press(key, scan, shift).keys);
const hypr = bound(got.map(c => c ?? ""));
keys.forEach(([layout, what, , scan, , first, shows], i) => {
  const fires = got[i] !== undefined && (hypr[i] === `code:${scan}` || hypr[i].toLowerCase() === first);
  check(`${layout}: ${what} is recorded, shown as "${shows}", and fires on that key`, fires && S.said(got[i]) === shows,
    `recorded ${JSON.stringify(got[i])}, Hyprland gets ${JSON.stringify(got[i] === undefined ? null : hypr[i])} for ${first} at ${scan}`);
});

// the clash checks see the same keys as on a US layout
for (const [layout, what, key, scan, line] of [["us,ru", "Super+у", 0x423, 26, "Super E already opens Files."],
  ["fr", "Super+&", Qt.Key_Ampersand, 10, "Super 1 already goes to a workspace."]]) {
  const p = press(key, scan);
  const row = p.keys === undefined ? null : captured(p.keys, p.held);
  check(`${layout}: ${what} says "${line}"`, row?.mode === "clash" && row.line === line, JSON.stringify({ p, row }));
}

// a key with no name is said in the row; a modifier alone still waits for the key
for (const [layout, what, key, scan] of [["fr", "ù", Qt.Key_Ugrave, 48], ["fr", "the dead ^", Qt.Key_Dead_Circumflex, 34],
  ["fr", ": (not ; on the key beside it)", Qt.Key_Colon, 60], ["tr", "ğ", 0x11e, 34]]) {
  const p = press(key, scan);
  const row = p.keys === undefined ? null : captured(p.keys, p.held);
  check(`${layout}: Super+${what} says "This key can't be used for a shortcut." with Super held`,
    row?.mode === "clash" && row.line === "This key can't be used for a shortcut." && row.held === "Super", JSON.stringify({ p, row }));
}
// (Qt gives the Super key's own press with no modifier yet)
for (const [what, key, scan, mods] of [["Super", Qt.Key_Meta, 133, 0], ["AltGr", Qt.Key_AltGr, 108, Qt.MetaModifier]]) {
  const p = press(key, scan, false, mods);
  check(`${what} alone waits for the key`, p.keys === undefined && p.held === "Super", JSON.stringify(p));
}
done();
