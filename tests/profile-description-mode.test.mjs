// The legacy panel's "Description text" choice after a click (modules/ii/settings/pages/Profile.qml): the page's
// descriptionMode binding and the choice's own block run under qmltestrunner offscreen, on a stand-in Config whose
// descriptionText a preset or a hand edit changes afterwards.
import { qmlProperty } from "./lib/qml.mjs";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the Description text choice after a click (Profile.qml)");
const src = read("modules/ii/settings/pages/Profile.qml");
const choice = objectWith(src, 'text: Translation.tr("Description text")');
const scene = `import QtQuick
import QtTest
import qs.services
import qs.modules.common
import qs.modules.common.widgets
Item {
    id: page
    property string descriptionMode: ${qmlProperty(src, "descriptionMode")}
    ${choice.replace(/^ConfigSelectionArray\s*\{/, "ConfigSelectionArray {\n        id: choice")}
    TestCase {
        name: "description"; when: windowShown
        function test_follows() {
            const out = {}
            choice.selected("uptime")
            out.saved = Config.options.profile.descriptionText
            out.afterClick = choice.currentValue
            Config.options.profile.descriptionText = "::distro::"   // a preset, or config.json edited
            out.afterEdit = choice.currentValue
            console.log("MODE " + JSON.stringify(out))
        }
    }
}
`;
try {
  const r = logged(runScene({
    "tst_description.qml": scene,
    ...module("qs.services", { Translation: `QtObject { function tr(s) { return s } }` }),
    ...module("qs.modules.common", { Config: `QtObject {
    property QtObject options: QtObject { property QtObject profile: QtObject { property string descriptionText: "::distro::" } }
}` }),
    ...module("qs.modules.common.widgets", {}, { ConfigSelectionArray: `Item {
    property string text; property string icon; property var options; property var currentValue
    signal selected(var newValue)
}` }),
  }), "MODE");
  check("choosing Uptime saves ::uptime:: and shows Uptime", r.saved === "::uptime::" && r.afterClick === "uptime", JSON.stringify(r));
  check("a preset that sets ::distro:: afterwards turns the row back to Distro", r.afterEdit === "distro", `the row shows ${r.afterEdit}`);
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
