// Where a match sits in the dropdown with a search (modules/common/widgets/StyledComboBoxSearch.qml) on the world
// clock's zones (services/WorldClock.qml's list and labels): the delegate's own height binding and the list's spacing,
// laid out as a ListView lays out its rows (each row's y is the heights and spacings of the rows before it, hidden ones
// included), against the popup, which is sized for the rows the search shows.
import { inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a match far down the dropdown with a search (StyledComboBoxSearch.qml)");
const src = read("modules/common/widgets/StyledComboBoxSearch.qml");
const clock = read("services/WorldClock.qml");
const zones = inScope({}, "", `return (${qmlProperty(clock, "fallbackTimezones")});`)();
const lf = qmlFunction(clock, "labelFor"), labelFor = inScope({}, lf.params, lf.body);

const at = src.indexOf("delegate: ItemDelegate");
const delegate = src.slice(at, matchBrace(src, src.indexOf("{", at)));
const heightOf = inScope({}, "visible", `return (${readExpression(delegate, delegate.indexOf("implicitHeight:") + 15).expr});`);
const bg = delegate.slice(delegate.indexOf("background: Rectangle"));
const ground = +(bg.slice(0, matchBrace(bg, bg.indexOf("{"))).match(/anchors\.bottomMargin:\s*(\d+)/)?.[1] ?? 0);
const list = src.slice(src.indexOf("StyledListView {"));
const spacing = +list.slice(0, matchBrace(list, list.indexOf("{"))).match(/\bspacing:\s*(\d+)/)[1];
const perRow = +src.match(/visibleCount \* (\d+)/)[1];   // what the popup gives each row it shows

function layout(labels, search) {
  let y = 0;
  const shown = [];
  for (const label of labels) {
    const visible = label.toLowerCase().includes(search);
    const h = heightOf(visible);
    if (visible) shown.push({ label, y, ground: h - ground });
    y += h + spacing;
  }
  return { shown, room: shown.length * perRow };
}

for (const [name, labels, search, want] of [
  ["the world clock's own list", zones.map(labelFor), "toronto", "Toronto (America)"],
  ["the whole list of zones", Intl.supportedValuesOf("timeZone").map(labelFor), "toronto", "Toronto (America)"],
  ["the whole list of zones", Intl.supportedValuesOf("timeZone").map(labelFor), "yo", "Tokyo (Asia)"],
]) {
  const { shown, room } = layout(labels, search);
  const row = shown.find(r => r.label === want);
  check(`"${search}" in ${name} (${labels.length} zones): ${want} is within the popup`, row && row.y + row.ground <= room,
    row ? `its row starts at y ${row.y}, the popup shows ${room} px of rows` : "not shown");
}
for (const search of ["", "(america)"]) {
  const { shown } = layout(Intl.supportedValuesOf("timeZone").map(labelFor), search);
  const apart = shown.slice(1).map((r, i) => r.y - shown[i].y);
  check(`rows ${search ? `the search "${search}" shows` : "without a search"} are 40 px with 2 px between`,
    shown.length > 2 && apart.every(d => d === 42) && shown.every(r => r.ground === 40),
    `${shown.length} rows, ${[...new Set(apart)].join(" or ")} px apart, their ground ${[...new Set(shown.map(r => r.ground))].join(" or ")} px`);
}

done();
