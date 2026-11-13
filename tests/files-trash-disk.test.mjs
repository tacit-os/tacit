// Undo of a trash on a stick (scripts/files/job.sh trash, then restore-paths): gio trash puts a file from another disk
// in that disk's own .Trash-UID, with its Path from the disk's top, and a fresh install has no GVfs for gio's trash:///.
// The job runs under bash in a home of its own with a pretend gio that trashes as GLib does and has no trash:///, and a
// pretend stat that says the stick's folder is a disk of its own.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== Undo of a trash on a stick puts the file back (scripts/files/job.sh restore-paths)");
const job = join(tree, "scripts/files/job.sh");
const tmp = mkdtempSync(join(tmpdir(), "tacit-trash-disk-"));
const bin = join(tmp, "bin");
mkdirSync(bin);
const realStat = execFileSync("bash", ["-c", "command -v stat"], { encoding: "utf8" }).trim();
// gio trash: a file on $STICK to $STICK/.Trash-$UID with its Path from the stick's top, others to the home trash
writeFileSync(join(bin, "gio"), `#!/bin/bash
[ "$1" = trash ] && [ "$2" != --restore ] || { echo "gio: Operation not supported" >&2; exit 1; }
shift; [ "$1" = -- ] && shift
p=$1
case "$p" in "$STICK"/*) t=$STICK/.Trash-$UID; rel=\${p#"$STICK"/} ;; *) t=$XDG_DATA_HOME/Trash; rel=$p ;; esac
mkdir -p "$t/files" "$t/info"
n=\${p##*/}; k=1; while [ -e "$t/files/$n" ]; do k=$((k+1)); n="\${p##*/}.$k"; done
mv -- "$p" "$t/files/$n" && printf '[Trash Info]\\nPath=%s\\nDeletionDate=2026-11-13T10:00:00\\n' "$(jq -rn --arg p "$rel" '$p | @uri')" > "$t/info/$n.trashinfo"
`);
writeFileSync(join(bin, "stat"), `#!/bin/bash
if [ "$1" = -c ] && [ "$2" = %m ]; then case "\${4:-$3}" in "$STICK"|"$STICK"/*) echo "$STICK"; exit 0 ;; esac; fi
exec ${realStat} "$@"
`);
for (const f of ["gio", "stat"]) chmodSync(join(bin, f), 0o755);

let n = 0;
// a fresh home and stick, a photo on `which`: trash it (job a), then Undo it as Jobs.undo does (job b)
function scene(which) {
  const home = join(tmp, `home${++n}`), docs = join(home, "Pictures"), stick = join(tmp, `stick${n}`);
  mkdirSync(docs, { recursive: true }); mkdirSync(stick);
  const name = "IMG 1 #50%.jpg", path = join(which === "stick" ? stick : docs, name);
  writeFileSync(path, "PHOTO");
  const env = { PATH: `${bin}:${process.env.PATH}`, HOME: home, XDG_DATA_HOME: join(home, ".local/share"),
    XDG_STATE_HOME: join(home, ".local/state"), JOB: job, STICK: stick, P: path };
  const report = id => JSON.parse(readFileSync(join(home, ".local/state/quickshell/user/files/jobs", `${id}.json`), "utf8"));
  const trash = which === "stick" ? join(stick, `.Trash-${process.getuid()}`) : join(home, ".local/share/Trash");
  const inTrash = () => ["files", "info"].flatMap(d => (existsSync(join(trash, d)) ? readdirSync(join(trash, d)) : []));
  execFileSync("bash", ["-c", `bash "$JOB" a trash "$P"`], { env });
  const trashed = inTrash();
  execFileSync("bash", ["-c", `u=$(jq -c .undo "$XDG_STATE_HOME/quickshell/user/files/jobs/a.json")
mapfile -t a < <(jq -r '.paths[]' <<<"$u"); bash "$JOB" b restore-paths "\${a[@]}"`], { env });
  return { trashed, trash, a: report("a"), b: report("b"), back: existsSync(path) && readFileSync(path, "utf8") === "PHOTO",
    left: inTrash() };
}

try {
  {
    const s = scene("stick");
    check("a photo trashed on a stick lands in the stick's own trash", s.a.state === "done" && s.trashed.length === 2,
      `${s.a.state} "${s.a.error}", ${s.trash}: ${JSON.stringify(s.trashed)}`);
    check("Undo puts it back where it was", s.b.state === "done" && s.back, `${s.b.state} "${s.b.error}"`);
    check("and takes it and its record out of the stick's trash", s.left.length === 0, JSON.stringify(s.left));
  }
  {
    const s = scene("home");
    check("Undo of a trash in the home folder still puts it back", s.trashed.length === 2 && s.b.state === "done" && s.back &&
      s.left.length === 0, `${s.b.state} "${s.b.error}", trashed ${JSON.stringify(s.trashed)}, left ${JSON.stringify(s.left)}`);
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
