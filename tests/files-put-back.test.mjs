// Put back from Files' Trash (scripts/files/job.sh restore) when something else now has the trashed file's name where it
// came from: the trashed one comes back beside it as "notes 2.txt", the other is left as it is, and the job says so, in
// the line services/Jobs.qml's label() makes of its report. The job runs under bash in a home of its own whose trash
// holds two notes.txt from Documents (the second under the name the trash gave it).
import { execFileSync } from "child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== Put back onto a name that is taken now (scripts/files/job.sh restore, Jobs.label)");
const job = join(tree, "scripts/files/job.sh");
const jobs = read("services/Jobs.qml");
const Jobs = {};
for (const name of ["verb", "past", "label"]) {
  const f = qmlFunction(jobs, name);
  Jobs[name] = inScope({ root: Jobs, Voice: { count: (n, w) => `${n} ${w}s`, cant: w => `Can't: ${w}` }, Files: { placeName: p => p.split("/").pop() } }, f.params, f.body);
}
const tmp = mkdtempSync(join(tmpdir(), "tacit-put-back-"));

try {
  const home = join(tmp, "home"), docs = join(home, "Documents"), trash = join(home, ".local/share/Trash");
  const env = { PATH: process.env.PATH, HOME: home, XDG_DATA_HOME: join(home, ".local/share"), XDG_STATE_HOME: join(home, ".local/state") };
  const trashed = (name, from, text) => {
    writeFileSync(join(trash, "files", name), text);
    writeFileSync(join(trash, "info", `${name}.trashinfo`), `[Trash Info]\nPath=${from}\nDeletionDate=2026-11-13T10:00:00\n`);
  };
  const run = (id, ...items) => {
    execFileSync("bash", [job, id, "restore", ...items], { env });
    return JSON.parse(readFileSync(join(home, ".local/state/quickshell/user/files/jobs", `${id}.json`), "utf8"));
  };
  for (const d of [docs, join(trash, "files"), join(trash, "info")]) mkdirSync(d, { recursive: true });
  trashed("notes.txt", join(docs, "notes.txt"), "OLD");
  trashed("notes.2.txt", join(docs, "notes.txt"), "OLDER");
  writeFileSync(join(docs, "notes.txt"), "NEW");
  const text = f => (existsSync(f) ? readFileSync(f, "utf8") : null);

  for (const [id, item, as, was] of [["a", "notes.txt", "notes 2.txt", "OLD"], ["b", "notes.2.txt", "notes 3.txt", "OLDER"]]) {
    const r = run(id, item);
    check(`Put back of ${item} with another notes.txt there brings it back beside it as ${as}`,
      r.state === "done" && text(join(docs, as)) === was && text(join(docs, "notes.txt")) === "NEW"
        && !existsSync(join(trash, "files", item)) && !existsSync(join(trash, "info", `${item}.trashinfo`)),
      `${r.state}${r.error ? `: "${r.error}"` : ""}; Documents holds ${JSON.stringify(execFileSync("ls", [docs], { encoding: "utf8" }).trim().split("\n"))}`);
    check(`and says so: "Put back notes.txt as ${as}"`, Jobs.label({ ...r, kind: "job" }) === `Put back notes.txt as ${as}`, JSON.stringify(Jobs.label({ ...r, kind: "job" })));
  }
  // two at once, one in the way
  trashed("a.txt", join(docs, "a.txt"), "A");
  trashed("b.txt", join(docs, "b.txt"), "B");
  writeFileSync(join(docs, "a.txt"), "A NEW");
  const two = run("c", "a.txt", "b.txt");
  check("two at once, one of them in the way: both back, and the line names the one under a new name",
    two.state === "done" && text(join(docs, "a 2.txt")) === "A" && text(join(docs, "b.txt")) === "B" && Jobs.label({ ...two, kind: "job" }) === "Put 2 items back · a.txt as a 2.txt",
    `${two.state}: ${JSON.stringify(Jobs.label({ ...two, kind: "job" }))}`);
  // nothing in the way: as before
  trashed("c.txt", join(docs, "c.txt"), "C");
  const plain = run("d", "c.txt");
  check("with nothing in the way it comes back under its own name and the line is the usual one",
    plain.state === "done" && text(join(docs, "c.txt")) === "C" && !/ as /.test(Jobs.label({ ...plain, kind: "job" })), JSON.stringify(Jobs.label({ ...plain, kind: "job" })));
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
