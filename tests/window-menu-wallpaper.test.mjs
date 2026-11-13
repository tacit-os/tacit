// The window menu's mini screen with a wallpaper whose name has a #, ? or % in it (modules/ii/windowMenu/WindowMenu.qml):
// the file's own Image runs under Qt's qml tool offscreen, with the tree's FileUtils.qml, on pictures in the home folder.
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the window menu's mini screen for a wallpaper named with #, ? or % (WindowMenu.qml)");
const image = objectWith(read("modules/ii/windowMenu/WindowMenu.qml"), "readonly property string thumbnail:");
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64");

function load(name) {
  const scene = `import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
Item {
    width: 232; height: 145
    ${image.replace(/^Image\s*\{/, "Image {\n        id: mini")}
    Timer {
        interval: 400; running: true
        onTriggered: { console.log("MINI " + JSON.stringify({ ready: mini.status === Image.Ready, source: String(mini.source) })); Qt.quit() }
    }
}
`;
  return logged(runScene({
    "scene.qml": scene,
    ...module("qs.modules.common", { Config: `import QtCore
QtObject {
    readonly property string home: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace("file://", "")
    property var options: ({ background: { wallpaperPath: home + "/Pictures/" + ${JSON.stringify(name)}, thumbnailPath: "" } })
}` }),
    ...module("qs.services", { Wallpapers: `QtObject { function hiddenByWorkSafety(p) { return false } }` }),
    ...module("Quickshell", {}, { Singleton: "QtObject {}" }),
    "qs/modules/common/functions/FileUtils.qml": read("modules/common/functions/FileUtils.qml"),
    "qs/modules/common/functions/qmldir": "module qs.modules.common.functions\nsingleton FileUtils 1.0 FileUtils.qml\n",
    [`Pictures/${name}`]: png,
  }), "MINI");
}
try {
  for (const name of ["Trip #3.png", "100%.png", "Lake?.png"]) {
    const r = load(name);
    check(`"${name}" is drawn`, r.ready === true, `not loaded from ${r.source}`);
  }
  const plain = load("Lake.png");
  check("a plain name is drawn as before", plain.ready === true, `not loaded from ${plain.source}`);
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
