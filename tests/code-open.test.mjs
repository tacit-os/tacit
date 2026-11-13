// Which project bin/code-open opens Graphis on, run under sh with a pretend tacit-app that only notes the project it is
// given (CODE_PROJECT), in a home folder that is a git repository of dotfiles: the launcher gives no folder and runs in
// the home folder, and a folder asked for may not be there.
import { spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== the project code-open opens (bin/code-open)");
const tmp = realpathSync(mkdtempSync(join(tmpdir(), "tacit-code-open-")));
try {
  const bin = join(tmp, "bin"), home = join(tmp, "home"), app = join(home, "dev", "app");
  mkdirSync(bin); mkdirSync(join(app, "src"), { recursive: true });
  writeFileSync(join(bin, "tacit-app"), '#!/bin/sh\n[ "$1" = ensure ] && { printf "%s" "$CODE_PROJECT" > "$NOTE"; echo started; }\nexit 0\n', { mode: 0o755 });
  writeFileSync(join(bin, "notify-send"), "#!/bin/sh\n", { mode: 0o755 });
  for (const r of [home, app]) spawnSync("git", ["init", "-q", r]);
  const note = join(tmp, "project");
  const open = (cwd, ...args) => {
    rmSync(note, { force: true });
    const r = spawnSync("sh", [join(tree, "bin/code-open"), ...args], { cwd, encoding: "utf8",
      env: { PATH: `${bin}:${process.env.PATH}`, HOME: home, TACIT_BIN: bin, NOTE: note, GIT_CONFIG_NOSYSTEM: "1" } });
    let project = null;
    try { project = readFileSync(note, "utf8"); } catch {}
    return { status: r.status, project };
  };

  const launcher = open(home);
  check("the launcher (no folder, in a home folder that is a repository) shows the picker", launcher.project === "", `opened "${launcher.project}"`);
  const missing = open(home, join(home, "dev", "nowhere", "app"));
  check("a folder under one that is not there opens nothing", missing.status !== 0 && missing.project === null,
    `exit ${missing.status}, opened "${missing.project}"`);
  const inRepo = open(join(app, "src"));
  check("no folder, in a project's folder: that project", inRepo.project === app, `opened "${inRepo.project}"`);
  const asked = open(tmp, join(app, "src"));
  check("a folder in a project: that project", asked.project === app, `opened "${asked.project}"`);
  const named = open(tmp, home);
  check("the home folder asked for by name: the home folder", named.project === home, `opened "${named.project}"`);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
