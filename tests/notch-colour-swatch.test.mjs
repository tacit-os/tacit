// The swatch beside a copied colour in the notch's recent rows (modules/ii/island/IslandContent.qml, services/Recents.qml):
// the swatch's own colour binding, with Recents.swatch() from the tree when it has one, run under Qt's qml tool offscreen
// for each hex Recents.kindOf() takes for a colour; the colour Qt paints is read back. Qt reads eight digits as
// #AARRGGBB, while CSS and design tools write #RRGGBBAA.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the swatch of a copied colour (IslandContent.qml, Recents.qml)");
const recents = read("services/Recents.qml");
const block = objectWith(read("modules/ii/island/IslandContent.qml"), "id: swatch");
const at = block.search(/\n\s*color:/);
const colour = readExpression(block, block.indexOf(":", at) + 1).expr;
const swatch = qmlFunction(recents, "swatch");
const kindOf = qmlFunction(recents, "kindOf");
const kind = text => inScope({ root: { isSecret: () => false } }, kindOf.params, kindOf.body)(text);
const stubs = module("qs.services", { Recents: `QtObject {${swatch ? ` function swatch(${swatch.params}) {${swatch.body}}` : ""} }` });

// text copied -> the colour it means, as 0-255 channels
const cases = [
  ["#ff000080", [255, 0, 0, 128]],
  [" #1E90FFCC\n", [30, 144, 255, 204]],
  ["#3b82f6", [59, 130, 246, 255]],
  ["#fff", [255, 255, 255, 255]],
];
for (const [text, want] of cases) {
  check(`${JSON.stringify(text)} is taken for a colour`, kind(text) === "color");
  const scene = `import QtQuick
import qs.services
Item {
    property var recentRow: ({ item: { text: ${JSON.stringify(text)}, kind: "color" } })
    Rectangle { id: swatch; visible: true; color: ${colour} }
    Component.onCompleted: { const c = swatch.color; console.log("SWATCH " + JSON.stringify([c.r, c.g, c.b, c.a].map(v => Math.round(v * 255)))); Qt.quit() }
}
`;
  try {
    const got = logged(runScene({ "swatch.qml": scene, ...stubs }), "SWATCH");
    check(`${JSON.stringify(text)} paints as ${want.join(", ")}`, JSON.stringify(got) === JSON.stringify(want), `painted ${got.join(", ")}`);
  } catch (e) {
    check(`the scene for ${JSON.stringify(text)} ran`, false, String(e.message ?? e));
  }
}
done();
