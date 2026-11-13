// The vertical bar's round corners under auto-hide (modules/ii/verticalBar/VerticalBar.qml): the round decorators'
// active, the centre pill's two corners' visible, and the window's showCorners and onMustShowChanged run under node as
// the bar hides, comes back and has auto-hide off (cb1b19d did this for the horizontal bar, Bar.qml).
import { inScope, matchBrace, qmlProperty, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the vertical bar's corners under auto-hide (VerticalBar.qml)");
const src = read("modules/ii/verticalBar/VerticalBar.qml");
const expr = (marker, key) => { const b = objectWith(src, marker); return readExpression(b, b.indexOf(`${key}:`) + key.length + 1).expr; };
const decorators = expr("id: roundDecorators", "active"), topPill = expr("id: topPillCorner", "visible"), bottomPill = expr("id: bottomPillCorner", "visible");
const showCorners = qmlProperty(src, "showCorners");
const changedAt = src.indexOf("onMustShowChanged:");
const onMustShowChanged = changedAt < 0 ? "" : src.slice(src.indexOf("{", changedAt) + 1, matchBrace(src, src.indexOf("{", changedAt)));
const timer = objectWith(src.includes("id: cornerRevealTimer") ? src : "Timer { id: cornerRevealTimer }", "id: cornerRevealTimer");
const onTriggered = timer.includes("onTriggered:") ? readExpression(timer, timer.indexOf("onTriggered:") + 12).expr : "";

function bar(autoHide) {
  const Config = { options: { bar: { autoHide: { enable: autoHide }, cornerStyle: 0 } } };
  const barRoot = { mustShow: false, cornersWaiting: false };
  Object.defineProperty(barRoot, "showCorners", { get: () => showCorners ? inScope({ Config, ...barRoot }, "", `return (${showCorners});`)() : undefined });
  const cornerRevealTimer = { running: false, restart() { this.running = true; }, stop() { this.running = false; } };
  const scope = { Config, barRoot, cornerRevealTimer, showBarBackground: true };
  const drawn = centerOnly => {
    const s = { ...scope, barContent: { centerOnly } };
    return centerOnly
      ? [topPill, bottomPill].map(e => inScope(s, "", `return (${e});`)()).every(Boolean)
      : inScope(s, "", `return (${decorators});`)();
  };
  return {
    drawn,
    show(v) { barRoot.mustShow = v; if (onMustShowChanged) inScope({ ...scope, mustShow: v }, "", onMustShowChanged)(); },
    tick() { if (cornerRevealTimer.running && onTriggered) { cornerRevealTimer.running = false; inScope(scope, "", onTriggered)(); } },
  };
}
for (const centerOnly of [false, true]) {
  const what = centerOnly ? "the centre pill's corners" : "the round decorators";
  const b = bar(true);
  check(`auto-hide, the bar slid away: ${what} are not drawn`, b.drawn(centerOnly) === false, "they stay on the screen's edge");
  b.show(true);
  check(`the pointer brings the bar back: ${what} wait a beat`, b.drawn(centerOnly) === false, "drawn before the bar is there");
  b.tick();
  check(`then are drawn with it`, b.drawn(centerOnly) === true, "not drawn");
  b.show(false);
  check(`and leave with it again`, b.drawn(centerOnly) === false, "they stay");
  check(`with auto-hide off ${what} are drawn`, bar(false).drawn(centerOnly) === true, "not drawn");
}
done();
