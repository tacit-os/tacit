// Super+G's Image widget shows a picture whose name has a # or ? in it (modules/ii/overlay/floatingImage/
// FloatingImage.qml): the widget's own onDone, which hands the measured picture to its AnimatedImage, run under Qt's qml
// tool offscreen with a real GIF of each name and the tree's FileUtils.fileUrl(); what the AnimatedImage loaded is read.
import { mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { qmlFunction, readExpression } from "./lib/qml.mjs";
import { logged, module, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the Image widget's picture by name (FloatingImage.qml)");
const src = read("modules/ii/overlay/floatingImage/FloatingImage.qml");
const handler = readExpression(src, src.indexOf("onDone:") + "onDone:".length).expr;
const url = qmlFunction(read("modules/common/functions/FileUtils.qml"), "fileUrl");
const stubs = module("qs.modules.common.functions", { FileUtils: `QtObject { function fileUrl(${url.params}) {${url.body}} }` });
// a 1 x 1 GIF
const gif = Buffer.from("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7", "base64");

const dir = mkdtempSync(join(tmpdir(), "tacit-picture-"));
try {
  for (const name of ["Holiday.gif", "Holiday #3.gif", "what?.gif", "100% done.gif"]) {
    const path = join(dir, name);
    writeFileSync(path, gif);
    const scene = `import QtQuick
import qs.modules.common.functions
Item {
    QtObject { id: root; property int imageWidth: 0; property int imageHeight: 0 }
    AnimatedImage { id: animatedImage; source: "" }
    function done(path, width, height) { (${handler})(path, width, height) }
    Timer { interval: 50; running: true; onTriggered: done(${JSON.stringify(path)}, 1, 1) }
    Timer { interval: 500; running: true; onTriggered: { console.log("PICTURE " + JSON.stringify({ ready: animatedImage.status === AnimatedImage.Ready, frame: animatedImage.frameCount, source: String(animatedImage.source) })); Qt.quit() } }
}
`;
    try {
      const r = logged(runScene({ "picture.qml": scene, ...stubs }), "PICTURE");
      check(`"${name}" is shown`, r.ready, `the widget loaded ${r.source}`);
    } catch (e) {
      check(`the scene for "${name}" ran`, false, String(e.message ?? e));
    }
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}
done();
