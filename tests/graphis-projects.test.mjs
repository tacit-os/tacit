// Graphis's project picker lists the git repositories under home (modules/code/ProjectPicker.qml): the scan's own fd
// command and its output handler run on a home of its own with a repository, a worktree and a submodule (whose .git is
// a file), repositories five and six folders down, and the tool folders the picker leaves out.
import { spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the project picker finds worktrees and deeper repositories (ProjectPicker.qml)");
const src = read("modules/code/ProjectPicker.qml");
const at = src.indexOf("[", src.indexOf("command:", src.indexOf("id: scan")));
const command = src.slice(at, matchBrace(src, at) + 1);
const streamAt = src.indexOf("onStreamFinished:", src.indexOf("id: scan"));
const handler = src.slice(streamAt + "onStreamFinished:".length, src.indexOf("\n        }", streamAt));

if (spawnSync("fd", ["--version"]).status !== 0) console.log("  skip  fd is not installed here: nothing to run");
else {
  const home = mkdtempSync(join(tmpdir(), "tacit-projects-"));
  try {
    const repo = p => mkdirSync(join(home, p, ".git"), { recursive: true });
    const linked = p => { mkdirSync(join(home, p), { recursive: true }); writeFileSync(join(home, p, ".git"), "gitdir: /elsewhere\n"); };
    repo("dev/app");
    linked("dev/app-fix");                         // git worktree add ../app-fix
    linked("dev/app/vendor/lib");                  // a submodule
    repo("code/github.com/owner/tool");            // five down
    repo("go/src/github.com/owner/server");        // six down
    repo(".cache/someone/checkout");               // a tool's own: left out, as before
    const argv = inScope({ Quickshell: { env: k => (k === "HOME" ? home : "") } }, "", `return (${command});`)();
    const out = spawnSync(argv[0], argv.slice(1), { encoding: "utf8" }).stdout;
    const picker = { found: [] };
    inScope({ picker, collected: out }, "", `(${handler.trim().replace(/this\.text/g, "collected")});`)();   // the collector's text
    const found = picker.found.map(p => p.slice(home.length + 1));
    for (const [p, what] of [["dev/app", "a repository"], ["dev/app-fix", "a worktree"], ["dev/app/vendor/lib", "a submodule"],
      ["code/github.com/owner/tool", "a repository five folders down"], ["go/src/github.com/owner/server", "a repository six folders down"]])
      check(`${what} is listed (~/${p})`, found.includes(p), JSON.stringify(found));
    check("a tool's checkout under ~/.cache is still left out", !found.some(p => p.startsWith(".cache")), JSON.stringify(found));
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
}
done();
