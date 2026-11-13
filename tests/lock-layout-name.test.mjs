// The lock's note beside the password (modules/ii/lock/CapsLockNote.qml, on the lock and the boot lock): the tree's own
// file under Qt's qml tool offscreen, with a stand-in hyprctl answering as Hyprland 0.56.2's `hyprctl -j devices` does
// and a stand-in Hyprland that sends its activelayout event. On a us,ru pair switched to Russian, a password fails as a
// plain wrong one, and the lock never said which layout was in use.
import { logged, module, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the keyboard layout on the lock (CapsLockNote.qml)");
const keyboard = (index, name, caps) => JSON.stringify({ mice: [], keyboards: [
  { name: "power-button", layout: "us,ru", active_layout_index: 0, active_keymap: "English (US)", capsLock: false, main: false },
  { name: "at-translated-set-2-keyboard", layout: "us,ru", active_layout_index: index, active_keymap: name, capsLock: caps, main: true }] });
const files = {
  "CapsLockNote.qml": read("modules/ii/lock/CapsLockNote.qml"),
  ...module("qs.services", { Translation: `QtObject { function tr(s) { return s } }` }),
  ...module("qs.modules.common", { Appearance: `QtObject { property var colors: ({ colSubtext: "grey" }) }` }),
  ...module("qs.modules.common.widgets", {}, { MaterialSymbol: `Text { property real iconSize }`, StyledText: `Text {}` }),
  ...module("Quickshell.Hyprland", { Hyprland: `QtObject { signal rawEvent(var event) }` }),
  ...module("Devices", { Devices: `QtObject { property string answer: ""; property int reads: 0 }` }),
  ...module("Quickshell.Io", {}, {
    StdioCollector: `QtObject { property string text; signal streamFinished() }`,
    Process: `import Devices
Item {
    id: p
    property var command: []
    property bool running: false
    property QtObject stdout
    function finish() { Devices.reads++; p.stdout.text = Devices.answer; p.stdout.streamFinished(); p.running = false }
    onRunningChanged: if (running) Qt.callLater(p.finish)
}`,
  }),
};
const scene = `import QtQuick
import Devices
import Quickshell.Hyprland
Item {
    CapsLockNote { id: note }
    // what the note shows: the words of each part in view, or nothing when it is hidden
    function shown() {
        if (!note.visible) return [];
        const out = [];
        for (let i = 0; i < note.children.length; i++) if (note.children[i].visible && note.children[i].text) out.push(note.children[i].text);
        return out;
    }
    property var steps: [
        [${JSON.stringify(keyboard(0, "English (US)", false))}, "open"],
        [${JSON.stringify(keyboard(0, "English (US)", true))}, "caps"],
        [${JSON.stringify(keyboard(1, "Russian", true))}, "switch"],
        [${JSON.stringify(keyboard(1, "Russian", false))}, "caps"],
        [${JSON.stringify(keyboard(0, "English (US)", false))}, "switch"],
        ["not json", "caps"]
    ]
    property int at: -1
    property var seen: []
    Timer {
        interval: 250; repeat: true; running: true
        onTriggered: {
            if (at >= 0) seen = seen.concat([shown()]);
            at++;
            if (at === steps.length) { console.log("NOTE " + JSON.stringify(seen)); Qt.quit(); return; }
            Devices.answer = steps[at][0];
            // the lock opening reads by itself; Caps Lock pressed in the field calls refresh(); Alt + Shift is Hyprland's event
            if (steps[at][1] === "caps") note.refresh();
            else if (steps[at][1] === "switch") Hyprland.rawEvent({ name: "activelayout", data: "at-translated-set-2-keyboard," + JSON.parse(steps[at][0]).keyboards[1].active_keymap });
        }
    }
}
`;
try {
  const [open, caps, russian, russianOnly, back, broken] = logged(runScene({ "note.qml": scene, ...files }), "NOTE");
  const words = s => JSON.stringify(s.filter(t => !t.startsWith("keyboard")));
  check("the lock opens on the first layout, Caps Lock off: nothing", open.length === 0, JSON.stringify(open));
  check("Caps Lock on: the note alone, no layout named", words(caps) === '["Caps Lock is on"]', JSON.stringify(caps));
  check("Alt + Shift to Russian: its name beside the Caps Lock note", words(russian) === '["Caps Lock is on","Russian"]', JSON.stringify(russian));
  check("Caps Lock off on Russian: the layout's name alone", words(russianOnly) === '["Russian"]', JSON.stringify(russianOnly));
  check("back to the first layout: nothing again", back.length === 0, JSON.stringify(back));
  check("hyprctl unreadable: nothing", broken.length === 0, JSON.stringify(broken));
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
