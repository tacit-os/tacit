// A tiled window's tile dragged and dropped back on its own card in the workspace overview (modules/ii/overview/):
// OverviewWindow.qml's own place (initX, initY, with the ratio between the window's monitor and the overview's) and the
// place OverviewWidget.qml's updateWindowPosition timer binds the tile back to after the drop, run under node for a
// window on the overview's monitor and one on a monitor of another size.
import { inScope, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a tile dropped back in the overview (OverviewWidget.qml)");
const tile = read("modules/ii/overview/OverviewWindow.qml"), widget = read("modules/ii/overview/OverviewWidget.qml");
const delegate = widget.slice(widget.indexOf("delegate: OverviewWindow {"));
const timerAt = delegate.indexOf("onTriggered:", delegate.indexOf("id: updateWindowPosition"));
const onTriggered = readExpression(delegate, timerAt + "onTriggered:".length).expr;

// expr is a binding: a block with its own return, or an expression
const getter = (scope, expr) => inScope(scope, "", expr.startsWith("{") ? expr.slice(1, -1) : `return (${expr});`);

function dropped(monitor, overviewMonitor, at) {
  const bound = {};
  // the tile, its own ids (root) and the delegate's (monitor) in one scope, as the file's bindings see them
  const window = {
    windowData: { at, size: [1280, 720], floating: false }, monitorData: monitor, monitor, widgetMonitor: overviewMonitor,
    scale: 0.15, xOffset: 40, yOffset: 0,
    set x(f) { bound.x = f; }, set y(f) { bound.y = f; },
  };
  window.root = window;
  for (const name of ["widthRatio", "heightRatio", "initX", "initY"])
    Object.defineProperty(window, name, { get: getter(window, qmlProperty(tile, name)) });
  for (const name of ["xWithinWorkspaceWidget", "yWithinWorkspaceWidget"]) {
    const expr = qmlProperty(delegate, name);
    if (expr) Object.defineProperty(window, name, { get: getter(window, expr) });
  }
  const place = { x: window.initX, y: window.initY };
  getter({ window, Qt: { binding: f => f } }, onTriggered)();
  return { place, after: { x: bound.x(), y: bound.y() } };
}

const fhd = { id: 0, x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: 0, reserved: [0, 38, 0, 0] };
const qhd = { id: 1, x: 1920, y: 0, width: 2560, height: 1440, scale: 1, transform: 0, reserved: [0, 0, 0, 0] };
const say = r => `${Math.round(r.place.x)},${Math.round(r.place.y)} before, ${r.after.x},${r.after.y} after`;
{
  const r = dropped(fhd, fhd, [480, 300]);
  check("a window on the overview's own monitor goes back to its place", r.after.x === Math.round(r.place.x) && r.after.y === Math.round(r.place.y), say(r));
}
{
  const r = dropped(qhd, fhd, [1920 + 1280, 720]);
  check("a window on a 2560 x 1440 monitor, shown on a 1920 x 1080 one, goes back to its place",
    r.after.x === Math.round(r.place.x) && r.after.y === Math.round(r.place.y), say(r));
}
done();
