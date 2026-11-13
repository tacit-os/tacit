// The visualizer widget takes no pointer (modules/ii/background/widgets/visualizer/VisualizerWidget.qml): it is a
// MouseArea (AbstractWidget.qml) as wide as the screen over its bottom 240 px, drawn or not. Its enabled, the widgets'
// input mask in Background.qml and the canvas's rubber band (WidgetCanvas.qml selectWithinRect) run under node. A
// MouseArea that is not enabled takes no press in Qt, so the press goes on to the desktop under it.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the visualizer's strip along the bottom of the desktop (VisualizerWidget.qml)");
const viz = read("modules/ii/background/widgets/visualizer/VisualizerWidget.qml");
const widget = read("modules/common/widgets/widgetCanvas/AbstractWidget.qml");
const rootLine = (src, key) => { const m = new RegExp(`^ {4}${key}:\\s*`, "m").exec(src); return m ? readExpression(src, m.index + m[0].length).expr : null; };
const value = (e, scope = {}) => inScope({ Qt: { NoButton: 0, LeftButton: 1, RightButton: 2 }, ...scope }, "", `return (${e});`)();
const enabled = rootLine(viz, "enabled") === null ? true : value(rootLine(viz, "enabled"));
const buttons = value(rootLine(viz, "acceptedButtons") ?? rootLine(widget, "acceptedButtons"));
check("the visualizer takes no press: a right click there opens the desktop menu, not 'lock positions'", !enabled || buttons === 0,
  `enabled ${enabled}, buttons ${buttons}`);

// the widgets' own window over a video wallpaper takes the pointer only where its mask is
const bg = read("modules/ii/background/Background.qml");
const regionAt = bg.indexOf("item:", bg.indexOf("id: widgetMasks"));
const region = readExpression(bg, regionAt + "item:".length).expr;
const strip = { visible: true, enabled, x: 0, y: 840, width: 1920, height: 240, selected: false };
check("it is out of the widgets' input mask over a video wallpaper", value(region, { modelData: strip }) === null, "its strip is in the mask");

const select = qmlFunction(read("modules/common/widgets/widgetCanvas/WidgetCanvas.qml"), "selectWithinRect");
const intersects = (a, b) => a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
inScope({ root: { registeredWidgets: [strip], rectsIntersect: intersects }, Qt: { rect: (x, y, width, height) => ({ x, y, width, height }) } },
  select.params, select.body)({ x: 100, y: 700, width: 400, height: 300 });
check("a rubber band across the bottom does not frame the whole strip", !strip.selected);
done();
