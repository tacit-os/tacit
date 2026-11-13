// Ask's picture thumbnails (modules/ii/island/states/IslandAsk.qml): the attached chip's and the first-use list's Image
// source bindings, with the tree's FileUtils.fileUrl(), run under Qt's qml tool offscreen against real pictures whose
// names have a #, a ? or a % in them; whether each Image loaded is read back. A # starts a URL's fragment and a % an
// escape, so a path pasted after "file://" does not load.
import { mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { qmlFunction, readExpression } from "./lib/qml.mjs";
import { logged, module, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Ask's picture thumbnails by name (IslandAsk.qml)");
const src = read("modules/ii/island/states/IslandAsk.qml");
const source = id => {
  const at = src.indexOf("source:", src.indexOf(`id: ${id}`));
  return readExpression(src, at + "source:".length).expr;
};
const chip = source("chipThumb"), row = source("rowThumb");
const url = qmlFunction(read("modules/common/functions/FileUtils.qml"), "fileUrl");
const stubs = module("qs.modules.common.functions", { FileUtils: `QtObject { function fileUrl(${url.params}) {${url.body}} }` });
// a 1 x 1 PNG
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");

const dir = mkdtempSync(join(tmpdir(), "tacit-ask-thumb-"));
try {
  for (const name of ["Chart.png", "Chart #3.png", "50% off.png", "scan %41.png", "what?.png"]) {
    const path = join(dir, name);
    writeFileSync(path, png);
    const scene = `import QtQuick
import qs.modules.common.functions
Item {
    QtObject { id: chip; property bool thumb: true; property var modelData: ({ path: ${JSON.stringify(path)} }) }
    QtObject { id: row; property var modelData: ({ thumb: true, path: ${JSON.stringify(path)} }) }
    Image { id: chipThumb; source: ${chip} }
    Image { id: rowThumb; source: ${row} }
    Timer { interval: 400; running: true; onTriggered: { console.log("THUMBS " + JSON.stringify({ chip: chipThumb.status === Image.Ready, row: rowThumb.status === Image.Ready, source: String(chipThumb.source) })); Qt.quit() } }
}
`;
    try {
      const r = logged(runScene({ "thumbs.qml": scene, ...stubs }), "THUMBS");
      check(`"${name}" shows as an attached picture's chip`, r.chip, `the chip asked for ${r.source}`);
      check(`"${name}" shows in Ask's first-use list`, r.row);
    } catch (e) {
      check(`the scene for "${name}" ran`, false, String(e.message ?? e));
    }
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}
done();
