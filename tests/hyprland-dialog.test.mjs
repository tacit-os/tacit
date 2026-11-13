// Hyprland's "Application Not Responding" dialog brought to the notch (scripts/activity/hyprland-dialog), run under bash
// with a pretend hyprctl and a pretend shell (qs) that shows the prompt and answers Wait on its fifo: which process the
// prompt names for Close it, whose kill follows Hyprland's own (IslandController.answerNotAnswering, run under node);
// and the prompt offered again while it waits, as a reload or restart of the shell loses it, with the shell's own
// showNotAnswering() under node taking those offers. No display is given, so the real dialog could not open here.
import { spawn, spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== the process the not-answering prompt names (hyprland-dialog)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-anr-"));
try {
  const bin = join(tmp, "bin"), asked = join(tmp, "asked");
  mkdirSync(bin); mkdirSync(join(tmp, "run"));
  writeFileSync(join(bin, "hyprctl"), '#!/bin/sh\n[ "$1" = clients ] && printf %s "$CLIENTS"\n', { mode: 0o755 });
  writeFileSync(join(bin, "qs"), `#!/bin/sh
[ "$6" = notAnswering ] || exit 0
printf '%s\\n' "$7" >> "${asked}"
f=$(printf %s "$7" | jq -r .fifo)
[ -n "$NOANSWER" ] || ( sleep 0.3; printf 'Wait\\n' > "$f" ) >/dev/null 2>&1 &
echo shown
`, { mode: 0o755 });
  const args = text => [join(tree, "scripts/activity/hyprland-dialog"), "--title", "Application Not Responding", "--text", text, "--buttons", "Terminate;Wait"];
  const env = (clients, more = {}) => ({ PATH: `${bin}:${process.env.PATH}`, HOME: tmp, XDG_RUNTIME_DIR: join(tmp, "run"), TACIT_SHELL: "/s",
    CLIENTS: JSON.stringify(clients), ...more });
  const prompt = (text, clients) => {
    rmSync(asked, { force: true });
    const r = spawnSync("bash", args(text), { encoding: "utf8", timeout: 10000, env: env(clients) });
    let req = null;
    try { req = JSON.parse(readFileSync(asked, "utf8").split("\n")[0]); } catch {}
    return { answer: r.stdout.trim(), req };
  };
  const w = (pid, cls, title) => ({ pid, class: cls, title, address: `0x${pid}` });

  const twins = prompt("An application foot - foot is not responding.", [w(101, "foot", "foot"), w(202, "foot", "foot"), w(303, "firefox", "News")]);
  check("two terminals of one class and title in two processes: no process is named", twins.req?.pid === 0, JSON.stringify(twins.req));
  check("and Hyprland still hears the answer", twins.answer === "Wait", `heard "${twins.answer}"`);
  const one = prompt("An application ~/dev - foot is not responding.", [w(101, "foot", "~/notes"), w(202, "foot", "~/dev")]);
  check("one window fits: its process", one.req?.pid === 202 && one.req?.title === "~/dev", JSON.stringify(one.req));
  const browser = prompt("An application News - firefox is not responding.", [w(303, "firefox", "News"), w(303, "firefox", "News")]);
  check("two windows of one process: that process", browser.req?.pid === 303, JSON.stringify(browser.req));
  const classOnly = prompt("An application Unknown - krita is not responding.", [w(404, "krita", "a.kra"), w(505, "krita", "b.kra")]);
  check("only the class fits, in two processes: no process is named", classOnly.req?.pid === 0, JSON.stringify(classOnly.req));

  // a prompt nobody answers for a while: the shell may have been reloaded meanwhile
  rmSync(asked, { force: true });
  const started = Date.now();
  const p = spawn("bash", args("An application Notes - org.example.Notes is not responding."),
    { env: env([w(606, "org.example.Notes", "Notes")], { NOANSWER: "1" }), stdio: ["ignore", "pipe", "ignore"] });
  let out = "";
  p.stdout.on("data", d => out += d);
  const ended = new Promise(r => p.on("exit", () => r(Date.now())));
  await new Promise(r => setTimeout(r, 6500));
  const offers = (() => { try { return readFileSync(asked, "utf8").split("\n").filter(Boolean).map(l => JSON.parse(l)); } catch { return []; } })();
  check("unanswered, the prompt is offered again", offers.length >= 2 && offers.every(o => o.id === offers[0].id), `offered ${offers.length} times`);
  check("with the time the app stopped", offers.length > 0 && Math.abs(offers[0].since - started) < 2000 && offers.every(o => o.since === offers[0].since),
    JSON.stringify(offers.map(o => o.since)));
  const answeredAt = Date.now();
  if (offers[0]) writeFileSync(offers[0].fifo, "Wait\n");
  const gone = await Promise.race([ended, new Promise(r => setTimeout(() => r(0), 3000))]);
  check("an answer goes to Hyprland at once", gone > 0 && gone - answeredAt < 1500 && out.trim() === "Wait",
    gone ? `after ${gone - answeredAt} ms, "${out.trim()}"` : "it did not end");
  if (!gone) p.kill("SIGKILL");
} finally {
  rmSync(tmp, { recursive: true, force: true });
}

// the shell taking those offers: one just started shows it as it was, one showing it or that had it answered is unchanged
{
  const src = read("services/IslandController.qml");
  const ran = [], shown = [];
  let closes = 0;
  const root = { enabled: true, suppressed: false, notAnswering: null, notAnsweringFor: 0, notAnsweringDone: "",
    closeRequested: () => closes++, activate: name => shown.push(name), cancelState() {} };
  const scope = { root, DesktopEntries: { heuristicLookup: () => null }, Quickshell: { execDetached: c => ran.push(c) } };
  for (const name of ["showNotAnswering", "answerNotAnswering", "clearNotAnswering"]) {
    const f = qmlFunction(src, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  const offer = () => ({ id: "4242", cls: "org.example.Notes", title: "Notes", pid: 606, fifo: "/run/user/1000/tacit-anr-4242",
    buttons: ["Terminate", "Wait"], since: Date.now() - 120000 });
  root.showNotAnswering(offer());
  check("a shell just started shows the prompt with how long the app has been stopped", shown.length === 1 && Date.now() - root.notAnswering?.since >= 119000,
    `shown ${shown.length}, stopped ${Math.round((Date.now() - root.notAnswering?.since) / 1000)} s ago`);
  const again = root.showNotAnswering(offer());
  check("offered again while it shows: nothing changes", again === true && shown.length === 1 && closes === 1 && ran.length === 0,
    `shown ${shown.length} times, sheets closed ${closes} times`);
  root.answerNotAnswering("wait");
  root.showNotAnswering(offer());
  check("offered again after it was answered: it does not come back", root.notAnswering === null && shown.length === 1, `shown ${shown.length} times`);
}

// Close it on a prompt that names no process: Hyprland's Terminate goes out, and no kill of the shell's own
{
  const src = read("services/IslandController.qml");
  const ran = [];
  const root = { notAnswering: { id: "77", pid: 0, fifo: "/run/user/1000/tacit-anr-77", buttons: ["Terminate", "Wait"] }, clearNotAnswering() {} };
  const f = qmlFunction(src, "answerNotAnswering");
  inScope({ root, Quickshell: { execDetached: c => ran.push(c) } }, f.params, f.body)("close");
  check("Close it with no process named answers Terminate and kills nothing itself",
    ran.length === 1 && ran[0].at(-1) === "Terminate" && !ran.some(c => /kill/.test(c.join(" "))), JSON.stringify(ran));
}
done();
