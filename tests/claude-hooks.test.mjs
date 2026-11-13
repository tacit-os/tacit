// The notch's Claude Code hooks on a new account (scripts/praxis/claude_hooks.py, FirstRunExperience.qml): the merge run
// on a scratch Claude Code folder with no settings, the person's own settings, settings that already run a notch-session,
// and a file that is not JSON; then the account's first start, FirstRunExperience's own start() under node, asking for
// it. bin/notch-session is the only source of a terminal session's "needs you", "done" and activity line, and nothing
// put the hooks on a new install.
import { spawnSync } from "child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== the notch's Claude Code hooks on a new account (claude_hooks.py)");
const script = join(tree, "scripts/praxis/claude_hooks.py");
const hook = "/usr/lib/tacit/bin/notch-session";
const dir = mkdtempSync(join(tmpdir(), "tacit-claude-hooks-"));
const file = join(dir, "settings.json");
const merge = text => {
  rmSync(file, { force: true });
  if (text !== undefined) writeFileSync(file, text);
  if (!existsSync(script)) return { status: -1 };
  const r = spawnSync("python3", ["-I", script, hook], { env: { ...process.env, CLAUDE_CONFIG_DIR: dir }, encoding: "utf8" });
  let settings = null;
  try { settings = JSON.parse(readFileSync(file, "utf8")); } catch {}
  return { status: r.status, settings, text: existsSync(file) ? readFileSync(file, "utf8") : null };
};
const ours = groups => (groups ?? []).filter(g => g.hooks?.some(h => h.command === hook));
try {
  const fresh = merge();
  const events = Object.keys(fresh.settings?.hooks ?? {});
  check("no settings yet: they are made with the hook on its eight events",
    fresh.status === 0 && events.length === 8 && events.every(e => ours(fresh.settings.hooks[e]).length === 1), JSON.stringify(events));
  check("the activity line and sub-agents never hold Claude up; Notification only for the prompts that need the person",
    ours(fresh.settings?.hooks?.PreToolUse)[0]?.hooks[0].async === true && ours(fresh.settings?.hooks?.Stop)[0]?.hooks[0].async === undefined
      && ours(fresh.settings?.hooks?.Notification)[0]?.matcher === "permission_prompt|agent_needs_input|elicitation_dialog");

  const own = { model: "opus", permissions: { allow: ["Bash(ls:*)"] },
    hooks: { PreToolUse: [{ matcher: "Bash", hooks: [{ type: "command", command: "/home/sam/bin/guard", timeout: 5 }] }] } };
  const mine = merge(JSON.stringify(own, null, 2));
  check("the person's own settings and hooks stay, the notch's are added after theirs",
    mine.settings?.model === "opus" && mine.settings?.permissions?.allow?.[0] === "Bash(ls:*)"
      && mine.settings?.hooks?.PreToolUse?.[0]?.hooks?.[0]?.command === "/home/sam/bin/guard" && ours(mine.settings?.hooks?.PreToolUse).length === 1,
    JSON.stringify(mine.settings?.hooks?.PreToolUse));

  const handMade = merge(JSON.stringify({ hooks: Object.fromEntries(["SessionStart", "UserPromptSubmit", "Stop", "SessionEnd", "PreToolUse",
    "SubagentStart", "SubagentStop", "Notification"].map(e => [e, [{ hooks: [{ type: "command", command: "/home/sam/.local/bin/notch-session" }] }]])) }));
  check("settings that already run a notch-session are not written, so no event is reported twice",
    handMade.status === 0 && Object.values(handMade.settings?.hooks ?? {}).every(g => ours(g).length === 0 && g.length === 1));

  const broken = merge('{ "model": "opus", ');
  check("a file that is not JSON is left as it was", broken.status === 1 && broken.text === '{ "model": "opus", ', `exit ${broken.status}`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}

// an account's first start: FirstRunExperience's start() with its Processes standing in
{
  const f = qmlFunction(read("services/FirstRunExperience.qml"), "start");
  const ran = [];
  const root = { firstRun: true };
  inScope({ root, Config: { ready: true }, nameProc: {}, Directories: { tacitBin: "/usr/lib/tacit/bin" },
    Quickshell: { execDetached: argv => ran.push(argv), shellPath: p => `/usr/share/tacit/shell/${p}` } }, f.params, f.body)();
  check("an account's first start merges them, with the installed notch-session",
    ran.some(a => a[0] === "python3" && a[1] === "/usr/share/tacit/shell/scripts/praxis/claude_hooks.py" && a[2] === "/usr/lib/tacit/bin/notch-session"),
    JSON.stringify(ran.map(a => a.slice(0, 2))));
}
done();
