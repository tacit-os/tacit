// Super+G's widgets (modules/ii/overlay/StyledOverlayWidget.qml, and Crosshair.qml on it): the tree's own files, on the
// tree's AbstractWidget and TacitCard, run under Qt's qmltestrunner offscreen on a 1920 x 1080 screen with stand-ins for
// the singletons and the card's glyph and text. Qt's layouts place the body under the header and Qt's own delivery takes
// the presses; where a widget's body is on the screen is read from the body itself.
import { logged, module, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Super+G's widgets, pinned with the overlay closed and clicked on their border (StyledOverlayWidget.qml)");
// the files use nothing of Quickshell's, and its real module cannot load outside the shell
const qml = path => read(path).replace(/^import Quickshell\n/m, "");
const none = `readonly property var none: ({ createObject: () => null })`;
const files = {
  ...module("qs", { GlobalStates: `QtObject { property bool overlayOpen: true }` }),
  ...module("qs.modules.common", {
    Appearance: `QtObject {
    ${none}
    property var animationCurves: ({ expressiveDefaultSpatialDuration: 0, expressiveDefaultSpatial: [0, 0, 1, 1, 1, 1], emphasizedDecel: [0, 0, 1, 1, 1, 1] })
    // AbstractWidget's x and y glide as the shell's do
    property Component glide: Component { NumberAnimation { duration: 300 } }
    property var animation: ({ elementMove: { numberAnimation: glide } })
    property var colors: ({ colPrimary: "#88f", colSubtext: "#aaa", colOnLayer0: "#fff", colLayer0Border: "#444" })
    property var m3colors: ({ m3surfaceContainer: "#222" })
    property var rounding: ({ verylarge: 30 })
}`,
    Config: `QtObject { property var options: ({ overlay: { clickthroughOpacity: 0.8 }, background: { widgetsLocked: false } }) }`,
    // the widgets' saved spots as Persistent keeps them: objects whose writes are seen
    Persistent: `QtObject {
    property QtObject states: QtObject {
        property QtObject overlay: QtObject {
            property var open: ["notes", "crosshair"]
            property QtObject notes: QtObject { property real x: 300; property real y: 200; property real width: 250; property real height: 100; property bool pinned: true; property bool clickthrough: false }
            property QtObject crosshair: QtObject { property real x: 600; property real y: 300; property real width: 0; property real height: 0; property bool pinned: true; property bool clickthrough: true }
        }
    }
}`,
  }),
  ...module("qs.modules.common.functions", { ColorUtils: `QtObject { function transparentize(c, a) { return c } }` }),
  ...module("qs.modules.common.widgets", {}, {
    StyledText: `Text {}`,
    MaterialSymbol: `Text { property real iconSize }`,
    Anim: `NumberAnimation { enum Type { DefaultEffects } property int type }`,
  }),
  ...module("qs.modules.tacit.overlay", {}, { OverlayRoundButton: `Item { property string glyph; property bool on; signal clicked() }` }),
  ...module("qs.modules.ii.overlay", {
    OverlayContext: `QtObject { signal requestCenter(string identifier); function pin(i, p) {} function registerClickableWidget(w, c) {} }`,
  }),
  ...module("qs.modules.tacit.card"),
  ...module("qs.modules.common.widgets.widgetCanvas"),
  "qs/modules/tacit/card/TacitCard.qml": qml("modules/tacit/card/TacitCard.qml"),
  "qs/modules/ii/overlay/StyledOverlayWidget.qml": qml("modules/ii/overlay/StyledOverlayWidget.qml"),
  "qs/modules/common/widgets/widgetCanvas/AbstractWidget.qml": qml("modules/common/widgets/widgetCanvas/AbstractWidget.qml"),
  "qs/modules/common/widgets/widgetCanvas/AbstractOverlayWidget.qml": qml("modules/common/widgets/widgetCanvas/AbstractOverlayWidget.qml"),
  "crosshair/Crosshair.qml": qml("modules/ii/overlay/crosshair/Crosshair.qml"),
  "crosshair/CrosshairContent.qml": `import QtQuick\nItem { implicitWidth: 40; implicitHeight: 40 }\n`,
};
files["qs/modules/tacit/card/qmldir"] += "TacitCard 1.0 TacitCard.qml\n";
files["qs/modules/ii/overlay/qmldir"] += "StyledOverlayWidget 1.0 StyledOverlayWidget.qml\n";
files["qs/modules/common/widgets/widgetCanvas/qmldir"] += "AbstractWidget 1.0 AbstractWidget.qml\nAbstractOverlayWidget 1.0 AbstractOverlayWidget.qml\n";

function run(steps) {
  const scene = `import QtQuick
import QtTest
import qs
import qs.modules.common
import qs.modules.ii.overlay
import "crosshair"
Item {
    id: screen
    width: 1920; height: 1080
    StyledOverlayWidget {
        id: notes
        modelData: ({ identifier: "notes", label: "Notes" })
        contentItem: Item { implicitWidth: 250; implicitHeight: 100 }
    }
    Crosshair {
        id: cross
        modelData: ({ identifier: "crosshair", label: "Crosshair" })
    }
    // where a widget's content is on the screen (a crosshair's is centred in its body), and the body's size
    function body(w) { const c = w.contentItem, p = c.mapToItem(screen, 0, 0); return { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(c.parent.width), h: Math.round(c.parent.height) } }
    TestCase {
        name: "overlay"; when: windowShown
        function test_widgets() {
            const out = {}
            ${steps}
            console.log("OVERLAY " + JSON.stringify(out))
        }
    }
}
`;
  return logged(runScene({ "tst_overlay.qml": scene, ...files }), "OVERLAY");
}
const at = b => `${b.x},${b.y}`;

// pinned, then the overlay closed to play: the header folds away over 450 ms, and the body should stay where it was
try {
  const r = run(`
            wait(100)
            out.notesOpen = body(notes); out.crossOpen = body(cross)
            GlobalStates.overlayOpen = false
            // while the header folds
            out.folding = []
            for (let i = 0; i < 8; i++) { wait(50); out.folding.push([body(notes).y, body(cross).y]) }
            wait(500)
            out.notesClosed = body(notes); out.crossClosed = body(cross)
            GlobalStates.overlayOpen = true
            wait(700)
            out.notesAgain = body(notes)`);
  check("Notes, pinned at 300,200: its body stays where it was when the overlay closes", at(r.notesClosed) === at(r.notesOpen),
    `at ${at(r.notesOpen)} open, ${at(r.notesClosed)} closed`);
  check("a crosshair moved off the middle: its mark stays where it was put when the overlay closes", at(r.crossClosed) === at(r.crossOpen),
    `at ${at(r.crossOpen)} open, ${at(r.crossClosed)} closed`);
  check("neither moves while the header folds", r.folding.every(([n, c]) => n === r.notesOpen.y && c === r.crossOpen.y),
    `Notes at y ${r.folding.map(f => f[0]).join(", ")}; the mark at y ${r.folding.map(f => f[1]).join(", ")}`);
  check("Notes is back in the same place when the overlay opens again", at(r.notesAgain) === at(r.notesOpen), `at ${at(r.notesAgain)}`);
} catch (e) {
  check("the pinned scene ran", false, String(e.message ?? e));
}

// resized by its left border (which moves it as it goes), then pinned with the overlay closed
try {
  const r = run(`
            wait(100)
            mousePress(screen, 303, 290, Qt.LeftButton)
            for (let i = 1; i <= 10; i++) mouseMove(screen, 303 - 5 * i, 290, 10, Qt.LeftButton)
            mouseRelease(screen, 253, 290, Qt.LeftButton)
            wait(100)
            out.open = body(notes)
            GlobalStates.overlayOpen = false
            wait(700)
            out.closed = body(notes)`);
  check("resized 50 px wider by its border, the body grows to the left", r.open.w === 300 && r.open.x === 270, `${r.open.w} wide at ${at(r.open)}`);
  check("and it stays where it is when the overlay closes", at(r.closed) === at(r.open), `at ${at(r.open)} open, ${at(r.closed)} closed`);
} catch (e) {
  check("the resized scene ran", false, String(e.message ?? e));
}

// one plain click on its 8 px border (the resize arrow showing), then a drag by its title: the drag moves it
try {
  const r = run(`
            wait(100)
            out.before = body(notes)
            mouseClick(screen, 303, 290, Qt.LeftButton)
            mousePress(screen, 450, 225, Qt.LeftButton)
            for (let i = 1; i <= 10; i++) mouseMove(screen, 450 + 10 * i, 225 + 5 * i, 10, Qt.LeftButton)
            mouseRelease(screen, 550, 275, Qt.LeftButton)
            wait(100)
            out.after = body(notes)`);
  const moved = { x: r.after.x - r.before.x, y: r.after.y - r.before.y };
  check("after a click on its border, a drag by its title moves Notes", moved.x === 100 && moved.y === 50 && r.after.w === r.before.w && r.after.h === r.before.h,
    `moved by ${moved.x},${moved.y}, from ${r.before.w} x ${r.before.h} to ${r.after.w} x ${r.after.h}`);
} catch (e) {
  check("the border click scene ran", false, String(e.message ?? e));
}

done();
