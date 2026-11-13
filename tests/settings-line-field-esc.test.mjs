// Esc in one of Settings' typed boxes (tacit-settings.qml's LineField: the Wi-Fi password, the password change, a pasted
// key, Add a word, Watch pull requests): the box's own block in a page whose Esc closes Settings, as pageColumn's does,
// under qmltestrunner offscreen, so Qt's own key delivery carries the Esc from the box. The first Esc empties the box and
// leaves it and says so (cancelled), without closing Settings; the next one closes it. Every box beside a Cancel closes
// its line on that Esc, and none keeps an Esc handler of its own, which the box's would now stand in front of.
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { matchBrace } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Esc in a typed box in Settings (tacit-settings.qml LineField)");
const src = read("tacit-settings.qml");
const field = objectWith(src, "id: lf");
const files = {
  ...module("qs.modules.common", {
    Appearance: `QtObject { property var rounding: ({ small: 8 }); property var colors: ({ colLayer2: "#222", colPrimary: "#88f", colOutlineVariant: "#444", colInkMain: "#eee" }); property var font: ({ family: ({ main: "sans" }) }) }`,
    Tacit: `QtObject { property color inkMeta: "#999" }`,
  }),
  ...module("qs.modules.common.functions", { ColorUtils: `QtObject { function transparentize(c, a) { return c } }` }),
  ...module("qs.modules.common.widgets", {}, { StyledText: `Text {}` }),
};
const scene = `import QtQuick
import QtTest
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
Item {
    id: top
    width: 400; height: 200
    component LineField: ${field}
    property int closed: 0
    property int cancelled: 0
    FocusScope {
        id: page
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: top.closed++
        LineField { id: box; placeholder: "Password" }
    }
    Connections { target: box; ignoreUnknownSignals: true; function onCancelled() { top.cancelled++ } }
    TestCase {
        name: "esc"; when: windowShown
        function test_esc() {
            const out = {}
            box.focusInput()
            keyClick(Qt.Key_S); keyClick(Qt.Key_E); keyClick(Qt.Key_C)
            out.typed = box.text
            keyClick(Qt.Key_Escape)
            out.first = { closed: top.closed, cancelled: top.cancelled, text: box.text }
            keyClick(Qt.Key_Escape)
            out.second = { closed: top.closed }
            console.log("ESC " + JSON.stringify(out))
        }
    }
}
`;
try {
  const r = logged(runScene({ "tst_linefield.qml": scene, ...files }), "ESC");
  check("the box took the typing", r.typed === "sec", JSON.stringify(r.typed));
  check("the first Esc does not close Settings", r.first.closed === 0, `Settings closed ${r.first.closed} time(s)`);
  check("it empties the box and says cancelled", r.first.text === "" && r.first.cancelled === 1, JSON.stringify(r.first));
  check("the next Esc, out of the box, closes Settings", r.second.closed === 1, JSON.stringify(r.second));
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}

// the boxes in use: those in a row with a Cancel close it on Esc; none has a Keys.onEscapePressed of its own
const uses = [...src.matchAll(/\bLineField\s*\{/g)].map(m => ({
  at: src.slice(0, m.index).split("\n").length,
  block: src.slice(m.index, matchBrace(src, m.index + m[0].length - 1) + 1),
}));
const rowOf = at => src.split("\n").slice(at - 1, at + 14).join("\n");
const own = uses.filter(u => /Keys\.onEscapePressed/.test(u.block)).map(u => u.at);
check("no box has an Esc handler of its own, which the box's would stand in front of", own.length === 0, `lines ${own.join(", ")}`);
const beside = uses.filter(u => /Slab\s*\{[^}]*text:\s*"Cancel"/.test(rowOf(u.at)));
const open = beside.filter(u => !/onCancelled:/.test(u.block)).map(u => u.at);
check(`the ${beside.length} boxes beside a Cancel close their line on Esc`, beside.length >= 5 && open.length === 0, `lines ${open.join(", ")}`);
check("the boxes in use were found", uses.length >= 8, `${uses.length}`);
done();
