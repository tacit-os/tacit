// Copy in the Viewer and the shelf (scripts/viewer/viewer-copy, read by Viewer.qml's and DropShelf.qml's copyProc):
// without viewer-clip a picture goes onto the clipboard as the picture alone, and that is said, not "Copied", which
// promises its file too. viewer-copy runs under sh in a home of its own with a pretend wl-copy and magick that note what
// they were given, a wayland-scanner that fails (so viewer-clip cannot be built), and for one run a pretend viewer-clip;
// the two copyProc's own onExited run under node on its exit.
import { spawnSync } from "child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== Copy without viewer-clip says what went (scripts/viewer/viewer-copy, Viewer.qml, DropShelf.qml)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-viewer-copy-"));
const bin = join(tmp, "bin"), clipBin = join(tmp, "clip-bin"), log = join(tmp, "clipboard");
for (const d of [bin, clipBin]) mkdirSync(d);
const tool = (dir, name, text) => { writeFileSync(join(dir, name), `#!/bin/sh\n${text}\n`); chmodSync(join(dir, name), 0o755); };
tool(bin, "wl-copy", 'echo "wl-copy $2" >> "$LOG"');
tool(bin, "magick", '[ -n "$NO_PNG" ] && exit 1; for a; do out=$a; done; printf PNG > "$out"');
tool(bin, "wayland-scanner", "exit 1");
tool(clipBin, "viewer-clip", 'echo "viewer-clip $*" | sed "s|$HOME|~|g" >> "$LOG"');
const photo = join(tmp, "photo.jpg");
writeFileSync(photo, "JPEG");

// the toast each copyProc makes of an exit code
const viewerProc = objectWith(read("modules/viewer/Viewer.qml"), "id: copyProc");
const shelfProc = objectWith(read("modules/common/widgets/DropShelf.qml"), "id: copyProc");
const onExited = (block, scope) => inScope(scope, "", `return (${readExpression(block, block.indexOf("onExited:") + 9).expr});`)();
const viewerSays = code => { let said = null; onExited(viewerProc, { toast: t => (said = t) })(code); return said; };
const shelfSays = code => {
  let said = "(failed)";
  onExited(shelfProc, { copyProc: { words: "Copied · photo.jpg" }, root: { copied: w => (said = w), copyFailed: () => {} } })(code);
  return said;
};

try {
  const copy = (kind, env = {}, withClip = false) => {
    rmSync(log, { force: true });
    const r = spawnSync("sh", [join(tree, "scripts/viewer/viewer-copy"), photo, kind], { encoding: "utf8",
      env: { PATH: `${withClip ? `${clipBin}:` : ""}${bin}:${process.env.PATH}`, HOME: join(tmp, "home"), LOG: log, ...env } });
    return { code: r.status, got: existsSync(log) ? readFileSync(log, "utf8").trim().split("\n").join(" | ") : "nothing" };
  };
  let r = copy("image");
  check("a picture without viewer-clip goes as the picture alone, and says so (exit 4)", r.code === 4 && r.got === "wl-copy image/png", `exit ${r.code}: ${r.got}`);
  check('the Viewer says "Copied the picture, not the file"', viewerSays(r.code) === "Copied the picture, not the file", viewerSays(r.code));
  check("the shelf says it too", shelfSays(r.code) === "Copied the picture, not the file", shelfSays(r.code));
  r = copy("image", { NO_PNG: "1" });
  check("one no PNG can be made from goes as its file, as before (exit 3)", r.code === 3 && r.got === "wl-copy text/uri-list" && viewerSays(r.code) === "Copied the file, not the picture", `exit ${r.code}: ${r.got}`);
  r = copy("pdf");
  check("a PDF goes as its file, said as Copied", r.code === 0 && r.got === "wl-copy text/uri-list" && viewerSays(r.code) === "Copied", `exit ${r.code}: ${r.got}`);
  r = copy("image", {}, true);
  check("with viewer-clip the picture goes as both at once, said as Copied",
    r.code === 0 && /^viewer-clip text\/uri-list=\S+\/uri image\/png=\S+\/picture\.png$/.test(r.got) && viewerSays(r.code) === "Copied" && shelfSays(r.code) === "Copied · photo.jpg",
    `exit ${r.code}: ${r.got}`);
  check("Couldn't copy is still said when nothing went", viewerSays(1) === "Couldn't copy" && shelfSays(1) === "(failed)");
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
