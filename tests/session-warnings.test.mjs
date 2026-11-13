// What Restart and Shut down warn about (services/SessionWarnings.qml): its look at agent-host run by python3 against a
// pretend agent-host socket, its refresh() and the looks' own exit handlers under node, then what the session screen
// (modules/ii/sessionScreen/SessionScreen.qml) and the update's restart (services/Updates.qml) make of the answer.
import { execFile } from "child_process";
import { mkdtempSync, rmSync } from "fs";
import { createServer } from "net";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const warn = read("services/SessionWarnings.qml");
const screen = read("modules/ii/sessionScreen/SessionScreen.qml");
const updates = read("services/Updates.qml");

// the expression of "<key>:" first found after "id: <id>", or null when the file has no such id
function after(src, id, key) {
  const at = src.indexOf(`id: ${id}`);
  if (at < 0) return null;
  const k = src.indexOf(`${key}:`, at);
  return readExpression(src, k + key.length + 1).expr;
}

console.log("What Restart and Shut down warn about (services/SessionWarnings.qml)");
const Titles = new Function(`${read("modules/claude/Titles.js").replace(/^\.pragma library/m, "")}\nreturn { of, clean };`)();
const looked = { titles: "" };

// the look itself, against a socket that says hello as agent-host does: the sessions it runs, with their state
{
  const dir = mkdtempSync(join(tmpdir(), "tacit-warnings-"));
  const sock = join(dir, "agent-host.sock");
  const expr = after(warn, "detectAgentProc", "command");
  const cmd = expr && inScope({ Quickshell: { env: k => (k === "XDG_RUNTIME_DIR" ? dir : "") } }, "", `return (${expr});`)();
  const look = () => new Promise(res => {
    const t = Date.now();
    execFile(cmd[0], cmd.slice(1), { timeout: 10000 }, (err, out) => res({ code: err ? err.code : 0, ms: Date.now() - t, out }));
  });
  // says hello, then answers {"op":"history"} with these rows (after a state push, as a busy host sends), or never
  const host = (answer, rows = null) => new Promise(res => {
    const srv = createServer(c => {
      if (!answer) return;
      c.write(JSON.stringify(answer) + "\n");
      c.on("data", d => {
        if (rows && /"op":\s*"history"/.test(String(d)))
          c.end(JSON.stringify({ ev: "state", session: { id: "s0" } }) + "\n" + JSON.stringify({ ev: "history", sessions: rows }) + "\n");
      });
    });
    srv.listen(sock, () => res(srv));
  });
  const hello = (states, prompts = []) => ({ ev: "hello", version: "0.1.8", proto: 6,
    sessions: states.map((state, i) => ({ id: `s${i}`, tool: "claude", state, alive: true, prompt: prompts[i] ?? "" })), agents: {} });
  try {
    if (!cmd) {
      check("SessionWarnings asks agent-host whether a turn is running", false, "it has no detectAgentProc");
    } else {
      for (const [name, states, want] of [
        ["a session working", ["idle", "working"], 0],
        ["a session waiting on a permission, mid-turn", ["waiting"], 0],
        ["every session idle", ["idle", "idle"], 1],
        ["no sessions", [], 1],
      ]) {
        const srv = await host(hello(states));
        const r = await look();
        srv.close();
        check(`agent-host with ${name}: ${want === 0 ? "a turn is running" : "no turn"}`, r.code === want, `the look exited ${r.code}`);
      }
      rmSync(sock, { force: true });
      const none = await look();
      check("no agent-host: no turn, at once", none.code === 1 && none.ms < 2000, `exit ${none.code} after ${none.ms} ms`);
      const srv = await host(null);   // takes the connection and never says hello
      const hung = await look();
      srv.close();
      check("an agent-host that never answers: no turn, after the 3 s wait", hung.code === 1 && hung.ms < 6000, `exit ${hung.code} after ${hung.ms} ms`);

      // which conversations: the history's title, else its first question; a session the history lacks keeps the hello's
      const rows = [{ id: "s0", title: "", prompt: "Fix the login bug", lastPrompt: "and the tests" },
        { id: "s1", title: "Tidy the README", prompt: "tidy it" }, { id: "s9", title: "Not running" }];
      const h1 = await host(hello(["working", "waiting", "working", "idle"], ["shell crashed", "", "Rename the settings rows"]), rows);
      const named = await look();
      h1.close();
      looked.titles = named.out;
      let got = null;
      try { got = JSON.parse(named.out); } catch (e) {}
      check("the look names each turn's conversation from agent-host's history, the hello's prompt when the history lacks it",
        named.code === 0 && JSON.stringify((got ?? []).map(x => x.title || x.prompt)) === '["Fix the login bug","Tidy the README","Rename the settings rows"]',
        `exit ${named.code}, said ${JSON.stringify(named.out)}`);
      const h2 = await host(hello(["working"], ["Move the card"]), null);   // says hello, never answers the history
      const slow = await look();
      h2.close();
      check("an agent-host whose history never comes: the hello's prompt, within the 3 s",
        slow.code === 0 && /Move the card/.test(slow.out) && slow.ms > 2000 && slow.ms < 6000, `exit ${slow.code} after ${slow.ms} ms, said ${JSON.stringify(slow.out)}`);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// refresh() and the three looks' exit handlers: "checked" comes once every look has come back, agent-host's too
{
  let said = 0;
  const long = "Rewrite the whole update flow so that a skipped night is said in Settings";
  const root = { pending: 0, packageManagerRunning: false, downloadRunning: false, agentWorking: false, agentTitles: ["old"], checked: () => said++ };
  Object.assign(root, { root, Titles, detectPackageManagerProc: {}, detectDownloadProc: {}, detectAgentProc: {},
    agentOut: { text: JSON.stringify([{ title: "", prompt: "Fix the login bug" }, { title: long }]) } });
  for (const name of ["settle", "cut"]) {
    const f = qmlFunction(warn, name);
    if (f) root[name] = inScope(root, f.params, f.body);
  }
  const refresh = qmlFunction(warn, "refresh");
  const exited = id => { const e = after(warn, id, "onExited"); return e ? inScope(root, "", `return (${e});`)() : () => {}; };
  inScope(root, refresh.params, refresh.body)();
  exited("detectPackageManagerProc")(1, 0);
  exited("detectDownloadProc")(1, 0);
  const early = said;
  const cleared = JSON.stringify(root.agentTitles);
  exited("detectAgentProc")(0, 0);
  check("the warnings are said checked only once agent-host has answered too, and say an agent is working",
    early === 0 && said === 1 && root.agentWorking === true,
    `checked ${early} time(s) before agent-host answered, ${said} after; agentWorking ${root.agentWorking}`);
  const titles = root.agentTitles ?? [];
  check("the working conversations are named as Praxis names them, a long title cut at a word",
    cleared === "[]" && titles[0] === "Fix the login bug" && titles.length === 2 && titles[1].length <= 41 && titles[1].endsWith("…") && long.startsWith(titles[1].slice(0, -1)),
    `before the look ${cleared}, after ${JSON.stringify(titles)}`);
  if (looked.titles) {
    root.agentOut.text = looked.titles;
    exited("detectAgentProc")(0, 0);
    check("what the look said comes out as the names", JSON.stringify(root.agentTitles) === '["Fix the login bug","Tidy the README","Rename the settings rows"]',
      JSON.stringify(root.agentTitles));
  }
  exited("detectAgentProc")(1, 0);
  check("no turn running: no names", root.agentWorking === false && JSON.stringify(root.agentTitles) === "[]", JSON.stringify(root.agentTitles));
}

// the session screen: the warnings show, with a line for the agent
{
  const sw = { downloadRunning: false, packageManagerRunning: false, agentWorking: true, agentTitles: ["Fix the login bug"] };
  const scope = { SessionWarnings: sw, IslandController: { workUnsaved: false, unsavedLine: "" }, sessionRoot: { failedText: "" },
    Translation: { tr: s => ({ toString: () => s, arg: x => s.replace("%1", x) }) } };
  const at = screen.indexOf("// Warnings, text only");
  const block = inScope(scope, "", `return (${readExpression(screen, screen.indexOf("visible:", at) + 8).expr});`)();
  const shown = () => {
    const lines = [];
    for (let i = screen.indexOf("Warning {", at); i >= 0 && i < screen.indexOf("component BigAction", at); i = screen.indexOf("Warning {", i + 1)) {
      const v = inScope(scope, "", `return (${readExpression(screen, screen.indexOf("visible:", i) + 8).expr});`)();
      if (v) lines.push(String(inScope(scope, "", `return (${readExpression(screen, screen.indexOf("text:", i) + 5).expr});`)()));
    }
    return lines;
  };
  const lines = shown();
  check("the session screen warns while an agent is working, in a line of its own",
    block === true && lines.length === 1 && /agent/i.test(lines[0]), `warnings shown: ${block}, lines ${JSON.stringify(lines)}`);
  check("the line names the conversation", lines[0] === "An agent is still working: Fix the login bug", JSON.stringify(lines[0]));
  sw.agentTitles = ["Fix the login bug", "Tidy the README"];
  const two = shown();
  check("two at once are both named", two[0] === "Agents are still working: Fix the login bug, Tidy the README", JSON.stringify(two[0]));
}

// the update's Restart (the notch and Settings): it stops at the warning instead of restarting
{
  let went = 0, peek = "";
  const root = { guarding: true, restartWarning: "", go: () => went++ };
  const scope = { root, SessionWarnings: { agentWorking: true, agentTitles: ["Fix the login bug"], packageManagerRunning: false, downloadRunning: false },
    IslandController: { workUnsaved: false, request: (n, d) => { peek = d.text; } }, disarmTimer: { restart() {} } };
  const f = qmlFunction(updates, "onChecked");
  inScope(scope, f.params, f.body)();
  check("the update's Restart says an agent is working and waits for a second press",
    went === 0 && root.restartWarning === "An agent is still working: Fix the login bug" && peek === root.restartWarning,
    `restarted ${went} time(s), warning "${root.restartWarning}", notch "${peek}"`);
}

done();
