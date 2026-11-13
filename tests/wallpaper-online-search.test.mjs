// A new online search in the wallpaper strip (modules/ii/wallpaperSelector/WallpaperStrip.qml): the search field's
// onAccepted and the strip's `current` run under node, the 15th of the old results pointed at, then the new results in.
import { inScope, qmlProperty, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a new online search in the wallpaper strip (WallpaperStrip.qml)");
const src = read("modules/ii/wallpaperSelector/WallpaperStrip.qml");
const field = objectWith(src, "id: searchField");
const accepted = readExpression(field, field.indexOf("onAccepted:") + "onAccepted:".length).expr;
const current = qmlProperty(src, "current");

const results = q => Array.from({ length: 24 }, (_, i) => ({ online: { provider: "wallhaven", id: `${q}-${i}` } }));
const root = { source: "online", pointed: 14, onlineState: "", items: results("forest") };
const OnlineWallpapers = { query: "forest", fetched: 0, fetch() { this.fetched++; root.items = []; } };
inScope({ root, OnlineWallpapers, text: "lake", strip: { forceActiveFocus() {} } }, "", accepted)();
check("Enter in the search box asks for the new results", OnlineWallpapers.query === "lake" && OnlineWallpapers.fetched === 1, JSON.stringify(OnlineWallpapers));
root.items = results("lake");   // they arrive
const shown = inScope({ root }, "", `return (${current});`)();
check("the picture pointed at is the first new result", root.pointed === 0 && shown?.online.id === "lake-0",
  `pointed ${root.pointed}: the preview and Enter act on ${shown?.online.id}`);
done();
