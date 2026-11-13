// A press on another monitor while the notch's sheet holds the keyboard (modules/ii/island/Island.qml): the file's
// click-away catchers (the windows with a press handler), the screens each covers, whether it shows and what its press
// and wheel do, all the file's own expressions run under node with two screens, the notch on the first. Ask holds the
// keyboard exclusively, so a click on a window on the other screen cannot take it back: something there has to fold it.
import { inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the notch's sheet and a press on another monitor (Island.qml)");
const src = read("modules/ii/island/Island.qml");

// the innermost object around index at: its type and its brackets
function around(at) {
  for (let i = at, depth = 0; i >= 0; i--) {
    if (src[i] === "}") depth++;
    else if (src[i] === "{" && depth-- === 0)
      return { type: (src.slice(0, i).match(/([\w.]+)\s*$/) ?? [])[1], open: i, close: matchBrace(src, i) };
  }
  return null;
}
// "<name>:" in the object's own lines (not its children's), as text, or null
function own(obj, name) {
  const re = new RegExp(`\\b${name}\\s*:`, "g");
  for (let m; (m = re.exec(src)) && m.index < obj.close;) {
    if (m.index < obj.open) continue;
    const at = around(m.index);
    if (at && at.open === obj.open) return readExpression(src, m.index + m[0].length).expr;
  }
  return null;
}
const windows = [...src.matchAll(/\bPanelWindow\s*\{/g)].map(m => around(m.index + m[0].length));
const catchers = windows.filter(w => {
  const body = src.slice(w.open, w.close);
  return /\bonPressed\s*:/.test(body) && !/\bPanelWindow\s*\{/.test(body);
});
check("the file has its click-away catchers", catchers.length > 0);

const A = { name: "eDP-1" }, B = { name: "HDMI-A-1" };
const run = (scope, expr) => /^\{/.test(expr) ? inScope(scope, "", expr.slice(1, -1))() : inScope(scope, "", `return (${expr});`)();
function desk({ view, holdsKeys }) {
  const content = { open: true, view, pinnedUntilVisit: true };
  const islandRoot = { screen: A, clickAway: true, holdsKeys, WlrLayershell: { layer: 2 } };
  const away = qmlFunction(src, "away");
  if (away) islandRoot.away = inScope({ islandContent: content }, away.params, away.body);
  const scope = { islandRoot, islandContent: content, Quickshell: { screens: [A, B] } };
  // each catcher: the screens it is on, while it shows
  const shown = catchers.flatMap(w => {
    const parent = around(w.open - 1);
    const model = parent?.type === "Variants" ? run(scope, own(parent, "model")) : [null];
    return Array.from(model).map(modelData => {
      const s = { ...scope, modelData };
      const visible = own(w, "visible");
      return { screen: run(s, own(w, "screen") ?? "null"), visible: visible === null || Boolean(run(s, visible)), w, s };
    });
  }).filter(c => c.visible);
  const on = screen => shown.find(c => c.screen?.name === screen.name);
  const act = (screen, handler) => {
    const c = on(screen);
    const expr = c && own(around(src.indexOf("onPressed", c.w.open)), handler);
    if (expr) run(c.s, expr);
    return content;
  };
  return { on, act, content };
}

{
  const d = desk({ view: "ask", holdsKeys: true });
  check("Ask open on the laptop has a catcher on its own screen", !!d.on(A));
  check("and one on the other monitor while it holds the keyboard", !!d.on(B));
  check("a press there folds Ask, as Esc does", d.act(B, "onPressed").open === false);
}
{
  const d = desk({ view: "ask", holdsKeys: true });
  check("a wheel turn there leaves Ask and its draft", d.on(B) && d.act(B, "onWheel").open === true);
  const h = desk({ view: "home", holdsKeys: true });
  check("the sheet from Super+Space folds on a wheel turn there", h.on(B) && h.act(B, "onWheel").open === false);
}
{
  const d = desk({ view: "home", holdsKeys: false });
  check("a sheet opened by a hover holds no keys and puts nothing on the other monitor", !d.on(B) && !!d.on(A));
  const expr = qmlProperty(src, "holdsKeys");
  const holds = focus => expr !== null && Boolean(inScope({ islandRoot: { WlrLayershell: { keyboardFocus: focus } },
    WlrKeyboardFocus: { None: 0, Exclusive: 1, OnDemand: 2 } }, "", `return (${expr});`)());
  check("the window holds the keys exactly while it asks for them exclusively", holds(1) && !holds(0) && !holds(2));
}
done();
