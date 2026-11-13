// The legacy panel's avatar folder typed with ~ (modules/ii/settings/pages/Profile.qml): the page's FolderListModel, with
// the property it reads the folder from, runs under Qt's qml tool offscreen on a home folder holding two pictures, with
// the tree's FileUtils.qml; the Avatar path field's open button runs under node.
import { inScope, matchBrace, qmlProperty } from "./lib/qml.mjs";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the avatar folder typed with ~ (Profile.qml)");
const src = read("modules/ii/settings/pages/Profile.qml");
const model = objectWith(src, "id: avatarFolderModel");
const folderProp = qmlProperty(src, "avatarFolder");

function avatars(path) {
  const scene = `import QtQuick
import Qt.labs.folderlistmodel
import qs.modules.common
import qs.modules.common.functions
Item {
    id: page
    ${folderProp ? `readonly property string avatarFolder: ${folderProp}` : ""}
    ${model}
    Timer {
        interval: 400; running: true
        onTriggered: { console.log("AVATARS " + JSON.stringify({ count: avatarFolderModel.count, folder: String(avatarFolderModel.folder) })); Qt.quit() }
    }
}
`;
  return logged(runScene({
    "scene.qml": scene,
    ...module("qs.modules.common", {
      Config: `QtObject { property var options: ({ profile: { avatarPath: ${JSON.stringify(path)} } }) }`,
      Directories: `import QtCore
QtObject { readonly property string home: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0] }`,
    }),
    ...module("Quickshell", {}, { Singleton: "QtObject {}" }),
    "qs/modules/common/functions/FileUtils.qml": read("modules/common/functions/FileUtils.qml"),
    "qs/modules/common/functions/qmldir": "module qs.modules.common.functions\nsingleton FileUtils 1.0 FileUtils.qml\n",
    "Pictures/avatars/cat.png": "png",
    "Pictures/avatars/dog.jpg": "jpg",
    "Pictures/My avatars/fox.png": "png",
  }), "AVATARS");
}

try {
  const r = avatars("~/Pictures/avatars");
  check("~/Pictures/avatars shows the two pictures in it", r.count === 2, `${r.count} shown, from ${r.folder}`);
  const gone = avatars("/nonexistent-home/Pictures/avatars");
  check("a folder that is not there shows none", gone.count === 0, `${gone.count} shown`);
  const spaced = avatars("~/Pictures/My avatars");
  check("~/Pictures/My avatars, with a space, shows its picture", spaced.count === 1, `${spaced.count} shown, from ${spaced.folder}`);
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}

// the field's open button: the folder Files opens
{
  const at = src.indexOf("onConfirmClicked:", src.indexOf("id: avatarField")), open = src.indexOf("{", at);
  const body = src.slice(open + 1, matchBrace(src, open));
  const opened = [];
  const Config = { options: { profile: { avatarPath: "~/Pictures/avatars" } } };
  const page = { avatarFolder: folderProp ? inScope({ Config, FileUtils: { trimFileProtocol: s => s.replace(/^file:\/\//, "") }, Directories: { home: "file:///home/ana" } }, "", `return (${folderProp});`)() : undefined };
  inScope({ page, Config, GlobalStates: {}, Files: { open: f => opened.push(f) } }, "", body)();
  check("its open button opens /home/ana/Pictures/avatars", opened[0] === "/home/ana/Pictures/avatars", JSON.stringify(opened));
}
done();
