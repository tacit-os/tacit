// What bin/tacit-bg runs, under sh with a pretend systemd-run that runs what follows its "--" and a user bus socket of
// its own: on a computer with no cores 4-7 (a pretend taskset refuses them with the kernel's own error, as
// `taskset -c 99 true` does here), and on this computer's own CPUs.
import { spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { availableParallelism, tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== background work on any number of cores (bin/tacit-bg)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-bg-"));
try {
  const bin = join(tmp, "bin"), run = join(tmp, "run"), out = join(tmp, "out");
  mkdirSync(bin); mkdirSync(run);
  spawnSync("python3", ["-I", "-c", "import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])", join(run, "bus")]);
  writeFileSync(join(bin, "systemd-run"), '#!/bin/sh\nwhile [ $# -gt 0 ] && [ "$1" != "--" ]; do shift; done\nshift\nexec "$@"\n', { mode: 0o755 });
  const small = join(tmp, "small");
  mkdirSync(small);
  writeFileSync(join(small, "taskset"), `#!/bin/sh
[ "$1 $2" = "-c 4-7" ] && { echo "taskset: failed to set pid $$'s affinity: Invalid argument" >&2; exit 1; }
exec ${spawnSync("sh", ["-c", "command -v taskset"], { encoding: "utf8" }).stdout.trim()} "$@"
`, { mode: 0o755 });
  const bg = fewCores => {
    rmSync(out, { force: true });
    const r = spawnSync("sh", [join(tree, "bin/tacit-bg"), "sh", "-c", 'grep Cpus_allowed_list /proc/self/status > "$OUT"'],
      { encoding: "utf8", env: { PATH: `${fewCores ? small + ":" : ""}${bin}:${process.env.PATH}`, XDG_RUNTIME_DIR: run, OUT: out } });
    let ran = null;
    try { ran = readFileSync(out, "utf8").split(":")[1].trim(); } catch {}
    return { status: r.status, ran, err: r.stderr.trim() };
  };

  const four = bg(true);
  check("with no cores 4-7 the command still runs", four.status === 0 && four.ran !== null, `exit ${four.status}, ${four.err || "ran on " + four.ran}`);
  if (availableParallelism() >= 8) {
    const here = bg(false);
    check("with cores 4-7 it runs on those", here.status === 0 && here.ran === "4-7", `exit ${here.status}, ${here.err || "ran on " + here.ran}`);
  } else console.log(`  (this computer has ${availableParallelism()} CPUs: the pinning to 4-7 is not checked here)`);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
