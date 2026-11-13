// "S changes the sound" on the recording's choice (modules/ii/island/states/IslandRecord.qml) on a layout that types no
// Latin letter on that key: the sheet's own keyPressed() under node with the key events Qt gives for the same key on a
// US, a Russian and a Greek layout and on Dvorak (Qt names a key by what the layout types; nativeScanCode is the key's
// place, its evdev code + 8 on Wayland), then Qt's own KeyEvent under qmltestrunner, to show it has nativeScanCode.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the recording's S key on other layouts (IslandRecord.qml)");
const src = read("modules/ii/island/states/IslandRecord.qml");
const Qt = { Key_S: 0x53, Key_O: 0x4f, Key_Right: 0x01000014, Key_Left: 0x01000012, Key_Tab: 0x01000001, Key_Backtab: 0x01000002,
  Key_Return: 0x01000004, Key_Enter: 0x01000005 };

function press(key, text, nativeScanCode) {
  let sounds = 0;
  const root = { mode: "choose", pick: "area", choices: [{ what: "area" }, { what: "window" }, { what: "screen" }], choose() {},
    nextSound() { sounds++; }, acted() {}, close() {} };
  const scope = { root, Qt, Files: { reveal() {} } };
  for (const name of ["sKey", "keyPressed"]) {
    const f = qmlFunction(src, name);
    if (f) root[name] = inScope(scope, f.params, f.body);
  }
  const event = { key, text, nativeScanCode, accepted: false };
  root.keyPressed(event);
  return { sounds, accepted: event.accepted };
}
const S = 39, SEMICOLON = 47, D = 40;

check("S on a US layout changes the sound", press(Qt.Key_S, "s", S).sounds === 1);
check("the same key on a Russian layout (ы) does too", press(0x042b, "ы", S).sounds === 1, JSON.stringify(press(0x042b, "ы", S)));
check("and on a Greek one (σ)", press(0x03a3, "σ", S).sounds === 1);
check("the key beside it on the Russian layout (в) does not", press(0x0412, "в", D).sounds === 0);
check("on Dvorak the key that types o does not", press(Qt.Key_O, "o", S).sounds === 0);
check("and the one that types s does", press(Qt.Key_S, "s", SEMICOLON).sounds === 1);

// Qt's KeyEvent, as a Keys handler receives it: nativeScanCode is one of its properties
const out = runScene({ "tst_scan.qml": `import QtQuick
import QtTest
TestCase {
    name: "scan"; when: windowShown
    Item { id: box; focus: true; Keys.onPressed: e => console.log("SCAN " + typeof e.nativeScanCode) }
    function test_scan() { box.forceActiveFocus(); keyClick(Qt.Key_S) }
}
` });
check("Qt's KeyEvent has nativeScanCode", /SCAN number/.test(out), out.trim().split("\n").slice(0, 3).join(" | "));
done();
