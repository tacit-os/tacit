// Dragging a desktop widget (modules/common/widgets/widgetCanvas/AbstractWidget.qml): its own onDraggingChanged, snap()
// and the Binding that writes the dragged spot to x run under node, with the drag proxy's "x: root.x" binding and a
// MouseArea drag as Qt 6.12 has it (qquickmousearea.cpp: the start is read from the proxy on the first move, and
// setPosition() keeps the proxy's binding). A drag starts from where the widget is, however it got there.
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== dragging a desktop widget (AbstractWidget.qml)");
const src = read("modules/common/widgets/widgetCanvas/AbstractWidget.qml");
const proxyAt = src.lastIndexOf("Item {", src.indexOf("id: dragProxy"));
const proxyBlock = src.slice(proxyAt, matchBrace(src, src.indexOf("{", proxyAt)));
const proxyBound = /^\s*x:\s*root\.x\s*$/m.test(proxyBlock);
const valueAt = src.indexOf("value:", src.indexOf('property: "x"'));
const valueExpr = readExpression(src, valueAt + "value:".length).expr;
const snap = qmlFunction(src, "snap");
const draggingAt = src.indexOf("onDraggingChanged:");
const onDragging = readExpression(src, draggingAt + "onDraggingChanged:".length).expr.slice(1, -1);

function widget() {
  let x = 0, proxyX = 0, dragging = false;
  let bound = proxyBound ? () => root.x : null;
  const root = {
    gridSize: 12, snapEnabled: true, width: 240, height: 120, y: 0, parent: {},
    get x() { return x; },
    set x(v) { if (v === x) return; x = v; if (bound) setProxy(bound()); },   // the proxy's binding follows
    get dragging() { return dragging; },
  };
  root.snap = inScope({ root }, snap.params, snap.body);
  // the proxy moved: while dragging, the Binding writes its snapped spot to x
  function setProxy(v) {
    if (v === proxyX) return;
    proxyX = v;
    if (dragging) root.x = value();
  }
  const dragProxy = {
    get x() { return proxyX; },
    set x(v) {   // a script's write: a binding replaces the one there, a value drops it
      if (v && v.binding) { bound = v.binding; setProxy(bound()); } else { bound = null; setProxy(v); }
    },
    y: 0,
  };
  const value = inScope({ root, dragProxy }, "", `return (${valueExpr});`);
  const canvas = { width: 1920, height: 1080, setDragging() {}, beginGroupDrag() {}, endGroupDrag() {}, flashLines() {} };
  const scope = { root, dragProxy, get dragging() { return dragging; }, findCanvas: () => canvas,
    Config: { options: { background: { showSnapLines: false } } }, Qt: { binding: f => ({ binding: f }) } };
  const draggingChanged = inScope(scope, "", onDragging);
  return {
    root,
    // a press, then the pointer moving by each of moves from where it was pressed, then the release
    drag(...moves) {
      const start = proxyX;   // read on the first move
      dragging = true;
      draggingChanged();
      for (const d of moves) setProxy(start + d);   // setPosition(): the binding stays
      dragging = false;
      draggingChanged();
    },
  };
}

{
  const w = widget();
  w.drag(98, 100);
  check("a drag of 100 px puts the widget on the grid at 96", w.root.x === 96, `x ${w.root.x}`);
  w.drag(15);
  check("a second drag starts where the widget sits, not where the pointer let go", w.root.x === 108, `x ${w.root.x}`);
}
{
  const w = widget();
  w.drag(98, 100);
  w.root.x = 300;   // moved with a group, kept on the screen, or put back where it was saved
  w.drag(24);
  check("after it was moved some other way, the next drag starts from where it is now", w.root.x === 324,
    `x ${w.root.x}: it jumped back to its last drag`);
}
{
  const w = widget();
  w.root.x = 504;
  w.drag(12);
  check("a widget not dragged before starts from where it is too", w.root.x === 516, `x ${w.root.x}`);
}
done();
