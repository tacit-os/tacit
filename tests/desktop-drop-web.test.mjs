// A picture or a link dragged from a web page onto the desktop: what the drop puts in the Desktop folder
// (services/DesktopIcons.qml put()) and what the hold over the desktop previews as the wallpaper
// (modules/ii/background/Background.qml's onEntered), the files' own code under node. A browser hands such a drag over as
// its https address (text/uri-list): there is no file to copy and no picture on disk to set.
import { inScope, matchBrace, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a web picture or link dropped on the desktop");
const icons = read("services/DesktopIcons.qml"), bg = read("modules/ii/background/Background.qml");
const fu = qmlFunction(read("modules/common/functions/FileUtils.qml"), "trimFileProtocol");
const FileUtils = { trimFileProtocol: inScope({}, fu.params, fu.body) };
const extensions = inScope({}, "", `return (${qmlProperty(read("services/Wallpapers.qml"), "extensions")});`)();
const url = s => ({ toString: () => s });
const web = url("https://example.org/images/sunset.jpg"), local = url("file:///home/a/Pictures/sunset%20sea.jpg");

function drop(urls) {
  const ran = [];
  const root = { dir: "/home/a/Desktop", run: (op, args, words) => ran.push({ op, args, words }) };
  const f = qmlFunction(icons, "put");
  inScope({ root, FileUtils, Files: { parent: p => p.replace(/\/[^/]*$/, "") }, Voice: { count: (n, w) => `${n} ${w}${n === 1 ? "" : "s"}` },
    Qt: { ControlModifier: 1, ShiftModifier: 2 } }, f.params, f.body)(urls, 0, false);
  return ran;
}
{
  const ran = drop([web]);
  check("a web picture dropped on the desktop starts no copy", ran.length === 0, JSON.stringify(ran));
  const both = drop([web, local]);
  check("dropped with a file, only the file is copied", both.length === 1 && JSON.stringify(both[0].args) === JSON.stringify(["keep", "/home/a/Desktop", "/home/a/Pictures/sunset sea.jpg"]),
    JSON.stringify(both));
}

// the wallpaper drop area's onEntered: a single picture held over the desktop arms the preview after a second
const at = bg.indexOf("onEntered:", bg.indexOf("id: wallpaperDropArea"));
const open = bg.indexOf("{", at);
const entered = bg.slice(open + 1, matchBrace(bg, open));
function hold(urls) {
  const area = { picture: "" };
  let dwell = false;
  inScope({ wallpaperDropArea: area, DesktopIcons: {}, CF: { FileUtils }, Wallpapers: { extensions }, dwellTimer: { restart: () => { dwell = true; } } },
    "drag", entered)({ hasUrls: true, urls, accepted: false });
  return { picture: area.picture, dwell };
}
{
  const h = hold([web]);
  check("a web picture held over the desktop is not previewed as the wallpaper", h.picture === "" && !h.dwell, JSON.stringify(h));
  const l = hold([local]);
  check("a picture from disk still is", l.picture === "/home/a/Pictures/sunset sea.jpg" && l.dwell, JSON.stringify(l));
}
done();
