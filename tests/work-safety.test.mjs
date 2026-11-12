// Work safety on every view of the wallpaper: the desktop's own rule (Background.qml's wallpaperSafetyTriggered), then
// the centred shape's picture, the desktop menu's pictures and the window menu's small screen, each binding run under
// node on a flagged picture while on a flagged network. None may show it.
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== work safety on every view of the wallpaper");
const flagged = "/home/a/Pictures/Wallpapers/nsfw/beach.png", plain = "/home/a/Pictures/Wallpapers/dunes.png";
const Config = { options: {
  workSafety: { enable: { wallpaper: true }, triggerCondition: { fileKeywords: ["nsfw"], networkNameKeywords: ["company"] } },
  background: { wallpaperPath: flagged, thumbnailPath: "" } } };
const Network = { networkName: "Company-Guest" };
const StringUtils = { stringListContainsSubstring: (s, list) => list.some(k => s.includes(k)) };
const FileUtils = { trimFileProtocol: p => String(p).replace(/^file:\/\//, ""), fileUrl: p => `file://${p}` };
// the Wallpapers singleton's rule, where this tree has one
const ws = qmlFunction(read("services/Wallpapers.qml"), "hiddenByWorkSafety");
const Wallpapers = { hiddenByWorkSafety: ws ? inScope({ Config, Network, StringUtils }, ws.params, ws.body) : () => false };
const scope = { Config, Network, Wallpapers, StringUtils, CF: { StringUtils, FileUtils }, FileUtils };
// a binding's value: an expression, or a { ... return } block
const run = (names, expr) => inScope(names, "", expr.startsWith("{") ? expr.slice(1, -1) : `return (${expr});`)();

// the desktop itself
const bg = read("modules/ii/background/Background.qml");
const bgRoot = { wallpaperPath: flagged, pictureOf: p => p };
const triggered = run({ ...scope, ...bgRoot, bgRoot }, qmlProperty(bg, "wallpaperSafetyTriggered"));
check("the desktop hides a flagged picture on a flagged network", triggered === true);
bgRoot.wallpaperSafetyTriggered = triggered;

// the centred shape: the StyledImage inside centeredWallpaperShapeItem
const shapeAt = bg.indexOf("source:", bg.indexOf("StyledImage {", bg.indexOf("id: centeredWallpaperShapeItem")));
const shape = run({ ...scope, bgRoot }, readExpression(bg, shapeAt + "source:".length).expr);
check("the centred wallpaper shape does not draw it", !String(shape).includes("beach"), `source "${shape}"`);

// the desktop menu's pictures: the current wallpaper and others from its folder
const dm = read("modules/ii/desktopMenu/DesktopMenu.qml");
const dmRoot = { randomWallpapers: ["/home/a/Pictures/Wallpapers/nsfw/night.png", plain], displayPathFor: p => p };
const model = run({ ...scope, root: dmRoot, ...dmRoot }, qmlProperty(dm, "carouselModel"));
check("the desktop menu's pictures leave out every flagged one", model.length > 0 && !model.some(p => p.includes("nsfw")),
  JSON.stringify(model));

// the window menu's small screen
const wm = read("modules/ii/windowMenu/WindowMenu.qml");
const imgAt = wm.indexOf("source:", wm.indexOf("readonly property string wallpaper:"));
const img = { wallpaper: flagged, thumbnail: "", path: flagged };
const mini = run({ ...scope, ...img }, readExpression(wm, imgAt + "source:".length).expr);
check("the window menu's small screen does not draw it", !String(mini).includes("beach"), `source "${mini}"`);

// off the flagged network the picture shows again everywhere
Network.networkName = "home";
check("off the flagged network the desktop shows the picture",
  run({ ...scope, ...bgRoot, bgRoot }, qmlProperty(bg, "wallpaperSafetyTriggered")) === false);

// picking a card applies that card's picture; the current live wallpaper's card (its still) applies the wallpaper
{
  const picked = [];
  const pickAt = dm.indexOf("onPicked:");
  const names = { ...scope, Wallpapers: { ...Wallpapers, select: p => picked.push(p) }, GlobalStates: {},
    Appearance: { m3colors: { darkmode: true } }, root: { displayPathFor: p => (p.endsWith(".mp4") ? "/cache/live.png" : p) } };
  const onPicked = inScope(names, "", `return (${readExpression(dm, pickAt + "onPicked:".length).expr});`)();
  Config.options.background.wallpaperPath = "/home/a/Videos/live.mp4";
  onPicked("/cache/live.png", 0);
  onPicked(plain, 0);       // the first card when work safety left the current wallpaper out
  check("a picked card applies its own picture, the live wallpaper's still the wallpaper",
    picked.join() === `/home/a/Videos/live.mp4,${plain}`, picked.join());
}
done();
