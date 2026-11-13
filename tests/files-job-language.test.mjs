// Files' jobs work, and say why they could not, in every language (scripts/files/job.sh): the runner reads gio's and
// coreutils' own words (a disk with no trash, permission denied), which they translate, so those tools run in the C
// locale. The job runs under bash with the real gio and coreutils in a home of its own, with German and Indonesian
// messages asked for (LANGUAGE, as a desktop in those languages sets it): a Replace and a trash on /dev/shm, a disk gio
// has no trash on, and a rename, a copy and a delete in a folder that can't be written to.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== Files' jobs read their tools' words in English, whatever the language (scripts/files/job.sh)");
const job = join(tree, "scripts/files/job.sh");
const tmp = mkdtempSync(join(tmpdir(), "tacit-job-language-"));
const shm = existsSync("/dev/shm") ? mkdtempSync("/dev/shm/tacit-job-language-") : "";
check("/dev/shm is here, a disk gio has no trash on", shm.length > 0);
let n = 0;
try {
  for (const lang of ["de", "id"]) {
    const home = join(tmp, lang), locked = join(home, "locked");
    mkdirSync(locked, { recursive: true });
    const env = { PATH: process.env.PATH, HOME: home, XDG_DATA_HOME: join(home, ".local/share"), XDG_STATE_HOME: join(home, ".local/state"),
      GIO_USE_VFS: "local", LANG: "en_US.UTF-8", LANGUAGE: lang };
    const run = (...args) => {
      const id = `j${++n}`;
      execFileSync("bash", [job, id, ...args], { env, encoding: "utf8" });
      return JSON.parse(readFileSync(join(home, ".local/state/quickshell/user/files/jobs", `${id}.json`), "utf8"));
    };
    if (shm) {
      const disk = join(shm, lang);
      mkdirSync(disk);
      writeFileSync(join(disk, "notes.txt"), "old");
      writeFileSync(join(home, "notes.txt"), "new");
      const r = run("copy", "replace", disk, join(home, "notes.txt"));
      check(`${lang}: Replace of notes.txt on a disk with no trash is done, with the new one there`,
        r.state === "done" && readFileSync(join(disk, "notes.txt"), "utf8") === "new", JSON.stringify({ state: r.state, error: r.error }));
      writeFileSync(join(disk, "gone.txt"), "");
      const t = run("trash", join(disk, "gone.txt"));
      check(`${lang}: a trash there says the disk has none, so Files offers Delete for good`, t.state === "failed" && t.error === "no trash on this disk", JSON.stringify(t.error));
    }
    // a folder that can't be written to: the reason is the person's to act on
    writeFileSync(join(locked, "a.txt"), "");
    writeFileSync(join(home, "b.txt"), "");
    chmodSync(locked, 0o555);
    const why = "you are not allowed to change it here";
    const rn = run("rename", join(locked, "a.txt"), "c.txt");
    check(`${lang}: a rename there says why it could not`, rn.error === `Could not rename: ${why}`, JSON.stringify(rn.error));
    const cp = run("copy", "keep", locked, join(home, "b.txt"));
    check(`${lang}: a copy into it says why`, cp.error === `Could not copy b.txt: ${why}`, JSON.stringify(cp.error));
    const rm = run("delete", join(locked, "a.txt"));
    check(`${lang}: a delete there says why`, rm.error === `Could not delete a.txt: ${why}`, JSON.stringify(rm.error));
    chmodSync(locked, 0o755);
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
  if (shm) rmSync(shm, { recursive: true, force: true });
}
done();
