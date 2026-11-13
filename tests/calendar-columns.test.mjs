// The desktop calendar's day names stand over their dates (modules/ii/background/widgets/calendar/CalendarWidget.qml):
// in each size that shows a month, the row of names and the rows of dates are both centred in the same column, so each
// name's centre is laid out from the file's own widths and spacings as a RowLayout places them, and compared with its
// date's.
import { matchBrace } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the desktop calendar's day names over their dates (CalendarWidget.qml)");
const src = read("modules/ii/background/widgets/calendar/CalendarWidget.qml");
const cellAt = src.indexOf("component DayCell");
const cell = +src.slice(cellAt, matchBrace(src, src.indexOf("{", cellAt))).match(/^\s*implicitWidth:\s*(\d+)/m)[1];
const centres = (w, s) => [0, 1, 2, 3, 4, 5, 6].map(i => -(7 * w + 6 * s) / 2 + w / 2 + i * (w + s));

for (const [id, size] of [["twoByTwoContent", "2x2"], ["twoByThreeContent", "2x3"]]) {
  const at = src.indexOf(`id: ${id}`), block = src.slice(at, matchBrace(src, src.indexOf("{", at)));
  const heads = block.indexOf("model: root.dayHeads");
  const headSpacing = +[...block.slice(0, heads).matchAll(/spacing:\s*(\d+)/g)].pop()[1];   // the names' RowLayout
  const headWidth = +block.slice(heads).match(/Layout\.preferredWidth:\s*([\d.]+)/)[1];
  const rows = block.indexOf("delegate: RowLayout", heads);
  const rowSpacing = +block.slice(rows).match(/spacing:\s*(\d+)/)[1];
  const a = centres(headWidth, headSpacing), b = centres(cell, rowSpacing);
  const off = Math.max(...a.map((x, i) => Math.abs(x - b[i])));
  check(`in the ${size} size each day's name is centred over its dates`, off < 0.5,
    `names ${headWidth} px wide ${headSpacing} apart, dates ${cell} px wide ${rowSpacing} apart: off by up to ${off} px`);
}
done();
