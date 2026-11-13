// Pinax says no size it did not sum, and a count it cut off is said as one (modules/ii/files/FilesWindow.qml): the
// window's own folderBytes, selectedBytesNow() and statusLine run under node on a folder of 6,000 photos, a folder with
// a subfolder, a selection holding a folder, and Recent and Large & old at the number their lists stop at.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Pinax's sizes and counts are not cut off unsaid (FilesWindow.qml)");
const src = read("modules/ii/files/FilesWindow.qml");
// a property's { ... } block
const block = name => { const open = src.indexOf("{", src.indexOf(` ${name}: {`)); return src.slice(open + 1, matchBrace(src, open)); };
const voice = { count: (n, noun) => (n === 0 ? `no ${noun}s` : `${n} ${n === 1 ? noun : noun + "s"}`), facts: l => l.filter(f => (f ?? "").length).join(" · "),
  size: n => `${(n / 1e9).toFixed(1)} GB` };
const model = rows => ({ count: rows.length, get: (i, role) => rows[i][role] });
const photo = (i, bytes = 700000) => ({ filePath: `/home/a/Photos/IMG_${i}.jpg`, fileIsDir: false, fileSize: bytes });

function folderBytes(rows) { return inScope({ folderModel: model(rows), win: {} }, "", block("folderBytes"))(); }
check("a folder of 6,000 photos says no size it summed from the first 2,000", folderBytes(Array.from({ length: 6000 }, (_, i) => photo(i))) === 0,
  `it says ${folderBytes(Array.from({ length: 6000 }, (_, i) => photo(i)))} bytes`);
const withSub = [photo(1), photo(2), { filePath: "/home/a/Photos/Trip", fileIsDir: true, fileSize: 4096 }];
check("a folder with a subfolder says no size of its own files alone", folderBytes(withSub) === 0, `it says ${folderBytes(withSub)} bytes`);
check("a folder of files only still says their size", folderBytes([photo(1), photo(2)]) === 1400000, `it says ${folderBytes([photo(1), photo(2)])}`);

const sel = qmlFunction(src, "selectedBytesNow");
const selected = (rows, paths) => inScope({ folderModel: model(rows), win: { selectedMap: Object.fromEntries(paths.map(p => [p, true])) } }, "", sel.body)();
check("a selection holding a folder says no size", selected(withSub, [withSub[0].filePath, withSub[2].filePath]) === 0, `${selected(withSub, [withSub[0].filePath, withSub[2].filePath])} bytes`);
check("a selection of files says their size", selected(withSub, [withSub[0].filePath, withSub[1].filePath]) === 1400000);

const statusAt = src.indexOf("{", src.indexOf("readonly property string statusLine:"));
const statusLine = w => inScope({ win: { footLine: "", phoneShown: false, shelfShown: false, searching: true, searchRunning: false, diskLine: "Disk 91% · 20G free", ...w }, Voice: voice }, "",
  src.slice(statusAt + 1, matchBrace(src, statusAt)))();
const hits = n => Array.from({ length: n }, (_, i) => ({ path: `/f${i}` }));
const recent = statusLine({ recentShown: true, largeOld: false, hits: hits(300) });
check("Recent at its 300 says 300+", /^300\+ files touched this week/.test(recent), `it says "${recent}"`);
check("Recent under it says the number", statusLine({ recentShown: true, largeOld: false, hits: hits(12) }).startsWith("12 files touched this week"));
const large = statusLine({ recentShown: false, largeOld: true, hits: hits(100) });
check("Large & old at its 100 says 100+", /^100\+ files over 100 MB/.test(large), `it says "${large}"`);
done();
