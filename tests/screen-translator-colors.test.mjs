// The screen translator reads its paragraphs' colours from the capture with one run of text_color.py, not one each
// (modules/ii/screenTranslator/ScreenTextOverlay.qml): the file's own paragraph components, its Repeater and its colour
// sampling, on the tree's MultiTurnProcess, under Qt's qml tool offscreen with a stand-in Process that notes every
// command it is given and answers as the script would. 30 paragraphs, 25 of them translated.
import { matchBrace, qmlFunction } from "./lib/qml.mjs";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the screen translator's colours, for a page of text (ScreenTextOverlay.qml)");
const src = read("modules/ii/screenTranslator/ScreenTextOverlay.qml");
const component = name => { const at = src.indexOf(`component ${name}:`); return src.slice(at, matchBrace(src, src.indexOf("{", at)) + 1); };
// the root's colour sampling, where the file has one
const sampling = src.includes("id: colorSampler")
  ? [/^    property var colorWaiting:.*$/m.exec(src)[0], `function sampleColors() {${qmlFunction(src, "sampleColors").body}}`, objectWith(src, "id: colorSampler")].join("\n")
  : "";
const escape = qmlFunction(read("modules/common/functions/StringUtils.qml"), "shellSingleQuoteEscape");

const files = {
  ...module("qs.modules.common", {
    Appearance: `QtObject { property var colors: ({ colSecondaryContainer: "#333" }); property var animation: ({ elementMoveFast: { colorAnimation: { createObject: () => null } } }) }`,
  }),
  ...module("qs.modules.common.functions", {
    ColorUtils: `QtObject { function transparentize(c, a) { return c } }`,
    StringUtils: `QtObject { function shellSingleQuoteEscape(${escape.params}) {${escape.body}} }`,
  }),
  ...module("qs.modules.common.widgets", {}, { SqueezedAnnotationStyledText: `Text { property real scaleFactor }` }),
  ...module("qs.modules.common.utils", {}, { Unused: `Item {}` }),
  "qs/modules/common/utils/MultiTurnProcess.qml": read("modules/common/utils/MultiTurnProcess.qml"),
  // a process notes its command and answers a moment later as text_color.py would: one colour for a crop piped to it,
  // a list of them for boxes given as arguments
  ...module("Runs", {
    Runs: `QtObject {
    property var commands: []
    function answer(command) {
        commands = commands.concat([command]);
        const one = { background: "#102030", text: "#f0f0f0" };
        return JSON.stringify(command.join(" ").includes("magick") ? one : command.slice(2).map(b => one));
    }
}`,
  }),
  ...module("Quickshell.Io", {}, {
    StdioCollector: `QtObject { property string text; signal streamFinished() }`,
    Process: `import Runs
Item {
    id: p
    property var command: []
    property bool running: false
    property QtObject stdout
    function finish() { p.stdout.text = Runs.answer(p.command); p.stdout.streamFinished(); p.running = false }
    onRunningChanged: if (running) Qt.callLater(p.finish)
}`,
  }),
};
files["qs/modules/common/utils/qmldir"] += "MultiTurnProcess 1.0 MultiTurnProcess.qml\n";

const paragraphs = Array.from({ length: 30 }, (_, i) => ({
  text: `p${i}`, boundingBox: { vertices: [{ x: 10, y: 20 * i }, { x: 300, y: 20 * i }, { x: 300, y: 20 * i + 18 }, { x: 10, y: 20 * i + 18 }] } }));
const translation = Object.fromEntries(paragraphs.slice(0, 25).map(p => [p.text, `t${p.text}`]));
const scene = `import QtQuick
import Runs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils
import qs.modules.common.widgets
Item {
    id: root
    width: 800; height: 700
    property real scaleFactor: 1
    property real monitorScale: 1
    property string screenshotPath: "/tmp/shot.png"
    readonly property string textColorDetectionScriptPath: "/shell/scripts/images/text-color-venv.sh"
    property bool loading: true
    property var visionParagraphs: ${JSON.stringify(paragraphs)}
    property var translation: (${JSON.stringify(translation)})
    function translate(s) { return translation[s] ?? s }
    ${sampling}
    Item {
        id: textItems
        Repeater {
            model: root.loading ? [] : root.visionParagraphs
            delegate: TextItem {}
        }
    }
    ${component("VisionBoundingBoxRect")}
    ${component("TextItem")}
    Timer { interval: 50; running: true; onTriggered: root.loading = false }
    Timer {
        interval: 800; running: true
        onTriggered: {
            const items = textItems.children.filter(c => c.translatedText !== undefined);
            console.log("COLORS " + JSON.stringify({ runs: Runs.commands.length, first: Runs.commands[0], items: items.length,
                colored: items.filter(t => String(t.color) === "#102030").length }));
            Qt.quit();
        }
    }
}
`;
try {
  const r = logged(runScene({ "colors.qml": scene, ...files }), "COLORS");
  check("30 paragraphs, 25 translated: one run of the colour script", r.runs === 1, `${r.runs} runs`);
  check("which is given the capture and the 25 translated paragraphs' boxes",
    r.first?.[1] === "/tmp/shot.png" && r.first?.length === 27 && r.first?.[2] === "10,0,290,18", JSON.stringify(r.first));
  check("and each of them takes its colours", r.items === 30 && r.colored === 25, `${r.colored} of ${r.items} coloured`);
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
