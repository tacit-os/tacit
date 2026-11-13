// Setup's Welcome page with a language chosen from More languages (setup.qml): the page's own five language rows, with
// setupd.py's own list, under Qt's qml tool offscreen, beside setup.qml's own pickLanguage() and stand-ins for Setup's
// type and sizes. A language past the first five lit no row, and nothing on the page named it.
import { qmlFunction } from "./lib/qml.mjs";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the language chosen, on Setup's Welcome page (setup.qml)");
const src = read("setup.qml");
const rows = objectWith(src, "model: backend.languages.slice(0, 5)");
const pick = qmlFunction(src, "pickLanguage");
const list = read("scripts/setup/setupd.py").match(/^LANGUAGES = \[[\s\S]*?\]$/m)[0];
const languages = [...list.matchAll(/\("(\w+)", "([^"]+)", "(\w+)"\)/g)].map(([, code, name, layout]) => ({ code, name, layout }));

const files = {
  ...module("qs.modules.setup", { Look: `QtObject { property color main: "white"; property color meta: "grey"; function px(n) { return n } function fs(n) { return n } }` },
    { T: `Text {}` }),
};
const scene = `import QtQuick
import qs.modules.setup
Item {
    id: root
    QtObject { id: backend; property var languages: ${JSON.stringify(languages)} }
    QtObject {
        id: setup
        property string language: "en_GB"
        property string layout: "us"
        property bool layoutPicked: false
        readonly property var lang: backend.languages.find(l => l.code === language) ?? null
    }
    function pickLanguage(${pick.params}) {${pick.body}}
    Column { id: col; ${rows} }
    // the rows as the page shows them: each one's words and whether it is the chosen one
    function shown() {
        const out = [];
        for (let i = 0; i < col.children.length; i++) {
            const r = col.children[i];
            if (r.on !== undefined) out.push({ name: r.children[0].text, on: r.on, row: r });
        }
        return out;
    }
    function seen(rs) { return rs.map(r => (r.on ? "*" : "") + r.name) }
    Timer {
        interval: 0; running: true
        onTriggered: {
            const out = {};
            out.first = seen(shown());
            const before = shown().map(r => r.row);
            // More languages > Français (pickFrom(): its keyboard comes with it)
            setup.language = "fr_FR"; setup.layout = "fr";
            out.french = seen(shown());
            out.same = shown().every((r, i) => r.row === before[i]);
            // the fifth row pressed: still Français, still the keyboard's
            shown()[4].row.children[1].clicked(null);
            out.again = seen(shown()); out.layout = setup.layout;
            // English pressed: the fifth row is Deutsch again
            shown()[0].row.children[1].clicked(null);
            out.english = seen(shown());
            // one of the five from More languages: no row changes place
            setup.language = "de_DE";
            out.german = seen(shown());
            console.log("WELCOME " + JSON.stringify(out));
            Qt.quit();
        }
    }
}
`;
try {
  const r = logged(runScene({ "welcome.qml": scene, ...files }), "WELCOME");
  const five = languages.slice(0, 5).map(l => l.name);
  check("at the start, the first five, English chosen", JSON.stringify(r.first) === JSON.stringify(["*English", ...five.slice(1)]), r.first.join(", "));
  check("Français from More languages takes the fifth row's place, shown as chosen",
    JSON.stringify(r.french) === JSON.stringify([...five.slice(0, 4), "*Français"]), r.french.join(", "));
  check("the rows are the same items, so the keyboard stays on its row", r.same === true);
  check("pressing that row keeps Français and its keyboard", JSON.stringify(r.again) === JSON.stringify(r.french) && r.layout === "fr",
    `${r.again.join(", ")}; keyboard ${r.layout}`);
  check("English pressed: the fifth row is Deutsch again", JSON.stringify(r.english) === JSON.stringify(["*English", ...five.slice(1)]), r.english.join(", "));
  check("a language among the five, chosen from More languages, lights its own row",
    JSON.stringify(r.german) === JSON.stringify([...five.slice(0, 4), "*Deutsch"]), r.german.join(", "));
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
