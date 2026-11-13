// The Review panel's hunks (bin/claude-review), run on a scratch repository with a git config of its own: the names
// and lines it lists, and a revert, under the settings people give git for their own diffs (diff.noprefix,
// diff.mnemonicPrefix, an external diff, a textconv driver); and a project with thousands of new files, which are not
// all read, with the Review panel's own rows binding (ChangesPanel.qml) under node for the line that counts the rest.
import { spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, utimesSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== the Review panel's hunks under a person's git config (bin/claude-review)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-review-"));
const gitconfig = join(tmp, "gitconfig");
const env = { ...process.env, HOME: tmp, GIT_CONFIG_GLOBAL: gitconfig, GIT_CONFIG_NOSYSTEM: "1", XDG_RUNTIME_DIR: join(tmp, "run"),
  GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.org", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.org" };
const review = (...args) => spawnSync("python3", ["-I", join(tree, "bin/claude-review"), ...args], { env, encoding: "utf8" });
const git = (repo, ...args) => spawnSync("git", ["-C", repo, ...args], { env, encoding: "utf8" });
mkdirSync(join(tmp, "run"));

// a repository with a changed file in a folder and one at the top, under this config
let n = 0;
function repo(config) {
  writeFileSync(gitconfig, config);
  const r = join(tmp, `repo${n++}`);
  mkdirSync(join(r, "sub"), { recursive: true });
  git(r, "init", "-q");
  writeFileSync(join(r, "sub", "my file.txt"), "one\ntwo\nthree\n");
  writeFileSync(join(r, "top.txt"), "alpha\nbeta\n");
  git(r, "add", "-A");
  git(r, "commit", "-qm", "start");
  writeFileSync(join(r, "sub", "my file.txt"), "one\nTWO and more\nthree\n");
  writeFileSync(join(r, "top.txt"), "alpha\nbeta\ngamma\n");
  return r;
}
const listed = r => { try { return JSON.parse(review("hunks", r).stdout).files; } catch { return []; } };
const names = files => JSON.stringify(files.map(f => f.path).sort());
const want = JSON.stringify(["sub/my file.txt", "top.txt"]);

try {
  for (const [what, config] of [
    ["diff.noprefix", "[diff]\n\tnoprefix = true\n"],
    ["diff.mnemonicPrefix", "[diff]\n\tmnemonicPrefix = true\n"],
    ["an external diff", `[diff]\n\texternal = ${join(tmp, "nodiff")}\n`],
  ]) {
    writeFileSync(join(tmp, "nodiff"), "#!/bin/sh\necho 'files differ'\n", { mode: 0o755 });
    const r = repo(config);
    const files = listed(r);
    check(`with ${what} every file is listed under its own name`, names(files) === want, names(files));
    const f = files.find(x => x.path === "sub/my file.txt");
    const res = f?.hunks?.[0] ? review("revert", r, join(r, "sub", "my file.txt"), f.hunks[0].id) : { status: -1, stderr: "no hunk listed" };
    check(`with ${what} a hunk is taken back`, res.status === 0 && readFileSync(join(r, "sub", "my file.txt"), "utf8") === "one\ntwo\nthree\n",
      (res.stderr || "").trim() || readFileSync(join(r, "sub", "my file.txt"), "utf8"));
  }

  // a textconv driver: git diff shows what the driver made of the file, not the file
  const r = repo("[diff \"upper\"]\n\ttextconv = tr a-z A-Z\n");
  writeFileSync(join(r, ".git", "info", "attributes"), "*.txt diff=upper\n");
  const f = listed(r).find(x => x.path === "top.txt");
  check("with a textconv driver the lines are the file's own", /\n\+gamma$/.test(f?.hunks?.[0]?.body ?? ""), f?.hunks?.[0]?.body);
  const res = f?.hunks?.[0] ? review("revert", r, join(r, "top.txt"), f.hunks[0].id) : { status: -1, stderr: "no hunk listed" };
  check("with a textconv driver a hunk is taken back", res.status === 0 && readFileSync(join(r, "top.txt"), "utf8") === "alpha\nbeta\n",
    (res.stderr || "").trim());

  // later-praxis-1 [15] a revert took back a change in a file the person had edited after the agent, at one click: with
  // the time the agent's edit was written, a file written later is left as it is and the panel told so
  {
    const r = repo("");
    const file = join(r, "top.txt"), edited = "alpha\nbeta\ngamma\n";
    utimesSync(file, new Date(2_000_000_000_000), new Date(2_000_000_000_000));
    const id = listed(r).find(x => x.path === "top.txt")?.hunks?.[0]?.id ?? "";
    const held = review("revert", r, file, id, String(2_000_000_000_000 - 60_000));
    const after = readFileSync(file, "utf8");
    const gone = review("revert", r, file, id, String(2_000_000_000_000 + 60_000));
    check("a file written after the agent's edit is not reverted and says changed; one not written since is",
      held.status === 0 && /"changed": true/.test(held.stdout) && after === edited && gone.status === 0 && /"undo"/.test(gone.stdout)
        && readFileSync(file, "utf8") === "alpha\nbeta\n", `${(held.stdout + held.stderr).trim()} | ${(gone.stdout + gone.stderr).trim()}`);
  }

  // a project with no .gitignore: node_modules, a build, dumps
  writeFileSync(gitconfig, "");
  const many = join(tmp, "many");
  mkdirSync(join(many, "node_modules"), { recursive: true });
  git(many, "init", "-q");
  for (let i = 0; i < 250; i++) writeFileSync(join(many, "node_modules", `m${String(i).padStart(3, "0")}.js`), "module.exports = 1;\n");
  const m = JSON.parse(review("hunks", many).stdout || "{}");
  check("250 new files: the first 200 are listed with their lines and the other 50 counted",
    m.files?.length === 200 && m.unlisted === 50 && m.files.every(f => f.hunks?.length === 1), `${m.files?.length} listed, ${m.unlisted} counted`);
  const big = join(tmp, "big");
  mkdirSync(big);
  git(big, "init", "-q");
  for (let i = 0; i < 10; i++) writeFileSync(join(big, `dump${i}.txt`), ("x".repeat(99) + "\n").repeat(9000));   // 900 KB each
  const b = JSON.parse(review("hunks", big).stdout || "{}");
  check("ten new files of 900 KB: reading stops past 4 MB and the rest are counted", b.files?.length === 5 && b.unlisted === 5,
    `${b.files?.length} listed, ${b.unlisted} counted`);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}

// the panel: one line for the new files not listed
{
  const rows = inScope({ panel: { shownFiles: [], review: { repo: "/home/sam/app", files: [], unlisted: 50 }, open: {}, scope: "all", cursor: "",
    isKept: () => false, context: {}, comments: [], writing: null, showOutside: false } }, "", qmlProperty(read("modules/claude/ChangesPanel.qml"), "rows"))();
  check("the Review panel says how many more new files there are", rows.some(r => r.kind === "note" && r.text === "50 more new files"), JSON.stringify(rows));
}

// later-praxis-1 [15] the panel's side: the time it sends is when the agent's last edit of that file was surely written
// (the first item after the call that is not another call), and an answer of changed holds the revert for the question
{
  const src = read("modules/claude/ChangesPanel.qml");
  const sent = [];
  const panel = { cwd: "/home/sam/app", home: "/home/sam", ownAt: {}, asking: null, lastRevert: null,
    items: [
      { role: "user", kind: "text", ts: 1000 },
      { kind: "tool", tool: "Edit", files: [{ path: "/home/sam/app/top.txt" }], ts: 2000, result: "ok" },
      { kind: "tool", tool: "Edit", files: [{ path: "other.txt" }], ts: 2001, result: "ok" },   // the same message's next call
      { role: "assistant", kind: "text", ts: 45000 },                                             // after a permission wait
      { kind: "tool", tool: "Write", files: [{ path: "~/app/new.txt" }], ts: 50000, error: true },
      { role: "user", kind: "text", ts: 90000 } ],
    act: (args, cb) => { sent.push({ args, cb }); return true; } };
  for (const f of ["editDone", "revert"]) { const q = qmlFunction(src, f); if (q) panel[f] = inScope({ panel, Date: { now: () => 99999 } }, q.params, q.body); }
  const top = { path: "top.txt", abs: "/home/sam/app/top.txt", repo: "/home/sam/app" }, hunk = { id: "h1", line: 3 };
  if (panel.revert) panel.revert(top, hunk);
  const first = sent[0]?.args ?? [];
  sent[0]?.cb?.('{"ok": false, "changed": true}');
  const held = panel.asking;
  if (panel.revert && held) panel.revert(held.file, held.hunk, true);
  const anyway = sent[1]?.args ?? [];
  sent[1]?.cb?.('{"ok": true, "undo": "/run/u.patch"}');
  if (panel.revert) panel.revert(top, hunk);
  const again = sent[2]?.args ?? [];
  if (panel.revert) panel.revert({ path: "new.txt", abs: "/home/sam/app/new.txt", repo: "/home/sam/app" }, hunk);
  const refused = sent[3]?.args ?? [];
  check("Revert sends when the agent's edit was written, holds the revert on changed, and Revert anyway sends none",
    JSON.stringify(first) === '["revert","/home/sam/app","/home/sam/app/top.txt","h1","45000"]' && held?.hunk === hunk && JSON.stringify(anyway.slice(4)) === "[]"
      && panel.asking === null && panel.lastRevert?.undo === "/run/u.patch",
    `sent ${JSON.stringify(first)}, then ${JSON.stringify(anyway)}, asking ${JSON.stringify(held)}`);
  check("its own revert is not a change of someone else's, and a file the agent's edit of failed sends no time",
    again[4] === "99999" && refused.length === 4, `next ${JSON.stringify(again)}, a refused Write ${JSON.stringify(refused)}`);
  check("the question is the decided one, and Esc puts it away",
    src.includes(`"This file changed after the agent's edit. Revert anyway?"`) && /Key_Escape && panel\.asking\) \{ panel\.asking = null/.test(src));
}
done();
