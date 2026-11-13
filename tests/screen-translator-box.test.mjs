// The screen translator's box over a paragraph (modules/ii/screenTranslator/ScreenTextOverlay.qml, its
// VisionBoundingBoxRect): the component's own properties run under node on Google Vision's vertices, which its JSON writes
// without a coordinate that is 0, as for a paragraph at the screen's left or top edge.
import { inScope, matchBrace, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the screen translator's box at the screen's edge (ScreenTextOverlay.qml)");
const src = read("modules/ii/screenTranslator/ScreenTextOverlay.qml");
const at = src.indexOf("component VisionBoundingBoxRect:");
const block = src.slice(at, matchBrace(src, src.indexOf("{", at)) + 1);

function box(vertices) {
  const item = { modelData: { boundingBox: { vertices } }, scaleFactor: 1, root: { monitorScale: 1, scaleFactor: 1 } };
  for (const name of ["boundingVertices", "unscaledX", "unscaledY", "unscaledWidth", "unscaledHeight"]) {
    const v = inScope(item, "", `return (${qmlProperty(block, name)});`)();
    // a property real takes no undefined: QML keeps its 0
    item[name] = name === "boundingVertices" ? v : v === undefined ? 0 : v;
  }
  for (const name of ["x", "y", "width", "height"]) {
    const m = new RegExp(`\\n\\s*${name}:\\s*([^\\n]+)`).exec(block);
    item[`shown_${name}`] = inScope(item, "", `return (${m[1]});`)();
  }
  return item;
}
const says = b => `${b.shown_x},${b.shown_y} ${b.shown_width} x ${b.shown_height}`;
{
  const b = box([{ x: 536, y: 236 }, { x: 583, y: 236 }, { x: 583, y: 262 }, { x: 536, y: 262 }]);
  check("a paragraph inside the screen gets its box", says(b) === "536,236 47 x 26", says(b));
}
{
  const b = box([{ y: 12 }, { x: 80, y: 12 }, { x: 80, y: 40 }, { y: 40 }]);
  check("one at the left edge (no x on its left vertices) gets its box", says(b) === "0,12 80 x 28", says(b));
}
{
  const b = box([{ x: 30 }, { x: 200 }, { x: 200, y: 18 }, { x: 30, y: 18 }]);
  check("one at the top edge (no y on its top vertices) gets its box", says(b) === "30,0 170 x 18", says(b));
}
done();
