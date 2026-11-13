// The keyboard layout's code in the bar's system icons keeps the colour of the icons beside it (modules/ii/bar/
// SystemIcons.qml): the indicator's Loader's onLoaded runs under node with a pretend item whose color, like a QML
// property, holds a value or a binding (Qt.binding), then the palette and the bar's style change.
import { inScope, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the layout code's colour in the bar after the palette changes (SystemIcons.qml)");
const src = read("modules/ii/bar/SystemIcons.qml");
const at = src.indexOf("onLoaded:", src.indexOf('source: "HyprlandXkbIndicator.qml"'));
const onLoaded = readExpression(src, at + "onLoaded:".length).expr;
const iconAt = src.indexOf("color:", src.indexOf("Network.materialSymbol"));
const iconColor = readExpression(src, iconAt + "color:".length).expr;

const colors = { colOnPrimary: "on-primary (old palette)", colOnLayer1: "on-layer1 (old palette)" };
const root = { isMaterial: false };
let held = null;
const item = { get color() { return typeof held === "function" ? held() : held; }, set color(v) { held = v; } };
const scope = { item, root, Appearance: { colors }, Qt: { binding: f => f } };
inScope(scope, "", `${onLoaded};`)();
const icon = () => inScope(scope, "", `return (${iconColor});`)();

check("loaded, the code has the icons' colour", item.color === icon(), `${item.color} beside ${icon()}`);
colors.colOnLayer1 = "on-layer1 (new wallpaper)";
check("after a new wallpaper's palette, it still has", item.color === icon(), `${item.color} beside ${icon()}`);
root.isMaterial = true;
check("after the bar's corner style changes, it still has", item.color === icon(), `${item.color} beside ${icon()}`);
done();
