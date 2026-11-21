// Regression for BUG-2026-11-22T031000: after a bar off->on toggle the control panel
// background filled the window height while its content stayed at ~405px. Root cause:
// a Loader anchored conditionally to the screen-sized wrapper (anchors.bottom when bar off)
// stretched its item to the window height, and the stretch persisted through the toggle.
// The fix positions the Loader with an explicit `y`, which never stretches its item.
// This qtscene test proves the two geometries differ under an off->on transition: the
// anchored Loader keeps a window-sized item, the explicit-y Loader tracks implicitHeight.
import { matchBrace } from "./lib/qml.mjs";
import { logged, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== control panel loader geometry across a bar toggle (SidebarRight.qml)");
const src = read("modules/ii/sidebarRight/SidebarRight.qml");
const loaderAt = src.indexOf("id: sidebarContentLoader");
const loader = src.slice(loaderAt, matchBrace(src, src.indexOf("{", src.indexOf("Loader {", loaderAt - 32))) + 1);
const usesExplicitY = /y:\s*panelWindow\.barShown/.test(loader);
const hasConditionalAnchors = /anchors\s*:\s*\{[^}]*top:\s*panelWindow\.barShown[^}]*bottom:\s*panelWindow\.barShown/s.test(loader);
check("the loader is positioned with an explicit y", usesExplicitY, loader.slice(0, 400));
check("the loader no longer uses conditional top/bottom anchors", !hasConditionalAnchors, loader.slice(0, 400));

const scene = `import QtQuick
import QtTest
Item {
    width: 1200; height: 1000
    property bool barShown: true
    property int topGap: 8
    property int contentHeight: 405
    property int windowHeight: 1164

    // The fixed production approach: explicit y, no top/bottom anchors.
    Loader {
        id: fixedLoader
        width: 400
        y: barShown ? topGap : Math.max(0, windowHeight - (item?.implicitHeight ?? 0))
        height: item?.implicitHeight ?? 0
        sourceComponent: contentComp
    }
    Component {
        id: contentComp
        Item { implicitHeight: 405; implicitWidth: 400 }
    }
    // The old broken approach, for contrast: conditional bottom anchor stretches the item.
    Item {
        id: wrapper
        width: 400; height: 1164
        Loader {
            id: brokenLoader
            width: 400
            anchors.top: barShown ? parent.top : undefined
            anchors.bottom: barShown ? undefined : parent.bottom
            height: item?.implicitHeight ?? 0
            sourceComponent: contentComp
        }
    }
    TestCase {
        name: "geometry"; when: windowShown
        function test_geometry() {
            const out = {}
            barShown = false; out.offFixedH = fixedLoader.item.height; out.offBrokenH = brokenLoader.item.height
            barShown = true;  out.onFixedH  = fixedLoader.item.height; out.onBrokenH  = brokenLoader.item.height
            console.log("GEO " + JSON.stringify(out))
        }
    }
}
`;
try {
  const r = logged(runScene({ "tst_geometry.qml": scene }), "GEO");
  check("fixed loader keeps item at its implicitHeight with bar off", Math.abs(r.offFixedH - 405) <= 1, JSON.stringify(r));
  check("fixed loader keeps item at its implicitHeight with bar on", Math.abs(r.onFixedH - 405) <= 1, JSON.stringify(r));
  check("old anchored loader stretched the item in at least one bar state (the bug)", r.offBrokenH > 1000 || r.onBrokenH > 1000, JSON.stringify(r));
} catch (e) {
  check("qtscene ran", false, e.message);
}
done();
