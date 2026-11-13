// Praxis's window (claude.qml): what it opens on, what it asks the CLI, and what the desktop hands it. The window's own
// functions and handlers run under node with a pretend host and conversation.
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { spawnSync } from "child_process";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const appSrc = read("claude.qml");
const fn = (src, name) => { const f = qmlFunction(src, name); return scope => inScope(scope, f.params, f.body); };

console.log("Praxis's window (claude.qml)");

// later-praxis-1 [0] a session opened from the notch or a link that the rail leaves out (a /tmp run, a helper's) was
// written to claude-last.txt, but the restore looked for it in the rail's list only: Praxis reopened on nothing
{
  const sessions = [
    { id: "a1", cwd: "/home/a/proj", title: "Fix the login", entry: "cli" },
    { id: "t1", cwd: "/tmp/run-3", title: "A bench run", entry: "cli" },
    { id: "h1", cwd: "/home/a/proj", title: "Helper", entry: "sdk-cli" },
  ];
  const reopen = (last, stage = "") => {
    const root = { history: [], allHistory: [], loaded: false, restored: false, selected: null, wantedId: "", stage, home: "/home/a" };
    const host = { request: (op, cb) => cb({ ev: "history", sessions }) };
    const scope = { root, host, lastFile: { text: () => last } };
    for (const name of ["worthShowing", "scratch", "onStage", "refresh"]) root[name] = fn(appSrc, name)(scope);
    root.refresh();
    return root.selected?.id ?? "";
  };
  check("the last session comes back when the rail shows it, and when it is one the rail leaves out",
    reopen("a1") === "a1" && reopen("t1") === "t1" && reopen("h1") === "h1", `listed ${reopen("a1")}, /tmp run ${reopen("t1") || "nothing"}, helper ${reopen("h1") || "nothing"}`);
  check("not one off a demo's stage, nor one the host no longer has", reopen("t1", "/home/a/demo") === "" && reopen("gone") === "");
}

// later-praxis-1 [1] `claude auth status --json` exits 1 when signed out (Claude Code 2.1.322: {"loggedIn": false, ...}),
// and the `|| echo '{}'` after it made two JSON documents: the parse failed quietly and the sign-in notice never came
{
  const at = appSrc.indexOf("id: claudeCheck");
  const cmd = inScope({}, "", `return (${readExpression(appSrc, appSrc.indexOf("command:", at) + "command:".length).expr});`)();
  const open = appSrc.indexOf("onStreamFinished: {", at) + "onStreamFinished: ".length;
  const finished = appSrc.slice(open + 1, matchBrace(appSrc, open)).replace(/\bthis\.text\b/g, "__text");
  const tmp = mkdtempSync(join(tmpdir(), "praxis-auth-"));
  // a claude that answers as the real one does: its JSON on stdout, and its exit code
  let n = 0;
  const need = (json, code) => {
    const bin = join(tmp, `bin-${n++}`);
    mkdirSync(bin);
    if (json !== null) {
      writeFileSync(join(bin, "claude"), `#!/bin/sh\n[ "$1 $2 $3" = "auth status --json" ] || exit 9\nprintf '%s\\n' '${json}'\nexit ${code}\n`);
      chmodSync(join(bin, "claude"), 0o755);
    }
    const out = spawnSync("/bin/bash", cmd.slice(1), { env: { PATH: bin, HOME: tmp }, encoding: "utf8" }).stdout;
    const root = { claudeNeed: "unset" };
    inScope({ root, __text: out }, "", finished)();
    return root.claudeNeed;
  };
  const out = need('{\n  "loggedIn": false,\n  "authMethod": "none"\n}', 1), signedIn = need('{"loggedIn": true}', 0);
  const silent = need("", 1), missing = need(null, 0);
  check("a signed-out Claude Code is noticed; signed in, crashed with nothing said, or not installed read as before",
    out === "signedOut" && signedIn === "" && silent === "" && missing === "missing",
    `signed out "${out}", signed in "${signedIn}", nothing said "${silent}", not installed "${missing}"`);
  rmSync(tmp, { recursive: true });
}

// later-praxis-1 [2] "Hand to Claude" from Files or a page while the box held a draft for that folder's new session:
// prefill() set the box's text, and the draft was gone
{
  const convSrc = read("modules/claude/Conversation.qml"), boxSrc = read("modules/claude/Composer.qml");
  const hand = qmlFunction(appSrc, "handoff"), changed = /\bonSessionChanged:\s*\{/.exec(convSrc);
  const onSession = readExpression(convSrc, changed.index + changed[0].length - 1).expr.slice(1, -1);
  // the box with its own setText, addText and setDraft; the conversation with its prefill and its session handler
  const handOff = (open, drafts) => {
    const input = { text: open.text, cursorPosition: 0, forceActiveFocus() {} };
    const composer = { aside: false, attachments: [] };
    Object.defineProperty(composer, "text", { get: () => input.text });
    for (const f of ["setText", "addText", "setDraft"]) composer[f] = fn(boxSrc, f)({ composer, input });
    const conv = { session: open.session, loadedKey: open.key, drafts, queued: [], findOnLoad: "", shownSession: null,
      closeFind() {}, load() {}, focusComposer() {} };
    conv.prefill = fn(convSrc, "prefill")({ conv, composer });
    const root = { visible: false, home: "/home/a" };
    Object.defineProperty(root, "selected", { set: s => { conv.session = s; inScope({ conv, composer }, "", onSession)(); }, get: () => conv.session });
    inScope({ root, conv }, hand.params.replace(/:\s*\w+/g, ""), hand.body)("/home/a/proj", "Page: Invoices https://example.com/invoices");
    return input.text;
  };
  const here = handOff({ session: { fresh: true, id: "", cwd: "/home/a/proj" }, key: "fresh:/home/a/proj", text: "rename the export button and" }, {});
  const away = handOff({ session: { id: "s9", cwd: "/home/a/other" }, key: "s9", text: "" },
    { "fresh:/home/a/proj": { text: "rename the export button and", files: [] } });
  const empty = handOff({ session: { id: "s9", cwd: "/home/a/other" }, key: "s9", text: "" }, {});
  const both = t => t.startsWith("rename the export button and") && t.endsWith("Page: Invoices https://example.com/invoices");
  check("a hand-off keeps the draft of that folder's new session, open or kept, and goes after it; an empty box takes it as it is",
    both(here) && both(away) && empty === "Page: Invoices https://example.com/invoices",
    `open: ${JSON.stringify(here)}, kept: ${JSON.stringify(away)}, empty: ${JSON.stringify(empty)}`);
}

done();
