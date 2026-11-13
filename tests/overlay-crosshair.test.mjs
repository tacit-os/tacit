// The overlay's crosshair (modules/ii/overlay/crosshair/Crosshair.qml on StyledOverlayWidget.qml): where its mark is on
// screens other than the 1920x1080 its saved spot was picked on, with the overlay open (the 35 px header shown) and
// closed (no header, the crosshair pinned while playing). Its x and y bindings and Recenter run under node: Crosshair's
// own where it has them, else the widget's.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the crosshair's mark on any screen (Crosshair.qml)");
const cross = read("modules/ii/overlay/crosshair/Crosshair.qml"), base = read("modules/ii/overlay/StyledOverlayWidget.qml");
const persistent = read("modules/common/Persistent.qml");
const spot = /property JsonObject crosshair: JsonObject \{[^}]*?property real x: (\d+)[^}]*?property real y: (\d+)/.exec(persistent);
const fn = name => qmlFunction(cross, name) ?? qmlFunction(base, name);
// a binding written at the widget's top level ("    x: ..."), Crosshair's first
const binding = name => {
  for (const src of [cross, base]) {
    const m = new RegExp(`\\n    ${name}:`).exec(src);
    if (m) return readExpression(src, m.index + m[0].length).expr;
  }
};
const margin = 8, contentW = 250, contentH = 100;

// the widget on a W x H overlay with the header at header px: its size as StyledOverlayWidget lays it out (the
// crosshair has no padding), and the saved spot from Persistent's defaults
function widget(W, H, header, saved = { x: +spot[1], y: +spot[2] }) {
  const w = {
    persistentStateEntry: { ...saved, width: contentW, height: contentH, pinned: true, clickthrough: true },
    parent: { width: W, height: H }, headerHeight: header, resizeMargin: margin,
    get width() { return contentW + 2 * margin; }, get height() { return w.headerHeight + contentH + 2 * margin; },
    border: { column: { get width() { return contentW; } }, titleBar: { get implicitHeight() { return w.headerHeight; } } },
    contentContainer: { implicitWidth: contentW, implicitHeight: contentH, height: contentH },
    middleSpot: { x: +spot[1], y: +spot[2] },
    Qt: { binding: f => f, point: (x, y) => ({ x, y }) },
  };
  w.root = w;
  for (const name of ["onScreen", "shownX", "shownY", "savePosition", "center"]) {
    const f = fn(name);
    if (f) w[name] = inScope(w, f.params, f.body);
  }
  const inMiddle = /property bool inMiddle:/.test(cross) ? readExpression(cross, cross.indexOf("property bool inMiddle:") + 23).expr : "false";
  Object.defineProperty(w, "inMiddle", { get: inScope(w, "", `return (${inMiddle});`) });
  const bx = inScope(w, "", `return (${binding("x")});`), by = inScope(w, "", `return (${binding("y")});`);
  w.boundX = bx; w.boundY = by;
  // an assignment (Recenter) replaces the binding: a number stays, a Qt.binding follows
  Object.defineProperty(w, "x", { get: () => (typeof w.boundX === "function" ? w.boundX() : w.boundX), set: v => (w.boundX = v) });
  Object.defineProperty(w, "y", { get: () => (typeof w.boundY === "function" ? w.boundY() : w.boundY), set: v => (w.boundY = v) });
  // where the mark is: the middle of the content, under the header
  w.mark = () => ({ x: w.x + w.width / 2, y: w.y + margin + w.headerHeight + contentH / 2 });
  return w;
}

const off = (w, W, H) => { const m = w.mark(); return Math.max(Math.abs(m.x - W / 2), Math.abs(m.y - H / 2)); };
for (const [W, H] of [[2560, 1440], [1366, 768], [1920, 1080]]) {
  for (const header of [35, 0]) {
    const w = widget(W, H, header);
    const m = w.mark();
    check(`never moved, on ${W}x${H} with the overlay ${header ? "open" : "closed"}: the mark is in the middle`, off(w, W, H) <= 1,
      `at ${m.x},${m.y}, not ${W / 2},${H / 2}`);
  }
}

// one dragged away stays where it was put
{
  const w = widget(2560, 1440, 0, { x: 300, y: 200 });
  check("one dragged to 300,200 stays there", w.x === 300 && w.y === 200, `at ${w.x},${w.y}`);
}

// Recenter, pressed with the overlay open, then the overlay closed to play
for (const [W, H] of [[2560, 1440], [1920, 1080]]) {
  const w = widget(W, H, 35, { x: 300, y: 200 });
  w.center();
  w.headerHeight = 0;
  const m = w.mark();
  check(`Recenter on ${W}x${H}, then the overlay closed: the mark is in the middle`, off(w, W, H) <= 1, `at ${m.x},${m.y}, not ${W / 2},${H / 2}`);
}

done();
