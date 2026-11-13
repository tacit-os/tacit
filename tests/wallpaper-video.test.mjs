// A live wallpaper is a video by its extension, in any case: the desktop (Background.qml), its widgets
// (AbstractBackgroundWidget.qml) and switchwall.sh, which starts mpvpaper, give the same answer for each name. Their
// bindings run under node, switchwall.sh's is_video() under bash.
import { spawnSync } from "child_process";
import { inScope, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== live wallpapers by extension (Background.qml, AbstractBackgroundWidget.qml, switchwall.sh)");

const names = ["/home/me/Videos/IMG_0001.MP4", "/home/me/Videos/clip.MOV", "/home/me/Videos/loop.WebM", "/home/me/Videos/rain.mp4",
  "/home/me/Pictures/dusk.jpg", "/home/me/Pictures/IMG_0002.JPG", "/home/me/Pictures/mp4.png"];

const sh = read("scripts/colors/switchwall.sh");
const isVideoSh = sh.match(/^is_video\(\) \{\n[\s\S]*?\n\}\n/m)[0];
const script = `${isVideoSh}for f in "$@"; do is_video "$f" && echo yes || echo no; done`;
const shSays = spawnSync("bash", ["-c", script, "_", ...names], { encoding: "utf8" }).stdout.trim().split("\n");

const bg = qmlProperty(read("modules/ii/background/Background.qml"), "wallpaperIsVideo");
const widget = qmlProperty(read("modules/ii/background/widgets/AbstractBackgroundWidget.qml"), "wallpaperIsVideo");
names.forEach((path, i) => {
  const mpv = shSays[i] === "yes";
  const desktop = inScope({ bgRoot: { effectiveWallpaperPath: path } }, "", `return (${bg});`)();
  const widgets = inScope({ Config: { options: { background: { wallpaperPath: path } } } }, "", `return (${widget});`)();
  const name = path.split("/").pop();
  check(`${name}: the desktop takes it for ${mpv ? "a video" : "a picture"}, as switchwall.sh does`, desktop === mpv, `the desktop says ${desktop ? "video" : "picture"}`);
  check(`${name}: the desktop's widgets take it for ${mpv ? "a video" : "a picture"}`, widgets === mpv, `they say ${widgets ? "video" : "picture"}`);
});

done();
