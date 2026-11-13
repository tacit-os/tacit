// A copy or move that is stopped or fails part way (scripts/files/job.sh copy|move): nothing half-written may be left
// looking like a real file, a move's source must stay whole, and what did finish keeps its Undo, which Files and the
// desktop offer (FilesWindow.qml and DesktopIcons.qml, onJobFinished). The job runs under bash in a home of its own with
// a pretend cp (and, for a move across disks, a pretend mv) first on PATH: on big.mkv it writes part of the file, then
// waits to be stopped or runs out of room; everything else is copied or moved for real.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== a copy or move stopped or failed part way leaves no half file and keeps its Undo (scripts/files/job.sh)");
const job = join(tree, "scripts/files/job.sh");
const tmp = mkdtempSync(join(tmpdir(), "tacit-stopped-"));
const bin = join(tmp, "bin");
mkdirSync(bin);
const real = name => execFileSync("bash", ["-c", `command -v ${name}`], { encoding: "utf8" }).trim();
// what cp and mv do to big.mkv across disks: part of it, then $MODE (slow: wait to be stopped, full: no room left)
const half = tool => `if [ "\${t##*/}" = big.mkv ] && [ -n "\${MODE:-}" ]; then
  printf 'PART' > "$t"
  [ "$MODE" = slow ] && exec sleep 30
  echo "${tool}: error writing '$t': No space left on device" >&2; exit 1
fi`;
writeFileSync(join(bin, "cp"), `#!/bin/bash\nfor a; do t=$a; done\n${half("cp")}\nexec ${real("cp")} "$@"\n`);
// $XDEV: the destination is another disk, so a rename is refused and mv falls back to copying (old job.sh ran plain mv)
writeFileSync(join(bin, "mv"), `#!/bin/bash
for a; do t=$a; done
if [ -n "\${XDEV:-}" ]; then
  case " $* " in *" --no-copy "*) echo "mv: cannot move '$t': Invalid cross-device link" >&2; exit 1 ;; esac
  ${half("mv")}
fi
exec ${real("mv")} "$@"
`);
for (const f of ["cp", "mv"]) chmodSync(join(bin, f), 0o755);

let n = 0;
// a fresh home: a.txt and big.mkv on a stick, pasted into Documents; `steps` is bash with $JOB, $DOCS and $STICK
function scene(steps, { mode = "", xdev = false } = {}) {
  const home = join(tmp, `home${++n}`), docs = join(home, "Documents"), stick = join(tmp, `stick${n}`);
  mkdirSync(docs, { recursive: true }); mkdirSync(stick);
  writeFileSync(join(stick, "a.txt"), "A"); writeFileSync(join(stick, "big.mkv"), "BIG, WHOLE");
  const env = { PATH: `${bin}:${process.env.PATH}`, HOME: home, XDG_DATA_HOME: join(home, ".local/share"),
    XDG_STATE_HOME: join(home, ".local/state"), MODE: mode, XDEV: xdev ? "1" : "", JOB: job, DOCS: docs, STICK: stick };
  execFileSync("bash", ["-c", steps], { env, encoding: "utf8", timeout: 30000 });
  const report = JSON.parse(readFileSync(join(home, ".local/state/quickshell/user/files/jobs/a.json"), "utf8"));
  const files = d => Object.fromEntries(readdirSync(d).map(f => [f, readFileSync(join(d, f), "utf8")]));
  return { report, docs: files(docs), stick: files(stick), DOCS: docs, STICK: stick };
}
const paste = op => `bash "$JOB" a ${op} keep "$DOCS" "$STICK/a.txt" "$STICK/big.mkv"`;
// the paste until big.mkv is under way, then Stop (the .cancel the window touches)
const stopped = op => `${paste(op)} & j=$!
for i in $(seq 100); do grep -qs '"current":"big.mkv"' "$XDG_STATE_HOME/quickshell/user/files/jobs/a.json" && [ -e "$DOCS/big.mkv" ] && break; sleep 0.1; done
touch "$XDG_STATE_HOME/quickshell/user/files/jobs/a.cancel"; wait $j`;
const show = s => `${s.report.state} "${s.report.error}", Documents ${JSON.stringify(s.docs)}, stick ${JSON.stringify(s.stick)}, undo ${JSON.stringify(s.report.undo)}`;

