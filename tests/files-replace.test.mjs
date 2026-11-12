// Files' Replace (scripts/files/job.sh copy|move replace): the job run by bash in a home of its own, with a pretend
// gio that trashes the freedesktop way (and refuses on a disk with no trash) and, where a copy must be slow or fail, a
// pretend cp first on PATH that writes part of the new file over the target, as cp does, then waits or fails. The old
// file must survive Stop, a full disk and Undo.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== Files' Replace keeps the old file until the new one is whole (scripts/files/job.sh)");
const job = join(tree, "scripts/files/job.sh");
const tmp = mkdtempSync(join(tmpdir(), "tacit-replace-"));
const bin = join(tmp, "bin"), slow = join(tmp, "slow"), full = join(tmp, "full");
for (const d of [bin, slow, full]) mkdirSync(d);
// gio trash: into $XDG_DATA_HOME/Trash with a record, or "not supported" under $NOTRASH
writeFileSync(join(bin, "gio"), `#!/bin/bash
[ "$1" = trash ] || exit 1
shift; [ "$1" = -- ] && shift
p=$1; t=$XDG_DATA_HOME/Trash; mkdir -p "$t/files" "$t/info"
case "$p" in "$NOTRASH"/*) echo "gio: $p: Trashing on system internal mounts is not supported" >&2; exit 1 ;; esac
[ -e "$p" ] || { echo "gio: $p: No such file or directory" >&2; exit 1; }
n=$(basename -- "$p"); k=1; while [ -e "$t/files/$n" ]; do k=$((k+1)); n="$(basename -- "$p").$k"; done
mv -- "$p" "$t/files/$n" && printf '[Trash Info]\\nPath=%s\\nDeletionDate=2026-11-12T10:00:00\\n' "$p" > "$t/info/$n.trashinfo"
`);
// cp that writes part of the new file over the target, then waits to be stopped
writeFileSync(join(slow, "cp"), `#!/bin/bash\nfor a; do t=$a; done\nprintf 'NEW, PART' > "$t"\nexec sleep 30\n`);
// cp that writes part of the new file over the target, then runs out of room
writeFileSync(join(full, "cp"), `#!/bin/bash\nfor a; do t=$a; done\nprintf 'NEW, PART' > "$t"\necho "cp: error writing '$t': No space left on device" >&2\nexit 1\n`);
for (const f of [join(bin, "gio"), join(slow, "cp"), join(full, "cp")]) chmodSync(f, 0o755);

let n = 0;
// a fresh home with report.odt in Documents (OLD) and on a stick (NEW); runs `steps` (bash, with $JOB and $ID)
function scene(steps, { path = [], noTrash = false } = {}) {
  const home = join(tmp, `home${++n}`), docs = join(home, "Documents"), stick = join(tmp, `stick${n}`);
  mkdirSync(docs, { recursive: true }); mkdirSync(stick);
  writeFileSync(join(docs, "report.odt"), "OLD"); writeFileSync(join(stick, "report.odt"), "NEW, WHOLE");
  const env = { PATH: [...path, bin, process.env.PATH].join(":"), HOME: home, XDG_DATA_HOME: join(home, ".local/share"),
    XDG_STATE_HOME: join(home, ".local/state"), NOTRASH: noTrash ? docs : "/nowhere", JOB: job, DOCS: docs, STICK: stick };
  execFileSync("bash", ["-c", steps], { env, encoding: "utf8" });
  const report = id => JSON.parse(readFileSync(join(home, ".local/state/quickshell/user/files/jobs", `${id}.json`), "utf8"));
  const target = join(docs, "report.odt");
  const trash = join(home, ".local/share/Trash/files");
  return { target: existsSync(target) ? readFileSync(target, "utf8") : null, report,
    left: readdirSync(docs).filter(f => f !== "report.odt"), trashed: existsSync(trash) ? readdirSync(trash) : [] };
}
// the job until it is copying, then Stop (the .cancel the window touches)
const stopped = `bash "$JOB" a copy replace "$DOCS" "$STICK/report.odt" & j=$!
for i in $(seq 50); do grep -qs '"current":"report.odt"' "$XDG_STATE_HOME/quickshell/user/files/jobs/a.json" && [ "$(cat "$DOCS/report.odt" 2>/dev/null)" != OLD ] && break; sleep 0.1; done
touch "$XDG_STATE_HOME/quickshell/user/files/jobs/a.cancel"; wait $j`;

try {
  {
    const s = scene(stopped, { path: [slow] });
    check("Stop in the middle of a Replace leaves the old file as it was", s.target === "OLD" && s.report("a").state === "cancelled",
      `report.odt is ${s.target === null ? "gone" : `"${s.target}"`}, state ${s.report("a").state}`);
  }
  {
    const s = scene(`bash "$JOB" a copy replace "$DOCS" "$STICK/report.odt"`, { path: [full] });
    const r = s.report("a");
    check("a Replace that runs out of room leaves the old file as it was, and says the disk is full",
      s.target === "OLD" && r.state === "failed" && /disk is full/.test(r.error), `report.odt "${s.target}", ${r.state}: ${r.error}`);
  }
  {
    // done, then Undo the way Jobs.undo runs it
    const s = scene(`bash "$JOB" a copy replace "$DOCS" "$STICK/report.odt"
u=$(jq -c .undo "$XDG_STATE_HOME/quickshell/user/files/jobs/a.json")
case $(jq -r .op <<<"$u") in
  unreplace) mapfile -t a < <(jq -r '.args[]' <<<"$u"); bash "$JOB" b unreplace "\${a[@]}" ;;
  delete) mapfile -t a < <(jq -r '.paths[]' <<<"$u"); bash "$JOB" b trash "\${a[@]}" ;;
esac`);
    check("a finished Replace put the new file in place", s.report("a").state === "done");
    check("Undo brings the old file back, and the new one is in the trash", s.target === "OLD" && s.report("b").state === "done" &&
      s.trashed.length === 1, `report.odt ${s.target === null ? "gone" : `"${s.target}"`}, trash ${JSON.stringify(s.trashed)}`);
  }
  {
    const s = scene(`bash "$JOB" a copy replace "$DOCS" "$STICK/report.odt"`, { noTrash: true });
    check("on a disk with no trash, Replace still puts the new file in place and leaves nothing behind",
      s.target === "NEW, WHOLE" && s.report("a").state === "done" && s.left.length === 0, `"${s.target}", left ${JSON.stringify(s.left)}`);
  }
  {
    const s = scene(stopped, { path: [slow], noTrash: true });
    check("on a disk with no trash, Stop leaves the old file as it was", s.target === "OLD" && s.left.length === 0,
      `"${s.target}", left ${JSON.stringify(s.left)}`);
  }
  {
    const s = scene(`bash "$JOB" a copy keep "$DOCS" "$STICK/report.odt"`);
    check("Keep both still copies beside it, and its Undo is to trash the copy",
      s.target === "OLD" && s.report("a").results[0].endsWith("report 2.odt") && s.report("a").undo.op === "delete");
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
