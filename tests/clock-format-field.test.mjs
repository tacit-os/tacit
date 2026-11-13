// Settings > General's clock format field (modules/ii/settings/pages/GeneralConfig.qml): the field's own block, with
// whatever it holds, under Qt's qml tool offscreen on a stand-in ConfigTextArea, typed into a key at a time with a pause
// before Enter; what reaches page.applyTimeFormat() (which saves the format and rewrites hyprlock.conf) is noted.
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the clock format field while it is typed in (GeneralConfig.qml)");
const field = objectWith(read("modules/ii/settings/pages/GeneralConfig.qml"), "id: clockFormatField");
const files = {
  ...module("qs.modules.common", { Config: `QtObject { property var options: ({ time: { format: "hh:mm" } }) }` }),
  ...module("qs.services", { Translation: `QtObject { function tr(s) { return s } }` }),
  ...module("qs.modules.common.widgets", {}, {
    ConfigTextArea: `Item { property string value; property string text; property string buttonIcon; property string placeholderText; property bool confirmButtonVisible; signal confirmClicked() }`,
  }),
};
const scene = `import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
Item {
    QtObject { id: page; property var applied: []; function applyTimeFormat(f) { applied = applied.concat([f]) } }
    ${field}
    property var typed: "hh:mm 'a".split("")
    property var seen: ({})
    Timer {
        interval: 30; repeat: true; running: true
        // a key every 30 ms, from an empty field
        property int at: 0
        onTriggered: { at++; clockFormatField.value = typed.slice(0, at).join(""); if (at === typed.length) stop() }
    }
    Timer { interval: 30 * 9 + 900; running: true; onTriggered: { seen.paused = page.applied; clockFormatField.confirmClicked() } }
    Timer { interval: 30 * 9 + 1000; running: true; onTriggered: { seen.entered = page.applied; console.log("CLOCK " + JSON.stringify(seen)); Qt.quit() } }
}
`;
try {
  const r = logged(runScene({ "clock.qml": scene, ...files }), "CLOCK");
  check("a pause in the typing applies nothing", r.paused.length === 0, `applied ${JSON.stringify(r.paused)}`);
  check("Enter applies what was typed, once", JSON.stringify(r.entered) === JSON.stringify(["hh:mm 'a"]), `applied ${JSON.stringify(r.entered)}`);
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