try {
  {
    const s = scene(paste("copy"), { mode: "full" });
    check("a copy that runs out of room leaves no half big.mkv, and says the disk is full",
      s.report.state === "failed" && /disk is full/.test(s.report.error) && !("big.mkv" in s.docs) && s.docs["a.txt"] === "A", show(s));
    check("and a.txt, which was copied, can be undone", s.report.undo?.op === "delete" &&
      JSON.stringify(s.report.undo.paths) === JSON.stringify([join(s.DOCS, "a.txt")]), show(s));
  }
  {
    const s = scene(stopped("copy"), { mode: "slow" });
    check("Stop in the middle of a copy leaves no half big.mkv, and a.txt can be undone", s.report.state === "cancelled" &&
      !("big.mkv" in s.docs) && s.report.undo?.op === "delete" && s.report.undo.paths.length === 1, show(s));
  }
  {
    const s = scene(stopped("move"), { mode: "slow", xdev: true });
    check("Stop in the middle of a move to another disk leaves no half big.mkv there, and the whole one where it was",
      s.report.state === "cancelled" && !("big.mkv" in s.docs) && s.stick["big.mkv"] === "BIG, WHOLE", show(s));
    check("and a.txt, which was moved, can be moved back", s.docs["a.txt"] === "A" && !("a.txt" in s.stick) &&
      s.report.undo?.op === "move-back" && JSON.stringify(s.report.undo.to) === JSON.stringify([join(s.STICK, "a.txt")]), show(s));
  }
  {
    const s = scene(paste("move"), { mode: "full", xdev: true });
    check("a move to another disk that runs out of room leaves no half big.mkv, the whole one where it was, and an Undo",
      s.report.state === "failed" && /disk is full/.test(s.report.error) && !("big.mkv" in s.docs) &&
      s.stick["big.mkv"] === "BIG, WHOLE" && s.report.undo?.op === "move-back", show(s));
  }
  {
    const s = scene(paste("move"), { xdev: true });
    check("a move to another disk that finishes has both there whole, none left behind, and a move-back Undo",
      s.report.state === "done" && s.docs["big.mkv"] === "BIG, WHOLE" && s.docs["a.txt"] === "A" &&
      Object.keys(s.stick).length === 0 && s.report.undo?.op === "move-back" && s.report.undo.from.length === 2, show(s));
  }
  {
    // on one disk a move is a rename: the pretend cp would leave "PART" if it were copied instead
    const s = scene(paste("move"), { mode: "full" });
    check("a move within a disk is still a rename", s.report.state === "done" && s.docs["big.mkv"] === "BIG, WHOLE" &&
      Object.keys(s.stick).length === 0, show(s));
  }

  // what the window and the desktop do with a stopped copy that carries an undo
  const stoppedJob = { id: "a", kind: "job", op: "copy", dest: "/home/u/Documents", state: "cancelled", total: 2, done: 1,
    error: "", results: ["/home/u/Documents/a.txt"], undo: { op: "delete", paths: ["/home/u/Documents/a.txt"] } };
  {
    const f = qmlFunction(read("modules/ii/files/FilesWindow.qml"), "onJobFinished");
    const win = { myJobs: { a: true }, undoJob: "", jobLine: "", folder: "/home/u", pendingTrash: [], askDelete() {}, reload() {},
      tryRevealEdit() {} };
    inScope({ win, Jobs: { label: () => "Stopped · 1 of 2 done" }, Files: { learnMove() {}, parent: p => p.replace(/\/[^/]*$/, "") },
      jobLineTimer: { restart() {} }, revealEdit: {} }, f.params, f.body)(stoppedJob);
    check("Files offers Undo after a stopped copy", win.undoJob === "a", `undoJob "${win.undoJob}"`);
  }
  {
    const f = qmlFunction(read("services/DesktopIcons.qml"), "onJobFinished");
    let action = null;
    const root = { mine: { a: "" }, undoJob: "", said(text, act) { action = act; } };
    inScope({ root, Jobs: { label: () => "Stopped · 1 of 2 done" } }, f.params, f.body)(stoppedJob);
    check("the desktop offers Undo after a stopped copy", root.undoJob === "a" && action === "Undo",
      `undoJob "${root.undoJob}", action ${JSON.stringify(action)}`);
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
