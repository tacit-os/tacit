// Two downloads of the same cover at once both end with the cover (modules/ii/bar/Media.qml, modules/common/widgets/
// Player.qml, modules/ii/background/widgets/media/MediaWidget.qml, modules/ii/equalizer/EqualizerPopup.qml): each
// file's own download line runs under bash, twice for the same cover, with a pretend curl that writes the file through
// one descriptor over a moment, as curl -o does. The bar, the media card, the desktop widget and the equalizer all fetch
// the playing track's cover into the same file when it changes.
import { spawnSync } from "child_process";
import { chmodSync, existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, read } from "./lib/check.mjs";

console.log("== the same cover downloaded twice at once (Media.qml, Player.qml, MediaWidget.qml, EqualizerPopup.qml)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-cover-"));
writeFileSync(join(tmp, "curl"), `#!/bin/bash
out=""; while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift 2 ;; *) shift ;; esac; done
if [ "\${FAKE_FAIL:-0}" = 1 ]; then sleep "\${FAKE_DELAY:-0}"; exit 22; fi
exec 3>"$out"; printf 'COVER-' >&3; sleep "\${FAKE_DELAY:-0}"; printf 'WHOLE' >&3; exec 3>&-
`);
chmodSync(join(tmp, "curl"), 0o755);
// two runs, the second started 0.2 s after the first: their exit codes, and what is in the cover's folder after
const driver = `s=$1; out=$2
FAKE_DELAY=$3 bash -c "$s" _ https://example.org/cover.jpg "$out" & a=$!
sleep 0.2
FAKE_DELAY=$4 FAKE_FAIL=$5 bash -c "$s" _ https://example.org/cover.jpg "$out" & b=$!
wait $a; ea=$?; wait $b; eb=$?; echo "$ea $eb"`;

try {
  for (const file of ["modules/ii/bar/Media.qml", "modules/common/widgets/Player.qml", "modules/ii/background/widgets/media/MediaWidget.qml",
    "modules/ii/equalizer/EqualizerPopup.qml"]) {
    const script = read(file).match(/\["bash", "-c",\s*`([^`]*curl[^`]*)`/)[1];
    const run = (...args) => {
      const dir = mkdtempSync(join(tmp, "art-")), out = join(dir, "5f1c0e");
      const r = spawnSync("bash", ["-c", driver, "_", script, out, ...args], { encoding: "utf8", env: { PATH: `${tmp}:${process.env.PATH}` } });
      const [a, b] = r.stdout.trim().split(" ").map(Number);
      return { a, b, cover: existsSync(out) ? readFileSync(out, "utf8") : null, left: readdirSync(dir).filter(f => f !== "5f1c0e") };
    };
    const name = file.replace(/.*\//, "");
    const both = run("0.6", "0.6", "0");
    check(`${name}: two at once both end with the cover, whole`, both.a === 0 && both.b === 0 && both.cover === "COVER-WHOLE",
      `exits ${both.a} and ${both.b}, cover ${JSON.stringify(both.cover)}`);
    check(`${name}: and leave no temporary file`, both.left.length === 0, both.left.join(", "));
    const late = run("0.6", "0.6", "1");   // both start before the cover is there
    check(`${name}: one that fails after the other put the cover there counts as done`, late.a === 0 && late.b === 0 && late.cover === "COVER-WHOLE",
      `exits ${late.a} and ${late.b}`);
    const dir = mkdtempSync(join(tmp, "art-")), out = join(dir, "5f1c0e");
    const alone = spawnSync("bash", ["-c", script, "_", "https://example.org/cover.jpg", out], { env: { PATH: `${tmp}:${process.env.PATH}`, FAKE_FAIL: "1" } });
    check(`${name}: a failed one alone still fails and keeps nothing`, alone.status !== 0 && readdirSync(dir).length === 0, `exit ${alone.status}, ${readdirSync(dir).join(", ")}`);
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
