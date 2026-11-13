// A session stopped by its plan's usage limit (agent-host's live `limited: { resetsAt }`, unix seconds): Praxis's rail
// and header, and the notch, say "Limit reached · back at 14:00" (modules/claude/Limit.js); a host that does not say
// shows nothing new. The files' own code is run under node.
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const limitSrc = (() => { try { return read("modules/claude/Limit.js"); } catch (e) { return null; } })();
const Limit = limitSrc ? new Function(`${limitSrc.replace(/^\.pragma library/m, "")}\nreturn { words, of };`)()
  : { words: () => "", of: () => "" };
const folderSrc = read("modules/claude/FolderModel.qml"), listSrc = read("modules/claude/SessionList.qml");
const convSrc = read("modules/claude/Conversation.qml"), notchSrc = read("services/Claude.qml");

console.log("A session at its usage limit (modules/claude/Limit.js, FolderModel, SessionList, Conversation, services/Claude.qml)");

const at = (day, h, m) => new Date(2026, 10, day, h, m).getTime();
const now = at(13, 11, 20);
{
  const said = [Limit.words(at(13, 14, 0) / 1000, now), Limit.words(at(14, 9, 5) / 1000, now), Limit.words(at(17, 14, 0) / 1000, now),
    Limit.words(at(24, 14, 0) / 1000, now), Limit.words(0, now), Limit.words(at(13, 14, 0), now)];
  const want = ["Limit reached · back at 14:00", "Limit reached · back tomorrow at 09:05", "Limit reached · back on Tuesday at 14:00",
    "Limit reached · back on 24 Nov at 14:00", "Limit reached", "Limit reached · back at 14:00"];
  check("the words: today at its time, tomorrow, a day this week, a later date; no time, none; milliseconds read the same",
    JSON.stringify(said) === JSON.stringify(want), JSON.stringify(said));
  check("a session the host does not call limited, or a host that does not say, has no words",
    Limit.of({ state: "idle" }, now) === "" && Limit.of(null, now) === "" && Limit.of({ limited: {} }, now) === "Limit reached");
}

// the rail's row: the words under the title, in a row as tall as a search hit's
const resets = at(13, 14, 0) / 1000;
{
  const m = /const sessionRow = /.exec(folderSrc);
  const expr = m ? readExpression(folderSrc, m.index + m[0].length).expr : "() => ({})";
  const fm = { deleting: {}, arrivals: {}, titleOf: s => s.prompt, contextWord: () => "", folderOf: () => "/home/a/dev",
    live: { s1: { id: "s1", state: "idle", alive: true, limited: { resetsAt: resets } }, s2: { id: "s2", state: "idle", alive: true } } };
  const make = inScope({ fm, st: {}, pinSet: {}, archivedSet: {}, fk: {}, now, Voice: { age: () => "now" }, Limit }, "", `return (${expr});`)();
  const limited = make({ id: "s1", prompt: "fix the login" }, true), plain = make({ id: "s2", prompt: "tidy up" }, true);
  const twoLines = qmlProperty(listSrc, "twoLines"), base = qmlProperty(listSrc, "base");
  const height = d => {
    const row = { type: d.type, d };
    if (twoLines) row.twoLines = inScope({ row }, "", `return (${twoLines});`)();
    return inScope({ row, rail: { firstFooter: () => false }, part: {} }, "", `return (${base});`)();
  };
  check("the rail's row of a limited session carries the words, and one not limited none",
    limited.limit === "Limit reached · back at 14:00" && !plain.limit, `limited "${limited.limit}", not "${plain.limit}"`);
  check("its row has the second line a search hit has; other rows keep their height",
    height(limited) === 56 && height(plain) === 32 && height({ type: "hit" }) === 56, `limited ${height(limited)}, not ${height(plain)}`);
}

// the header and the notch read the clock themselves: a reset at 14:00 today is "back at 14:00" at any hour of it
const today = new Date(); today.setHours(14, 0, 0, 0);
const resetsToday = today.getTime() / 1000;

// the conversation's header: "~/dev/app · Claude Code · Limit reached · back at 14:00"
{
  const limit = qmlProperty(convSrc, "limit");
  const shown = live => limit ? inScope({ conv: { live }, Limit }, "", `return (${limit});`)() : "";
  const at = convSrc.indexOf('parts.push("waiting for you")');
  const open = convSrc.lastIndexOf("text: {", at) + 6;
  const header = (live, more = {}) => {
    const conv = { shownSession: { id: "s1", cwd: "/home/a/dev/app", tool: "claude", started: now }, agentNames: { claude: "Claude Code" },
      pending: [], busy: false, locked: false, place: p => p.replace("/home/a", "~"), limit: shown(live), ...more };
    return inScope({ conv, Qt: { formatDateTime: () => "13 Nov 2026" } }, "", readExpression(convSrc, open).expr.slice(1, -1))();
  };
  const limited = { state: "idle", limited: { resetsAt: resetsToday } };
  check("the header of a limited session says it after where it ran",
    header(limited) === "~/dev/app · Claude Code · Limit reached · back at 14:00", header(limited));
  check("working or waiting for you still says that, and a session not limited shows its date as before",
    header(limited, { busy: true }).endsWith("· working") && header({ state: "idle" }) === "~/dev/app · Claude Code · 13 Nov 2026",
    `${header(limited, { busy: true })} / ${header({ state: "idle" })}`);
}

// the notch, as the turn ends: the same words in the error tone with a clock, not a done tick
{
  const finished = qmlFunction(notchSrc, "finished"), limitText = qmlFunction(notchSrc, "limitText");
  const end = live => {
    const asked = [];
    const root = { activityId: "", whenOffScreen: (id, off) => off(), doneText: id => "fix the login done", titleOf: () => "fix the login" };
    const scope = { root, host: { live: { s1: live } }, Notifications: { silent: false }, Limit, Qt: { formatTime: () => "14:00", formatDate: () => "" },
      IslandController: { activityRunning: false, request: (name, data) => asked.push({ name, ...data }), endActivity() {} } };
    root.limitText = inScope(scope, limitText.params, limitText.body);
    inScope(scope, finished.params, finished.body)("s1");
    return asked[0] ?? {};
  };
  const hit = end({ state: "idle", limited: { resetsAt: resetsToday } }), fine = end({ state: "idle" });
  check("the notch says the limit's words with a clock in the error tone",
    hit.name === "activityFail" && hit.text === "Limit reached · back at 14:00" && hit.icon === "schedule" && hit.tone === "error",
    `${hit.name} "${hit.text}" ${hit.icon}`);
  check("a turn that ended well still peeks done with its check", fine.name === "activityDone" && fine.icon === "check_circle");
}
done();
