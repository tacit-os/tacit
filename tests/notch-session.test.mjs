// What a Claude Code hook tells the notch (bin/notch-session), run under bash with a pretend qs that notes its calls, a
// pretend hyprctl and a pretend user manager (systemctl --user show-environment), in a runtime folder of its own.
import { spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== what a Claude Code hook tells the notch (bin/notch-session)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-notch-session-"));
const bin = join(tmp, "bin"), calls = join(tmp, "qs-calls");
mkdirSync(bin);
writeFileSync(join(bin, "qs"), '#!/bin/sh\nprintf "%s|%s\\n" "$WAYLAND_DISPLAY" "$*" >> "$CALLS"\n', { mode: 0o755 });
writeFileSync(join(bin, "hyprctl"), '#!/bin/sh\ncase "$1" in clients) printf %s "$CLIENTS" ;; activewindow) printf %s "$ACTIVE" ;; esac\n', { mode: 0o755 });
writeFileSync(join(bin, "systemctl"), '#!/bin/sh\n[ "$*" = "--user show-environment" ] && printf "%b" "$MANAGER"\n', { mode: 0o755 });
let n = 0;
// one hook event; the qs calls it made, as "<WAYLAND_DISPLAY>|<arguments>"
let shell = 0;   // the pid of the sh the last hook ran under
function hook(event, more = {}, env = {}) {
  rmSync(calls, { force: true });
  shell = spawnSync("sh", ["-c", 'bash "$0"; true', join(tree, "bin/notch-session")], { encoding: "utf8",
    input: JSON.stringify({ hook_event_name: event, session_id: more.session_id ?? `s${n++}`, cwd: "/home/sam/app", ...more }),
    env: { PATH: `${bin}:${process.env.PATH}`, HOME: join(tmp, "home"), XDG_RUNTIME_DIR: join(tmp, "run"), CREW_STATE: join(tmp, "crew"),
      CALLS: calls, CLIENTS: "[]", ACTIVE: "{}", MANAGER: "", ...env } }).pid;
  try { return readFileSync(calls, "utf8").split("\n").filter(Boolean); } catch { return []; }
}
try {
  mkdirSync(join(tmp, "run"));

  // a Praxis session under agent-host: started before the compositor, so neither is in its environment
  const praxis = hook("UserPromptSubmit", {}, { MANAGER: "WAYLAND_DISPLAY=wayland-1\\nTACIT_SHELL=/usr/share/tacit/shell\\nPATH=/usr/bin\\n" });
  check("a session started before the compositor reaches the shell the user manager names",
    praxis.length > 0 && praxis.every(c => c.startsWith("wayland-1|-p /usr/share/tacit/shell ipc call sessions ")), JSON.stringify(praxis));
  const terminal = hook("UserPromptSubmit", {}, { WAYLAND_DISPLAY: "wayland-2", TACIT_SHELL: "/opt/tacit/shell", MANAGER: "TACIT_SHELL=/usr/share/tacit/shell\\n" });
  check("a session in a terminal keeps the shell and display it was given",
    terminal.length > 0 && terminal.every(c => c.startsWith("wayland-2|-p /opt/tacit/shell ")), JSON.stringify(terminal));

  // The window: this test's own process stands in for the terminal (it is an ancestor of the hook) and the sh it starts
  // the hook from for the shell in that window. One terminal process can have several windows (footclient's server).
  const win = (event, sid, clients, active, more = {}) => {
    const c = hook(event, { session_id: sid, ...more }, { TACIT_SHELL: "/s", WAYLAND_DISPLAY: "w", CLIENTS: JSON.stringify(clients),
      ACTIVE: JSON.stringify(active) }).find(l => l.includes(" update "));
    return c ? (c.split(" update ")[1].split(" ")[2] ?? "") : null;
  };
  const me = process.pid, other = { pid: 1, address: "0xccc" };
  const two = [{ pid: me, address: "0xaaa" }, { pid: me, address: "0xbbb" }, other];
  check("one window of the terminal: it is the session's", win("Notification", "w1", [{ pid: me, address: "0xaaa" }, other], other) === "0xaaa");
  const typed = win("UserPromptSubmit", "w2", two, { pid: me, address: "0xbbb" });
  check("two windows of one terminal process: a prompt typed in the one in front ties the session to that one", typed === "0xbbb", `tied to ${typed}`);
  const cached = (() => { try { return readFileSync(join(tmp, "run", "notch-sessions", "w2.addr"), "utf8").trim(); } catch { return ""; } })();
  check("and kept under the window's own shell, not the terminal process all its windows share",
    cached === `${shell} 0xbbb`, `cached "${cached}", the shell is ${shell} and the terminal ${me}`);
  const asked = win("Notification", "w3", two, other);
  check("two windows and nothing the person did in one: no window is guessed", asked === "", `tied to ${asked}`);
  const compact = win("SessionStart", "w4", two, { pid: me, address: "0xbbb" }, { source: "compact" });
  check("nor at a start Claude made itself (compacting)", compact === "", `tied to ${compact}`);

  // the activity line, for tools beyond the shell, files, search, the web and sub-agents
  const doing = (tool, input = {}) => (hook("PreToolUse", { session_id: "a1", tool_name: tool, tool_input: input }, { TACIT_SHELL: "/s", WAYLAND_DISPLAY: "w" })
    .find(l => l.includes(" activity a1 ")) ?? "").split(" activity a1 ")[1];
  for (const [tool, line] of [["mcp__omnicord__send_message", "using omnicord"], ["mcp__claude_ai_Claude_Docs__batch", "using claude ai claude docs"],
    ["TodoWrite", "planning"], ["TaskCreate", "planning"], ["ToolSearch", "working"], ["Skill", "working"]])
    check(`${tool} reads "${line}"`, doing(tool) === line, `read "${doing(tool)}"`);
  check("Bash still names its command", doing("Bash", { command: "ls -la" }) === "running ls -la", doing("Bash", { command: "ls -la" }));

  // shell-praxis review r1 [3]: a sub-agent's tool call comes under the parent's session_id, with its agent_id; passed
  // on as the session's own, it ended the wait of a permission prompt still open in the terminal
  const pre = more => hook("PreToolUse", { session_id: "a2", tool_name: "Read", tool_input: { file_path: "/p/notes.md" }, ...more },
    { TACIT_SHELL: "/s", WAYLAND_DISPLAY: "w" }).filter(l => / (activity|agentActivity) a2 /.test(l)).map(l => l.split(" ipc call sessions ")[1]);
  const sub = pre({ agent_id: "a7f3c2", agent_type: "Explore" }), own = pre({});
  check("a sub-agent's tool call is told as that agent's, the main thread's as the session's",
    JSON.stringify(sub) === '["agentActivity a2 a7f3c2 reading notes.md"]' && JSON.stringify(own) === '["activity a2 reading notes.md"]',
    `sub-agent ${JSON.stringify(sub)}, main ${JSON.stringify(own)}`);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
