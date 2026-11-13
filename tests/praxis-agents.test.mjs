// The session's agents (modules/claude/AgentsPane.qml and its pages, AgentsGroup.qml, AgentRow.qml): what a page
// opens on, how a row reads, where a finding's file is. The files' own functions and bindings run under node.
import { inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const fnIn = (src, name, scope) => { const f = qmlFunction(src, name); return f ? inScope(scope, f.params, f.body) : () => {}; };

console.log("The session's agents (modules/claude/AgentsPane.qml, AgentPage.qml, AgentsListPage.qml, AgentsGroup.qml, AgentRow.qml)");

// later-praxis-1 [6] an agent opened while it ran (followed to its newest step), left and reopened once it had finished:
// the kept follow sent the page to the end of its activity, away from its report at the top
{
  const pageSrc = read("modules/claude/AgentPage.qml");
  const reopen = (entry, state) => {
    const later = [];
    let ended = 0;
    const ap = { entry, a: state ? { state } : null, running: state === "running", tools: [], seen: 0, unseen: 0, wantY: -1,
      toEnd() { ended++; }, settle() {} };
    const scope = { ap, jumpLater: { start() {} }, Qt: { callLater: f => later.push(f) } };
    ap.begin = fnIn(pageSrc, "begin", scope);
    ap.restore = fnIn(pageSrc, "restore", scope);
    ap.begin();
    ap.restore();
    later.splice(0).forEach(f => f());
    return { toEnd: ended > 0, y: ap.wantY };
  };
  const finished = reopen({ f: { follow: true }, y: 1840 }, "done"), still = reopen({ f: { follow: true }, y: 1840 }, "running");
  const readBefore = reopen({ f: { follow: false }, y: 620 }, "done"), firstTime = reopen({ f: {}, y: 0 }, "done");
  check("followed while it ran and finished since, it opens at the top on its report; still running, at its newest step",
    !finished.toEnd && finished.y === 0 && still.toEnd, `finished: ${finished.toEnd ? "to the end" : `at ${finished.y}`}, running: ${still.toEnd ? "to the end" : `at ${still.y}`}`);
  check("a place you scrolled to yourself is kept, and a first look at a finished one starts at the top",
    !readBefore.toEnd && readBefore.y === 620 && !firstTime.toEnd && firstTime.y === 0, `${JSON.stringify(readBefore)}, ${JSON.stringify(firstTime)}`);
}

// later-praxis-1 [7] a structured report's home folder as ~ was a split on home + "/" anywhere in the text, so with
// HOME=/home/a a line naming /backup/home/a/notes.txt read /backup~/notes.txt, a path that does not exist
{
  const pageSrc = read("modules/claude/AgentPage.qml");
  const report = { summary: "Copied it; see /backup/home/a/notes.txt and /home/a/proj/x.md", files: ["/home/a/proj/a.qml", "/srv/home/a/b"] };
  const blocks = home => {
    const ap = { detail: { kind: "json", report: JSON.stringify(report) }, a: { state: "done" }, textBlocks: t => [{ code: false, content: t }] };
    ap.itemOf = fnIn(pageSrc, "itemOf", { ap });
    return inScope({ ap, Quickshell: { env: () => home } }, "", qmlProperty(pageSrc, "reportBlocks").slice(1, -1))().filter(b => b.content).map(b => b.content);
  };
  const shown = blocks("/home/a"), none = blocks("");
  check("home reads ~ where a path starts, and not inside another path",
    JSON.stringify(shown) === JSON.stringify(["Copied it; see /backup/home/a/notes.txt and ~/proj/x.md", "- ~/proj/a.qml\n- /srv/home/a/b"]), JSON.stringify(shown));
  check("with no HOME the text is as written", JSON.stringify(none) === JSON.stringify([report.summary, "- /home/a/proj/a.qml\n- /srv/home/a/b"]), JSON.stringify(none));
}

// later-praxis-1 [8] an Agent call the host has no record of ("ended" since 1.2.14, or done): no end time, so its row
// read "0s" beside the stop mark, as if the agent had run for no time
{
  const rowSrc = read("modules/claude/AgentRow.qml");
  const Words = new Function(`${read("modules/claude/ActivityWords.js")}\nreturn { span };`)();
  const span = (status, started, ended, now = 0) => inScope({ row: { status, started, ended, now, running: status === "running" }, Words }, "",
    `return (${qmlProperty(rowSrc, "spanText")});`)();
  const unrecorded = [span("ended", 1000, 0), span("done", 1000, 0)], took = span("done", 1000, 126000), runs = span("running", 1000, 0, 61000);
  check("a call with no recorded end shows no time; one that has an end, or still runs, shows how long",
    JSON.stringify(unrecorded) === '["",""]' && took === "2m 5s" && runs === "1m 0s", `unrecorded ${JSON.stringify(unrecorded)}, took "${took}", running "${runs}"`);
}

// later-praxis-1 [10] the 30 s a call the host has not read yet stands in as running were counted on the window's clock,
// which ticks only while something runs: Praxis open since 09:00, an Agent or Workflow call at 10:20 that the host never
// records, and once the turn was over the call read "running" for good (now - ts was minus 80 minutes)
{
  const T0 = Date.UTC(2026, 10, 13, 9, 0), T1 = Date.UTC(2026, 10, 13, 10, 20);
  // the file's Timers, as { running, onTriggered } expressions
  const timers = src => [...src.matchAll(/\bTimer\s*\{/g)].map(m => src.slice(m.index, matchBrace(src, src.indexOf("{", m.index)) + 1))
    .map(t => Object.fromEntries(["running", "onTriggered"].map(k => { const at = t.search(new RegExp(`\\b${k}:`)); return [k, at < 0 ? "" : readExpression(t, at + k.length + 1).expr]; })));
  const later = (src, scope, after) => {
    const at = T1 + after, ran = [];
    for (const t of timers(src)) {
      const env = Object.assign({}, scope, { Date: { now: () => at } });
      // a timer that runs in the grace ticks through it (each second, as the Timer would, here once at its end)
      if (t.running && t.onTriggered && inScope(Object.assign({}, scope, { Date: { now: () => T1 } }), "", `return (${t.running});`)()) {
        inScope(env, "", t.onTriggered)();
        ran.push(inScope(env, "", `return (${t.running});`)());
      }
    }
    return ran;
  };
  const groupSrc = read("modules/claude/AgentsGroup.qml"), cardSrc = read("modules/claude/WorkflowCard.qml");
  const made = (src, own) => { const e = qmlProperty(src, "graceNow"); if (e) own.graceNow = inScope({ Date: { now: () => T1 } }, "", `return (${e});`)(); return own; };

  const call = { id: "c1", tool: "Agent", ts: T1, summary: "Review the diff" };
  const group = made(groupSrc, { calls: [call], info: { agents: [] }, pending: false, now: T0 });
  const gscope = { group };
  for (const name of ["inGrace"]) { const e = qmlProperty(groupSrc, name); if (e) Object.defineProperty(group, name, { get: () => inScope(gscope, "", `return (${e});`)() }); }
  group.statusOf = fnIn(groupSrc, "statusOf", gscope);
  const inTheGrace = group.statusOf(call, null);
  const stillTicking = later(groupSrc, gscope, 31000);
  const agentAfter = group.statusOf(call, null);

  const card = made(cardSrc, { item: { id: "w1", tool: "Workflow", ts: T1 }, run: null, pending: false, now: T0 });
  const cscope = { card };
  const status = () => inScope(cscope, "", `const waiting = (${qmlProperty(cardSrc, "waiting")}); return (${qmlProperty(cardSrc, "status").replace(/card\.waiting/g, "waiting")});`)();
  const cardIn = status();
  later(cardSrc, cscope, 31000);
  const cardAfter = status();
  check("an Agent or Workflow call the host never records stands in as running for 30 s, then reads ended, whatever the window's clock",
    inTheGrace === "running" && agentAfter === "ended" && cardIn === "running" && cardAfter === "ended",
    `agent ${inTheGrace} then ${agentAfter}, workflow ${cardIn} then ${cardAfter}`);
  check("and its clock stops once the 30 s are over", stillTicking.length > 0 && stillTicking.every(r => r === false), JSON.stringify(stillTicking));
}

// later-praxis-1 [11] on the Agents list (its order kept while you look), a sub-agent that started while you looked showed
// under Running only as "fresh", and once it finished it was in neither the kept order nor fresh: its row went until you
// left and came back; one that started and ended between two polls never showed at all
{
  const src = read("modules/claude/AgentsListPage.qml");
  const p = { runs: [], shells: [], tree: { roots: [], busy: {} }, info: { agents: [] }, loaded: true,
    findAgent: (info, id) => (info?.agents ?? []).find(a => a.agent === id) ?? null };
  const lp = { p, pane: p, entry: { k: "list", f: {} }, order: null, came: "", cursorKey: "" };
  const scope = { lp };
  for (const f of ["orderNow", "take", "begin", "stateOf"]) lp[f] = fnIn(src, f, scope);
  for (const name of ["fresh", "settled", "doneShown", "navList"]) {
    const e = qmlProperty(src, name);
    Object.defineProperty(lp, name, { get: () => inScope(scope, "", e.startsWith("{") ? e.slice(1, -1) : `return (${e});`)() });
  }
  const m = /\bonFreshChanged:\s*\{/.exec(src);
  const freshChanged = m ? inScope(scope, "", readExpression(src, m.index + m[0].length - 1).expr.slice(1, -1)) : () => {};
  // the host's next agents reply: the page's bindings see it, and fresh's change handler runs
  const poll = agents => { p.info = { agents }; p.tree = { roots: agents, busy: Object.fromEntries(agents.filter(a => a.state === "running").map(a => [a.agent, true])) }; freshChanged(); };
  lp.begin();
  poll([{ agent: "a1", state: "running", started: 10 }]);
  const whileRunning = lp.navList.slice();
  poll([{ agent: "a1", state: "done", started: 10, ended: 20 }]);
  const afterDone = lp.navList.slice(), settled = lp.settled;
  poll([{ agent: "a1", state: "done", started: 10, ended: 20 }, { agent: "a2", state: "done", started: 21, ended: 25 }]);
  const between = lp.navList.slice();
  check("a sub-agent that starts while you look and then finishes keeps its row, counted as finished while you were here",
    whileRunning.includes("agent:a1") && afterDone.includes("agent:a1") && settled === 1,
    `running ${JSON.stringify(whileRunning)}, finished ${JSON.stringify(afterDone)}, ${settled} counted as finished here`);
  check("one that started and ended between two looks shows too", between.includes("agent:a2") && between.indexOf("agent:a1") === afterDone.indexOf("agent:a1"),
    JSON.stringify(between));
}

// later-praxis-1 [12] on the Agents list Down moved the keys' highlight below the rows in view and the list stayed put,
// so Enter opened a row you could not see (the Results and Finding pages reveal theirs)
{
  const src = read("modules/claude/AgentsListPage.qml"), page = read("modules/claude/PanelPage.qml");
  const entry = src.slice(src.indexOf("component Entry")), at = entry.indexOf("PanelRow {");
  const row = entry.slice(at, matchBrace(entry, entry.indexOf("{", at)) + 1);
  const m = /\bonCursorChanged:\s*/.exec(row);
  const moved = cursor => {
    const shown = [], en = { k: "agent:a7" };
    if (m) { const e = readExpression(row, m.index + m[0].length).expr; inScope({ cursor, en, lp: { reveal: x => shown.push(x) } }, "", /^if\b/.test(e) ? `${e};` : `return (${e});`)(); }
    return shown.length === 1 && shown[0] === en ? "revealed" : shown.length ? "something else" : "nothing";
  };
  check("the row the keys move to is scrolled into view, and only that one", moved(true) === "revealed" && moved(false) === "nothing" && !!qmlFunction(page, "reveal"),
    `the keys' row: ${moved(true)}, another: ${moved(false)}`);
}

// later-praxis-1 [13] a finding's file with a line range, as agent-host's own file_of() takes it ("src/Foo.qml:324-330"),
// was placed as a file named "Foo.qml:324-330": the Where row linked to it and Files said "This file is gone"
{
  const pane = { results: { changes: [{ path: "/home/a/proj/src/Bar.qml" }] }, cwd: "/home/a/proj" };
  const fileOf = fnIn(read("modules/claude/AgentsPane.qml"), "fileOf", { pane });
  const placed = raw => { const r = fileOf(raw, 0); return `${r.path}:${r.line}`; };
  const got = ["src/Foo.qml:324-330", "Bar.qml:12-20", "src/Foo.qml:14", "src/Foo.qml:14:3", "/abs/F.qml"].map(placed);
  check("a line range places the file at the range's first line; single lines and bare paths as before",
    JSON.stringify(got) === JSON.stringify(["/home/a/proj/src/Foo.qml:324", "/home/a/proj/src/Bar.qml:12", "/home/a/proj/src/Foo.qml:14", "/home/a/proj/src/Foo.qml:14", "/abs/F.qml:0"]),
    JSON.stringify(got));
}

// later-praxis-1 [14] the Results page took a reply only when its counts differed, so one that marked a finding's file as
// changed since (its "may be fixed" fold), gave a verdict, or new line counts for a change was dropped: the page went on
// saying "6 need a look" until the session was switched
{
  const src = read("modules/claude/AgentsPane.qml");
  let reply = null;
  const pane = { canResults: true, sessionId: "s1", resultsBusy: false, root: "results", visible: true, results: null, resultsSig: "", resultsError: "",
    host: { request: (op, cb) => cb(JSON.parse(JSON.stringify(reply))) } };
  const scope = { pane };
  pane.sigOfResults = fnIn(src, "sigOfResults", scope);
  pane.loadResults = fnIn(src, "loadResults", scope);
  const answer = (tag, finding, change) => {
    reply = { ev: "results", tag, findings: [Object.assign({ title: "Weather never loads", need: true, level: "high", status: "open", sources: [{ source: "a1" }] }, finding)],
      reports: [{ kind: "read", source: "a1" }], failures: [], pictures: [], changes: [Object.assign({ path: "/p/Weather.qml", add: 3, del: 1, by: [] }, change)],
      counts: { sources: 2, running: 0, done: 2, failed: 0, stopped: 0, reports: 1 }, unread: { count: 0, cost: 0 }, reading: 0, error: null };
    pane.loadResults();
    return pane.results;
  };
  const first = answer(1, {}, {}), same = answer(2, {}, {});
  const fixed = answer(3, { changedSince: 1763030000 }, {}), counted = answer(4, { changedSince: 1763030000 }, { add: 9 });
  check("a reply that marks a finding's file changed since, or gives a change new line counts, is taken",
    fixed !== same && fixed.findings[0].changedSince === 1763030000 && counted.changes[0].add === 9,
    `changedSince ${pane.results.findings[0].changedSince ?? "not taken"}, add ${pane.results.changes[0].add}`);
  check("one that says nothing new keeps the page as it is", same === first);
}

done();
