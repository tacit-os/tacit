// The lock's and the boot lock's own picture (the one they blur when there is no baked ground: a lock screen picture
// chosen in Settings, a missing ground) whose file name holds # or ?: each surface's wallSource source binding run under
// node with FileUtils' own fileUrl(), then read as QML reads a source, relative to the file. The file it names must be
// the picture, with nothing taken for a fragment or a query.
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the lock's picture, whatever its name");
const f = qmlFunction(read("modules/common/functions/FileUtils.qml"), "fileUrl");
const FileUtils = { fileUrl: inScope({}, f.params, f.body) };

for (const file of ["modules/ii/lock/LockSurface.qml", "modules/ii/lock/BootLockSurface.qml"]) {
  const src = read(file);
  const at = src.indexOf("source:", src.indexOf("id: wallSource"));
  const expr = readExpression(src, at + "source:".length).expr;
  for (const path of ["/home/you/Pictures/Holiday #3.jpg", "/home/you/Pictures/Why?.png", "/home/you/Pictures/dusk.jpg"]) {
    const source = String(inScope({ root: { groundReady: false, wallpaper: path }, FileUtils }, "", `return (${expr});`)());
    const url = new URL(source, `file:///usr/share/tacit/shell/${file}`);
    const opened = decodeURIComponent(url.pathname);
    check(`${file.split("/").pop()}: "${path.split("/").pop()}" is drawn from that file`, opened === path && !url.hash && !url.search,
      `it opens ${opened}${url.hash ? `, with "${url.hash}" read as a fragment` : ""}${url.search ? `, with "${url.search}" read as a query` : ""}`);
  }
}
done();
