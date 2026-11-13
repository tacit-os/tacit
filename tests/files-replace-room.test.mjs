// Files' Replace on a nearly full disk (scripts/files/job.sh copy|move replace, and Pinax's question): Replace keeps the
// old file on its disk (in the trash, for Undo) until the new one is whole, so where both can't fit it asks "Not enough
// room to keep the old copy. Replace it for good?" before touching anything, and replace-for-good then removes the old
// one first. The job runs under bash in a home of its own with a pretend gio that trashes the freedesktop way and a
// pretend df that says $AVAIL bytes are free; the window's own functions run under node.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== Files' Replace asks before replacing for good where the old copy can't stay (scripts/files/job.sh, FilesWindow.qml)");
const job = join(tree, "scripts/files/job.sh");
const tmp = mkdtempSync(join(tmpdir(), "tacit-replace-room-"));
const bin = join(tmp, "bin");
mkdirSync(bin);
writeFileSync(join(bin, "gio"), `#!/bin/bash
[ "$1" = trash ] || exit 1
shift; [ "$1" = -- ] && shift
p=$1; t=$XDG_DATA_HOME/Trash; mkdir -p "$t/files" "$t/info"
[ -e "$p" ] || { echo "gio: $p: No such file or directory" >&2; exit 1; }
n=$(basename -- "$p"); k=1; while [ -e "$t/files/$n" ]; do k=$((k+1)); n="$(basename -- "$p").$k"; done
mv -- "$p" "$t/files/$n" && printf '[Trash Info]\\nPath=%s\\nDeletionDate=2026-11-13T10:00:00\\n' "$p" > "$t/info/$n.trashinfo"
`);
// df as GNU df prints --output=avail: a heading, then the bytes free
writeFileSync(join(bin, "df"), `#!/bin/bash\nprintf '     Avail\\n%s\\n' "$AVAIL"\n`);
for (const f of ["gio", "df"]) chmodSync(join(bin, f), 0o755);

const MiB = 1024 * 1024;
let n = 0;
// a fresh home with report.odt in Documents (OLD) and a new one (NEW, WHOLE) in Downloads, on the same disk here
function scene(steps, avail) {
  const home = join(tmp, `home${++n}`), docs = join(home, "Documents"), from = join(home, "Downloads");
  mkdirSync(docs, { recursive: true }); mkdirSync(from);
  writeFileSync(join(docs, "report.odt"), "OLD"); writeFileSync(join(from, "report.odt"), "NEW, WHOLE");
  const env = { PATH: `${bin}:${process.env.PATH}`, HOME: home, XDG_DATA_HOME: join(home, ".local/share"),
    XDG_STATE_HOME: join(home, ".local/state"), AVAIL: String(avail), JOB: job, DOCS: docs, FROM: from };
  execFileSync("bash", ["-c", steps], { env, encoding: "utf8" });
  const target = join(docs, "report.odt"), trash = join(home, ".local/share/Trash/files");
  const r = JSON.parse(readFileSync(join(home, ".local/state/quickshell/user/files/jobs/a.json"), "utf8"));
  return { target: existsSync(target) ? readFileSync(target, "utf8") : null, state: r.state, error: r.error, undo: r.undo?.op ?? null,
    left: readdirSync(docs).filter(f => f !== "report.odt"), trashed: existsSync(trash) ? readdirSync(trash) : [],
    source: existsSync(join(from, "report.odt")) };
}
const say = s => JSON.stringify(s);
const copy = policy => `bash "$JOB" a copy ${policy} "$DOCS" "$FROM/report.odt"`;

