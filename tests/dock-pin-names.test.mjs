// A pinned program's name in the dock (modules/ii/overview/PaletteDock.qml): the tree's own known names, entryFor(),
// nameFor() and the pill label's binding, under Qt's qml offscreen, beside a stand-in for Quickshell's DesktopEntries.
// Like Quickshell 0.3.2 (src/core/desktopentry.cpp), its lookups read a table no binding can see, its first read lands
// after the dock is made (a queued call, :364-369), a launcher reinstalled or replaced by the user's own file is a new
// entry (:500-561), and heuristicLookup() takes the first entry in its table whose StartupWMClass fits (:447-463).
import { qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a pinned program's name in the dock (PaletteDock.qml)");
const src = read("modules/ii/overview/PaletteDock.qml");
const fn = name => { const f = qmlFunction(src, name); return f ? `function ${name}(${f.params}) {${f.body}}` : ""; };
const label = objectWith(src, "id: label");
const labelText = readExpression(label, label.indexOf("text:") + "text:".length).expr;
// the revision a newer tree keeps, and its Connections; release-1.2.15 has neither
const revision = (src.match(/\n\s*property int entriesRead:[^\n]*/) ?? [""])[0];
let reread = "";
try { reread = objectWith(src, "function onApplicationsChanged()"); } catch (e) { reread = ""; }

const entry = (id, name, startupClass = "", noDisplay = false) => ({ id, name, startupClass, noDisplay });
const system = [
  entry("org.telegram.desktop", "Telegram Desktop", "TelegramDesktop"),
  // an app and its URL handler declare one window class; the handler happens to come first in the table
  entry("com.visualstudio.code-url-handler", "Visual Studio Code - URL Handler", "Code", true),
  entry("com.visualstudio.code", "Visual Studio Code", "Code"),
  entry("com.spotify.Client", "Spotify", "spotify"),
  entry("gimp", "GNU Image Manipulation Program", "gimp"),
];
const steps = [
  ["the dock is made before the entries are read", null],
  ["the first read lands", system],
  ["Telegram reinstalled under the same id with a new name", system.map(e => e.id === "org.telegram.desktop" ? entry(e.id, "Telegram", e.startupClass) : e)],
  ["Files installed after it was pinned", [...system.map(e => e.id === "org.telegram.desktop" ? entry(e.id, "Telegram", e.startupClass) : e),
    entry("org.gnome.Nautilus", "Files", "org.gnome.Nautilus")]],
  ["an Apps launcher of the same id takes the system one's place", [...system.map(e => e.id === "org.telegram.desktop" ? entry(e.id, "Telegram", e.startupClass) : e)
    .map(e => e.id === "gimp" ? entry("gimp", "GIMP", "gimp") : e), entry("org.gnome.Nautilus", "Files", "org.gnome.Nautilus")]],
];
const pins = ["praxis", "org.telegram.desktop", "code", "spotify", "org.gnome.nautilus", "gimp"];

const scene = `import QtQuick
import Quickshell
Item {
    id: root
    readonly property var known: ${qmlProperty(src, "known")}
    ${revision}
    ${reread}
    ${fn("entryFor")}
    ${fn("nameFor")}
    readonly property var steps: ${JSON.stringify(steps.map(s => s[1]))}
    property int at: 0
    property var seen: []
    property var again: []
    property int scans: 0
    component Pill: Item {
        id: pill
        required property var modelData
        readonly property string appId: modelData
        readonly property string shown: ${labelText}
    }
    Repeater { id: pills; model: ${JSON.stringify(pins)}; Pill {} }
    // the same pins made again once the first read is in, as unpinning and pinning again makes them
    Repeater { id: pinnedAgain; model: root.scans >= 1 ? ${JSON.stringify(pins)} : []; Pill {} }
    Timer {
        interval: 50; repeat: true; running: true
        onTriggered: {
            const names = [], again = [];
            for (let i = 0; i < pills.count; i++) names.push(pills.itemAt(i).shown);
            for (let i = 0; i < pinnedAgain.count; i++) again.push(pinnedAgain.itemAt(i).shown);
            root.seen = root.seen.concat([names]);
            root.again = root.again.concat([again]);
            root.at++;
            if (root.at === root.steps.length) { console.log("NAMES " + JSON.stringify({ seen: root.seen, again: root.again })); Qt.quit(); return; }
            DesktopEntries.scan(root.steps[root.at]);
            root.scans++;
        }
    }
}
`;
const files = {
  "scene.qml": scene,
  ...module("Quickshell", { DesktopEntries: `QtObject {
    id: de
    // the C++ table: changed in place, so a lookup's caller never sees it change
    property var table: ({ all: [] })
    // its applicationsChanged is the one Quickshell sends after each scan (in QML it is this property's own signal)
    readonly property QtObject applications: QtObject { property var values: [] }
    function byId(id) {
        const t = de.table.all, s = String(id);
        return t.find(e => e.id === s) ?? t.find(e => e.id.toLowerCase() === s.toLowerCase()) ?? null;
    }
    function heuristicLookup(name) {
        const t = de.table.all, s = String(name);
        return de.byId(s) ?? t.find(e => e.startupClass === s) ?? t.find(e => e.startupClass.toLowerCase() === s.toLowerCase()) ?? null;
    }
    // a scan: new entries for what was rewritten, the table swapped, the menu's list told, then the signal
    function scan(list) {
        de.table.all = list.map(e => Object.assign({}, e));
        de.applications.values = de.table.all.filter(e => !e.noDisplay);
        de.applicationsChanged();
    }
}` }),
};

let seen = null, again = null;
try { ({ seen, again } = logged(runScene(files), "NAMES")); } catch (e) { check("the dock's names ran under Qt", false, String(e.message ?? e)); }
if (seen) {
  const at = (step, pin) => seen[step][pins.indexOf(pin)];
  const say = step => JSON.stringify(seen[step]);
  check("Tacit's own programs keep Tacit's names", seen.every(s => s[0] === "Praxis"), JSON.stringify(seen.map(s => s[0])));
  check("made before the entries were read, a pinned program has its name once they are", at(1, "org.telegram.desktop") === "Telegram Desktop",
    `before ${JSON.stringify(at(0, "org.telegram.desktop"))}, after the read ${JSON.stringify(at(1, "org.telegram.desktop"))}`);
  check("pinned by its window's class, which an app and its URL handler share: the app's name", at(1, "code") === "Visual Studio Code"
    && again[1][pins.indexOf("code")] === "Visual Studio Code", `${say(1)}, pinned again ${JSON.stringify(again[1])}`);
  check("(unpinned and pinned again after the read, a pin had its name, as the report found)", again[1][pins.indexOf("org.telegram.desktop")] === "Telegram Desktop",
    JSON.stringify(again[1]));
  check("pinned by a class only a launcher's StartupWMClass names: that launcher's name", at(1, "spotify") === "Spotify", say(1));
  check("reinstalled with a new name under the same id: the new name", at(2, "org.telegram.desktop") === "Telegram", say(2));
  check("pinned before it was installed: its name once it is", at(3, "org.gnome.nautilus") === "Files",
    `before ${JSON.stringify(at(2, "org.gnome.nautilus"))}, installed ${JSON.stringify(at(3, "org.gnome.nautilus"))}`);
  check("an Apps launcher in the system one's place: the launcher's name", at(4, "gimp") === "GIMP", say(4));
}
done();
