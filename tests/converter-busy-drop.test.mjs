// Pictures dropped on the image converter while it is busy stop there (modules/ii/background/widgets/images/
// ImageConverterWidget.qml): its DropArea's handlers and the desktop's wallpaperDropArea's under it
// (modules/ii/background/Background.qml) run under node, delivered as Qt 6.12 delivers a drag: QQuickDropArea accepts the
// enter before its entered handler runs, a handler may refuse it, and QQuickDeliveryAgentPrivate::deliverDragEvent then
// offers it to the next DropArea behind; the one that kept it gets the drop, which starts refused.
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a drop on the busy image converter (ImageConverterWidget.qml, Background.qml)");
const conv = objectWith(read("modules/ii/background/widgets/images/ImageConverterWidget.qml"), "keys: [\"text/uri-list\"]");
const desk = objectWith(read("modules/ii/background/Background.qml"), "id: wallpaperDropArea");
const handler = (block, name) => readExpression(block, block.indexOf(`${name}:`) + name.length + 1).expr;
const fu = qmlFunction(read("modules/common/functions/FileUtils.qml"), "trimFileProtocol");
const FileUtils = { trimFileProtocol: inScope({}, fu.params, fu.body) };
const extensions = inScope({}, "", `return (${qmlProperty(read("services/Wallpapers.qml"), "extensions")});`)();
const url = s => ({ toString: () => s });

function dropOn({ busy }) {
  const did = [];
  const converter = { busy, dropStatus: busy ? "converting" : "idle", statusMessage: "", enqueueFiles: () => did.push("converted") };
  const convScope = { root: converter, resetTimer: { start() {}, stop() {} }, Qt: { CopyAction: 1 } };
  const area = { picture: "", armed: false, settle() {} };
  const deskScope = { wallpaperDropArea: area, dwellTimer: { restart() {}, stop() {} }, CF: { FileUtils },
    Wallpapers: { extensions, startPreview() {}, stopPreview() {} }, bgRoot: { screen: null },
    DesktopIcons: { hidden: false, dropCount: 0, dropArmed: false, put: () => did.push("put on the Desktop") },
    IslandController: { wallpaperSet: () => did.push("set as the wallpaper") }, DropShelf: { show: () => did.push("parked") } };
  const areas = [["converter", convScope, conv], ["desktop", deskScope, desk]].map(([name, scope, block]) => ({ name,
    entered: inScope(scope, "", `return (${handler(block, "onEntered")});`)(),
    dropped: inScope(scope, "", `return (${handler(block, "onDropped")});`)() }));
  const urls = [url("file:///home/a/Pictures/b.png"), url("file:///home/a/Pictures/c.png")];
  // front to back: the converter's card lies over the desktop
  let target = null;
  for (const a of areas) {
    const drag = { hasUrls: true, urls, accepted: true, accept(action) { this.accepted = true; this.action = action; } };
    a.entered(drag);
    if (drag.accepted) { target = a; break; }
  }
  if (target) target.dropped({ hasUrls: true, urls, accepted: false, keyboardModifiers: 0, source: null, x: 0, y: 0, accept() { this.accepted = true; } });
  return { did, target: target?.name ?? "nothing", status: converter.dropStatus };
}

{
  const r = dropOn({ busy: true });
  check("a drop on the converter while it converts stops at its card", r.target === "converter", `the ${r.target} took the drag`);
  check("and puts nothing on the Desktop, sets no wallpaper and converts nothing", r.did.length === 0, r.did.join(", "));
  check("the run in progress keeps its status", r.status === "converting", r.status);
}
{
  const r = dropOn({ busy: false });
  check("idle, a drop on the converter converts the pictures there", r.target === "converter" && r.did.join() === "converted", `${r.target}: ${r.did.join(", ")}`);
}
done();
