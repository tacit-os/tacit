// Put back from Files' Trash (scripts/files/job.sh restore) when something else now has the trashed file's name where it
// came from: the trashed one is not "already back", and both must be left as they are. The job runs under bash in a
// home of its own whose trash holds two notes.txt from Documents (the second under the name the trash gave it).
import { execFileSync } from "child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== Put back says another file is in the way, not that it is back (scripts/files/job.sh restore)");
const job = join(tree, "scripts/files/job.sh");
const tmp = mkdtempSync(join(tmpdir(), "tacit-put-back-"));

try {
  const home = join(tmp, "home"), docs = join(home, "Documents"), trash = join(home, ".local/share/Trash");
  for (const d of [docs, join(trash, "files"), join(trash, "info")]) mkdirSync(d, { recursive: true });
  for (const [name, text] of [["notes.txt", "OLD"], ["notes.2.txt", "OLDER"]]) {
    writeFileSync(join(trash, "files", name), text);
    writeFileSync(join(trash, "info", `${name}.trashinfo`), `[Trash Info]\nPath=${join(docs, "notes.txt")}\nDeletionDate=2026-11-13T10:00:00\n`);
  }
  writeFileSync(join(docs, "notes.txt"), "NEW");
  const env = { PATH: process.env.PATH, HOME: home, XDG_DATA_HOME: join(home, ".local/share"), XDG_STATE_HOME: join(home, ".local/state") };
  for (const [id, item] of [["a", "notes.txt"], ["b", "notes.2.txt"]]) {
    execFileSync("bash", [job, id, "restore", item], { env });
    const r = JSON.parse(readFileSync(join(home, ".local/state/quickshell/user/files/jobs", `${id}.json`), "utf8"));
    check(`Put back of ${item} says another notes.txt is already where it came from`,
      r.state === "failed" && /^Another notes\.txt is already where this one came from$/.test(r.error), `${r.state}: "${r.error}"`);
    check(`and leaves the new notes.txt, and ${item} in the trash`, readFileSync(join(docs, "notes.txt"), "utf8") === "NEW" &&
      existsSync(join(trash, "files", item)) && existsSync(join(trash, "info", `${item}.trashinfo`)));
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
