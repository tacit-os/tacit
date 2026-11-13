// A clock widget shown only when locked leaves nothing on the unlocked desktop (modules/ii/background/widgets/clock/
// ClockWidget.qml): the widget's visible binding, its own or the one AbstractBackgroundWidget.qml gives it, runs under
// node, and so does the widget canvas's selectWithinRect() (WidgetCanvas.qml), the rubber band. An item that is not
// visible takes no pointer in Qt and is out of the widgets' input mask (Background.qml), so visible is what decides.
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a clock shown only when locked, on the unlocked desktop (ClockWidget.qml, WidgetCanvas.qml)");
const clock = read("modules/ii/background/widgets/clock/ClockWidget.qml");
const base = read("modules/ii/background/widgets/AbstractBackgroundWidget.qml");
// a root-level "visible:" (four spaces in), the clock's own or else the one it inherits
const own = src => { const m = /^ {4}visible:\s*/m.exec(src); return m ? readExpression(src, m.index + m[0].length).expr : null; };
const visibleExpr = own(clock) ?? own(base);
const opacityExpr = readExpression(base, base.search(/^ {4}opacity:/m) + "    opacity:".length).expr;

function widget({ onlyWhenLocked, locked = false, safety = false, lockedText = true }) {
  const options = { background: { widgets: { clock: { showOnlyWhenLocked: onlyWhenLocked, quote: { enable: false, text: "" } } } },
    lock: { showLockedText: lockedText, centerClock: false, showWidgets: true } };
  const scope = { Config: { options }, GlobalStates: { screenLocked: locked } };
  const root = { wallpaperSafetyTriggered: safety, visibleWhenLocked: true };
  scope.root = root;
  for (const name of ["shouldShow", "lockedShown"]) {
    const e = qmlProperty(clock, name);
    Object.defineProperty(root, name, { get: () => inScope(scope, "", `return (${e});`)() });
  }
  const opacity = inScope({ ...scope, visibleWhenLocked: true }, "", `return (${opacityExpr});`)();
  return inScope({ ...scope, opacity }, "", `return (${visibleExpr});`)();
}

check("with 'only when locked', the unlocked desktop has no clock to click, drag or select", widget({ onlyWhenLocked: true }) === false,
  "the widget is visible with its card hidden");
check("locked, it is there", widget({ onlyWhenLocked: true, locked: true }) === true);
check("with the wallpaper safety's line on it, it is there", widget({ onlyWhenLocked: true, safety: true }) === true);
check("a clock shown always is there", widget({ onlyWhenLocked: false }) === true);

// the rubber band over a hidden widget and a shown one
const select = qmlFunction(read("modules/common/widgets/widgetCanvas/WidgetCanvas.qml"), "selectWithinRect");
const intersects = (a, b) => a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
const hidden = { x: 100, y: 100, width: 336, height: 60, visible: false, enabled: true, selected: false };
const shown = { x: 500, y: 100, width: 200, height: 200, visible: true, enabled: true, selected: false };
inScope({ root: { registeredWidgets: [hidden, shown], rectsIntersect: intersects }, Qt: { rect: (x, y, width, height) => ({ x, y, width, height }) } },
  select.params, select.body)({ x: 0, y: 0, width: 800, height: 400 });
check("the rubber band does not pick up a hidden widget, which a group drag would then move", !hidden.selected);
check("and picks up a shown one", shown.selected);
done();
