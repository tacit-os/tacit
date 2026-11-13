// Settings > Bar > Show Frame (modules/ii/frame/ScreenFrame.qml): which strips and corners are drawn, run under node on
// the settings a new install has, with the bar loaded or not as IllogicalImpulseFamily.qml decides.
import { adapterDefaults, inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the screen frame (ScreenFrame.qml)");
const src = read("modules/ii/frame/ScreenFrame.qml");
const family = read("panelFamilies/IllogicalImpulseFamily.qml");
const defaults = () => adapterDefaults(read("modules/common/Config.qml"));

// a binding's value: an expression, or a { ... } block run as a function body
const value = (scope, expr) => inScope(scope, "", expr.startsWith("{") ? expr.slice(1, -1) : `return (${expr});`)();

function frame(options) {
  const root = {}, scope = { root, Config: { options } };
  for (const name of ["centerOnly", "barPosition", "barLoaded"]) {
    const e = qmlProperty(src, name);
    Object.defineProperty(root, name, { get: () => (e === null ? undefined : value(scope, e)) });
  }
  const f = qmlFunction(src, "frameVisibleFor");
  root.frameVisibleFor = inScope(scope, f.params, f.body);
  const cornerExpr = src.match(/visible:\s*(root\.frameVisibleFor\(cornerWidget[^\n]+)/)[1];
  const corner = (isTop, isLeft) => value({ root, cornerWidget: { isTop, isLeft } }, cornerExpr);
  return {
    strips: ["top", "bottom", "left", "right"].filter(s => root.frameVisibleFor(s)),
    corners: [[true, true, "top-left"], [true, false, "top-right"], [false, true, "bottom-left"], [false, false, "bottom-right"]]
      .filter(([t, l]) => corner(t, l)).map(c => c[2]),
  };
}
// the bar IllogicalImpulseFamily loads for these settings, if any
function barLoaded(options) {
  const cond = component => value({ Config: { options } }, family.match(new RegExp(`PanelLoader \\{ extraCondition: (.+?); component: ${component} \\{\\} \\}`))[1]);
  return cond("Bar") || cond("VerticalBar");
}
const all = "top, bottom, left, right";
const allCorners = "top-left, top-right, bottom-left, bottom-right";

// a new install: no bar loaded (bar.enable off, the notch hides it), the bar's square-corner style
{
  const o = defaults();
  o.bar.showFrame = true;
  const f = frame(o);
  check("with no bar, Show Frame draws all four strips", f.strips.join(", ") === all, `it draws ${f.strips.join(", ")}`);
  check("with no bar, Show Frame draws all four corners", f.corners.join(", ") === allCorners, `it draws ${f.corners.join(", ")}`);
}
{
  const o = defaults();
  o.bar.showFrame = true;
  o.bar.vertical = true;   // the Bar page's switch: the bar's edge is the left one now, still with no bar
  const f = frame(o);
  check("with no bar and the bar set vertical, all four strips are drawn", f.strips.join(", ") === all, `it draws ${f.strips.join(", ")}`);
}
// a loaded bar in the square-corner style lies along its edge itself: the strip there stays off, as before
{
  const o = defaults();
  Object.assign(o.bar, { showFrame: true, enable: true });
  o.island.hideBar = false;
  const f = frame(o);
  check("with the bar loaded at the top, the frame leaves the top edge to it", f.strips.join(", ") === "bottom, left, right" && f.corners.join(", ") === "bottom-left, bottom-right",
    `strips ${f.strips.join(", ")}; corners ${f.corners.join(", ")}`);
  o.bar.vertical = true;
  const v = frame(o);
  check("with the vertical bar loaded, the frame leaves the left edge to it", v.strips.join(", ") === "top, bottom, right", `it draws ${v.strips.join(", ")}`);
}
// the frame's idea of the bar is the family's: every combination of the switches that decide it
{
  const wrong = [];
  for (const enable of [false, true]) for (const vertical of [false, true]) for (const hideBar of [false, true]) {
    const o = defaults();
    Object.assign(o.bar, { showFrame: true, enable, vertical });
    o.island.hideBar = hideBar;
    const loaded = barLoaded(o);
    const edge = vertical ? "left" : "top";
    if (frame(o).strips.includes(edge) === loaded) wrong.push(`enable ${enable}, vertical ${vertical}, hideBar ${hideBar}: bar ${loaded ? "loaded" : "not loaded"}`);
  }
  check("the bar's edge has a strip exactly when IllogicalImpulseFamily loads no bar there", wrong.length === 0, wrong.join("; "));
}

done();
