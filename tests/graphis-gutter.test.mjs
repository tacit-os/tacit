// Graphis's line numbers stand beside their lines and 'Ln N' names the cursor's line when some lines are taller than
// the rest (modules/code/CodeDoc.qml): a line in Devanagari or Hebrew falls back to another font, whose line is taller
// than the code font's. The file's own gutter (numbers), its line-height and line properties run under Qt's
// qmltestrunner offscreen beside a TextEdit and Flickable set up as the file's are, scrolled below the tall lines.
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { matchBrace, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Graphis's line numbers stay beside their lines (CodeDoc.qml)");
const src = read("modules/code/CodeDoc.qml");
const prop = (type, name) => { const e = qmlProperty(src, name); return e === null ? "" : `readonly property ${type} ${name}: ${e}\n`; };
const fn = name => { const f = qmlFunction(src, name); return f ? `function ${name}(${f.params}) {${f.body}}\n` : ""; };
// the property's whole block when it is one ({ ... } over several lines)
const blockProp = (type, name) => {
  const at = src.indexOf(`readonly property ${type} ${name}: {`);
  if (at < 0) return prop(type, name);
  const open = src.indexOf("{", src.indexOf(":", at));
  return src.slice(at, matchBrace(src, open) + 1) + "\n";
};
const numbers = objectWith(src, "id: numbers");

// a file that opens with forty comment lines in other scripts, then code: 240 lines in all
const lines = Array.from({ length: 240 }, (_, i) => i < 40 ? `# टिप्पणी שלום ${i + 1}` : `    x_${i + 1} = compute(${i + 1})`);
const text = lines.join("\n") + "\n";

const scene = `import QtQuick
import QtTest
import qs.modules.common
Item {
    id: top
    width: 700; height: 420
    Item {
        id: doc
        anchors.fill: parent
        property string cached: area.text
        property int layoutTick: 0
        property var marks: ({})
        property bool wrap: false
        property string problem: ""
        property int fontSize: 15
        ${prop("real", "lineHeight")}
        ${prop("int", "gutter")}
        ${blockProp("var", "lineStarts")}
        ${fn("lineAt")}
        ${prop("int", "line")}
        FontMetrics { id: fm; font: area.font }
        ${numbers}
        Flickable {
            id: flick
            anchors { left: numbers.right; right: parent.right; top: parent.top; bottom: parent.bottom }
            clip: true
            topMargin: 6
            bottomMargin: height / 2
            contentHeight: area.contentHeight
            contentWidth: Math.max(width, area.contentWidth + 40)
            TextEdit {
                id: area
                textFormat: TextEdit.PlainText
                font.family: "Noto Sans Mono"
                font.pixelSize: doc.fontSize
                font.hintingPreference: Font.PreferNoHinting
                text: ${JSON.stringify(text)}
                onTextChanged: doc.layoutTick++
                onContentHeightChanged: doc.layoutTick++
            }
        }
    }
    TestCase {
        name: "gutter"; when: windowShown
        function starts() { const s = [0]; for (let i = area.text.indexOf("\\n"); i >= 0; i = area.text.indexOf("\\n", i + 1)) s.push(i + 1); return s; }
        function numbersShown(item, out) {
            for (const c of item.children) {
                if (c.visible && typeof c.text === "string" && /^\\d+$/.test(c.text)) {
                    const y = c.mapToItem(numbers, 0, 0).y;
                    if (y >= 0 && y < numbers.height - 30) out.push({ n: +c.text, y: Math.round(y) });
                }
                numbersShown(c, out);
            }
            return out;
        }
        function test_gutter() {
            const s = starts();
            const heights = s.slice(0, -1).map(o => area.positionToRectangle(o).height);
            flick.contentY = area.positionToRectangle(s[40]).y;      // line 41 at the top
            area.cursorPosition = s[47] + 4;                          // on line 48
            wait(100);
            const shown = numbersShown(numbers, []);
            const off = shown.filter(r => Math.abs(r.y - Math.round(area.positionToRectangle(s[r.n - 1]).y - flick.contentY)) > 1);
            console.log("GUTTER " + JSON.stringify({ tall: Math.max(...heights) > Math.min(...heights), heights: [Math.min(...heights), Math.max(...heights)],
                shown: shown.length, off: off.slice(0, 3).map(r => ({ n: r.n, at: r.y, line: Math.round(area.positionToRectangle(s[r.n - 1]).y - flick.contentY) })), line: doc.line }));
        }
    }
}
`;
const stubs = module("qs.modules.common", {
  Appearance: `QtObject { property var font: ({ family: { monospace: "Noto Sans Mono" } }); property var m3colors: ({ m3primary: "#88f", m3tertiary: "#8f8" }); property var colors: ({ colError: "#f88" }) }`,
  Tacit: `QtObject { property color inkMain: "#fff"; property color inkFaint: "#777" }`,
});
try {
  const r = logged(runScene({ "tst_gutter.qml": scene, ...stubs }), "GUTTER");
  if (!r.tall) console.log(`  skip  every line came out ${r.heights[0]} px high here (no fallback font taller than Noto Sans Mono): nothing to show`);
  else {
    check(`with lines of ${r.heights[0]} and ${r.heights[1]} px, every number on screen is beside its line`, r.shown > 10 && r.off.length === 0,
      r.shown > 10 ? `off: ${JSON.stringify(r.off)}` : `only ${r.shown} numbers on screen`);
    check("the status line names the cursor's line (48)", r.line === 48, `Ln ${r.line}`);
  }
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
