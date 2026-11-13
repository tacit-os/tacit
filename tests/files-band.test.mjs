// Pinax's band in the list (FilesWindow.qml, selectBand): the window's own function, run under node on a list of ten
// 40 px rows in a tall window, with Qt's ListView.indexAt (-1 wherever there is no row: in the margin over the first
// one and in the ground under the last). The band takes the rows it crosses, and none when it crosses none.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Pinax's band selects the rows it crosses (FilesWindow.qml)");
const src = read("modules/ii/files/FilesWindow.qml");
const f = qmlFunction(src, "selectBand");
const ROW = 40, COUNT = 10, MARGIN = 4;
// the list at the top of its area, scrolled to its start: its top margin over row 0, and 400 px of ground under row 9
const list = { y: 0, contentY: -MARGIN, originY: 0, contentHeight: ROW * COUNT,
  indexAt: (x, y) => (y >= 0 && y < ROW * COUNT ? Math.floor(y / ROW) : -1) };
const win = { view: "list", pictures: false, selectedMap: {}, anchorIndex: -1, cursorPath: "", rowShown: () => true, pathAt: k => `/home/a/f${k}` };
const selectBand = inScope({ win, list, folderModel: { count: COUNT } }, f.params, f.body);
// a band between two heights of the window's area, as the ground draws it
const band = (top, bottom) => {
  win.selectedMap = {};
  selectBand(top, bottom, 20, 60);
  return Object.keys(win.selectedMap).map(p => +p.slice("/home/a/f".length)).sort((a, b) => a - b);
};
const area = y => y + MARGIN;   // a height in the list's content, as a height in its area
const cases = [
  ["a shaky click on the ground under the last row", area(470), area(478), []],
  ["a band wholly in the margin over the first row", 0, 3, []],
  ["a band over rows 2 to 5", area(90), area(220), [2, 3, 4, 5]],
  ["a band from row 7 into the ground under the rows", area(300), area(600), [7, 8, 9]],
  ["a band from the margin into row 3", 1, area(130), [0, 1, 2, 3]],
  ["a band from the margin to the ground under the rows", 1, area(600), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]],
];
for (const [name, top, bottom, want] of cases) {
  const got = band(top, bottom);
  check(`${name} selects ${want.length ? `rows ${want.join(", ")}` : "nothing"}`, JSON.stringify(got) === JSON.stringify(want),
    `selected ${got.length === COUNT ? "every file" : JSON.stringify(got)}`);
}
done();