try {
  {
    const s = scene(copy("replace"), 50 * 1024 * MiB);
    check("with room for both, Replace keeps the old one in the trash as before, for Undo",
      s.state === "done" && s.target === "NEW, WHOLE" && s.trashed.includes("report.odt") && s.undo === "unreplace", say(s));
  }
  {
    const s = scene(copy("replace"), 2 * MiB);
    check("with no room for both, Replace stops before touching anything and says so (the window asks)",
      s.state === "failed" && s.error === "not enough room to keep the old copy of report.odt" && s.target === "OLD"
        && !s.trashed.length && !s.left.length && s.source, say(s));
  }
  {
    const s = scene(copy("replace-for-good"), 2 * MiB);
    check("Replace for good with no room: the new one is in place, and no copy of the old one is kept in the trash or beside it",
      s.state === "done" && s.target === "NEW, WHOLE" && !s.trashed.length && !s.left.length, say(s));
  }
  {
    const s = scene(copy("replace-for-good"), 50 * 1024 * MiB);
    check("Replace for good where there is room still keeps the old one in the trash", s.state === "done" && s.target === "NEW, WHOLE"
      && s.trashed.includes("report.odt") && s.undo === "unreplace", say(s));
  }
  {
    const s = scene(`bash "$JOB" a move replace "$DOCS" "$FROM/report.odt"`, 2 * MiB);
    check("a move within a disk is a rename and needs no room: replaced, the old one in the trash", s.state === "done"
      && s.target === "NEW, WHOLE" && s.trashed.includes("report.odt") && !s.source, say(s));
  }

  // the window: Replace remembers what it was asked to bring; a job that stopped for want of room asks, with Cancel the
  // button Enter takes, and Replace brings what that job did not get to with replace-for-good
  const fw = read("modules/ii/files/FilesWindow.qml");
  const fn = name => qmlFunction(fw, name) ?? { params: "", body: "" };
  const ran = [], sheet = { title: "", lines: [], buttons: [], safe: 1, opened: 0, open() { this.opened++; } };
  const win = { myJobs: {}, replacing: {}, pendingTrash: [], folder: "/home/u/Documents" };
  let next = 0;
  win.run = (op, args) => { const id = `j${++next}`; ran.push([op, ...args]); win.myJobs[id] = true; return id; };
  const scope = { win, sheet, Files: { clip: null, parent: p => p.replace(/\/[^/]*$/, ""), learnMove() {}, placeName: p => p },
    Voice: { count: (k, w) => `${k} ${w}s` }, Jobs: { label: () => "" }, Quickshell: { execDetached() {} }, jobLineTimer: { restart() {} },
    revealEdit: {} };
  for (const name of ["askRoom", "bringChecked"]) { const f = fn(name); win[name] = inScope(scope, f.params, f.body); }
  const finished = inScope(scope, fn("onJobFinished").params, fn("onJobFinished").body);
  const list = ["/stick/a.odt", "/stick/b.odt"], dest = "/home/u/Documents";
  win.bringChecked("copy", list, dest, list, false);
  sheet.buttons.find(b => b.label === "Replace")?.run();
  const id = Object.keys(win.myJobs)[0] ?? "";
  sheet.title = ""; sheet.buttons = [];
  finished({ id, op: "copy", state: "failed", error: "Could not copy b.odt: the disk is full", results: [`${dest}/a.odt`], undo: null });
  const askedForFull = sheet.title;
  win.replacing[id] = { op: "copy", dest, list };
  finished({ id, op: "copy", state: "failed", error: "not enough room to keep the old copy of b.odt", results: [`${dest}/a.odt`], undo: null });
  const asked = { title: sheet.title, lines: sheet.lines, buttons: sheet.buttons.map(b => b.label), enter: sheet.buttons[sheet.safe]?.label };
  sheet.buttons.find(b => b.label === "Replace")?.run();
  check("a Replace that had no room asks \"Not enough room to keep the old copy. Replace it for good?\", Replace or Cancel, Enter on Cancel",
    asked.title === "Not enough room to keep the old copy" && say(asked.lines) === '["Replace it for good?"]'
      && say(asked.buttons) === '["Replace","Cancel"]' && asked.enter === "Cancel" && askedForFull === "", `${say(asked)}; a full disk asked "${askedForFull}"`);
  check("and Replace brings what it did not get to, replacing for good",
    say(ran) === say([["copy", "replace", dest, ...list], ["copy", "replace-for-good", dest, "/stick/b.odt"]]), say(ran));
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
