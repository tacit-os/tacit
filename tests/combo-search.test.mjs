// The dropdown with a search (modules/common/widgets/StyledComboBoxSearch.qml, the world clock's zones): its own
// functions, handlers and row colour run under node, with the ComboBox's highlightedIndex as Qt 6.12 sets it (the
// chosen row when the popup opens, the row under the pointer). Typing then Enter takes the first row the search shows,
// and the row Enter takes is drawn.
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the dropdown with a search (StyledComboBoxSearch.qml)");
const src = read("modules/common/widgets/StyledComboBoxSearch.qml");
const labels = ["Auckland", "Sydney", "Tokyo", "Seoul", "Berlin", "London", "Lisbon"];
const london = 5;

// a handler on the ComboBox itself, or null when the file has none
function handler(name) {
  const m = new RegExp(`\\n    ${name}:`).exec(src);
  if (!m) return null;
  const expr = readExpression(src, m.index + m[0].length).expr;
  return expr.startsWith("{") ? expr.slice(1, -1) : expr;
}
const colorExpr = qmlProperty(src, "color"), litExpr = qmlProperty(src, "lit");
// the list's currentIndex: bound to highlightedIndex in the file, until a script writes it
const listBound = /StyledListView\s*\{[^}]*currentIndex:\s*root\.highlightedIndex/.test(src);

function dropdown() {
  const picks = [];
  let cur = -1, bound = listBound, hi = -1, hover = -1;
  const listView = {
    get currentIndex() { return cur; },
    set currentIndex(v) { bound = false; cur = v; },
    get currentItem() { const i = cur; return i >= 0 ? { clicked: () => picks.push(i) } : null; },
  };
  const root = { model: labels.map(label => ({ label })), textRole: "label", currentIndex: london, searchText: "",
    get highlightedIndex() { return hi; } };
  const scope = { root, listView };
  for (const name of ["matchesSearch", "stepHighlight", "activateHighlighted"]) {
    const f = qmlFunction(src, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  const run = body => body && inScope(scope, "", body)();
  const onHighlighted = handler("onHighlightedIndexChanged"), onSearch = handler("onSearchTextChanged");
  function setHighlighted(i) {
    if (i === hi) return;
    hi = i;
    if (bound) cur = i;
    run(onHighlighted);
  }
  const Appearance = { colors: new Proxy({}, { get: (t, k) => String(k) }) };
  const ColorUtils = { transparentize: c => `clear ${c}` };
  function color(index) {
    const itemDelegate = { index, down: false, hovered: hover === index, ListView: { isCurrentItem: cur === index } };
    if (litExpr) itemDelegate.lit = inScope({ itemDelegate }, "", `return (${litExpr});`)();
    return inScope({ root, itemDelegate, Appearance, ColorUtils, listView }, "", colorExpr.slice(1, -1))();
  }
  return {
    picks, color,
    open() { cur = 0; setHighlighted(root.currentIndex); },   // setModel puts the list on row 0 first (qquickitemview.cpp)
    type(text) { if (text === root.searchText) return; root.searchText = text; run(onSearch); },
    hover(i) { hover = i; setHighlighted(i); },
    key(k) { if (k === "Down") root.stepHighlight(1); else if (k === "Up") root.stepHighlight(-1); else root.activateHighlighted(); },
  };
}
const name = i => labels[i] ?? `row ${i}`;

{
  const d = dropdown();
  d.open(); d.type("tok"); d.key("Enter");
  check("typing \"tok\" and pressing Enter takes Tokyo", d.picks.join() === "2", `took ${d.picks.map(name).join() || "nothing"}`);
}
{
  const d = dropdown();
  d.open(); d.type("s"); d.key("Down");
  const lit = labels.map((_, i) => i).filter(i => d.color(i) === "colLayer3Hover" || d.color(i) === "colSecondaryContainerHover");
  d.key("Enter");
  check("Down after typing \"s\" goes from the first row it shows (Sydney) to the next (Seoul)", d.picks.join() === "3",
    `took ${d.picks.map(name).join() || "nothing"}`);
  check("the row Enter takes is the one drawn lit, and the only one", lit.join() === "3", `lit: ${lit.map(name).join() || "none"}`);
}
{
  const d = dropdown();
  d.open(); d.type("o"); d.hover(6); d.key("Enter");
  check("the pointer on a row still makes it the one Enter takes", d.picks.join() === "6", `took ${d.picks.map(name).join() || "nothing"}`);
}
{
  const d = dropdown();
  d.open(); d.key("Enter");
  check("Enter with nothing typed keeps the chosen zone", d.picks.join() === String(london));
  const e = dropdown();
  e.open(); e.type("tok"); e.type(""); e.key("Enter");
  check("emptying the search goes back to the chosen zone", e.picks.join() === String(london), `took ${e.picks.map(name).join() || "nothing"}`);
  const f = dropdown();
  f.open(); f.type("zzz"); f.key("Enter");
  check("a search that shows nothing takes nothing", f.picks.length === 0);
}
done();
