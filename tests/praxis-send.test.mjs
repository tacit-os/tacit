// What Praxis sends, and what it keeps when it cannot send yet (claude.qml, modules/claude/Conversation.qml and the
// box and panels it feeds). The handlers' own code is run under node with a pretend conversation and host.
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const appSrc = read("claude.qml"), convSrc = read("modules/claude/Conversation.qml"), boxSrc = read("modules/claude/Composer.qml");
const reviewSrc = read("modules/claude/ChangesPanel.qml");
// "<name>: <expression>" in the file (a handler or a binding), run in scope; an absent one does nothing
function handler(src, name, scope) {
  const m = new RegExp(`\\b${name}:\\s*`).exec(src);
  if (!m) return () => {};
  const expr = readExpression(src, m.index + m[0].length).expr;
  if (expr.startsWith("{")) return inScope(scope, "", expr.slice(1, -1));
  return /^if\b/.test(expr) ? inScope(scope, "", `${expr};`) : inScope(scope, "", `return (${expr});`);
}

console.log("What Praxis sends and keeps (claude.qml, modules/claude/Conversation.qml)");

// [0] closing the window with a message queued behind a running turn quit the app, and the queue went with it
{
  const hasDraft = qmlProperty(convSrc, "hasDraft");
  const draft = conv => inScope({ composer: { text: "", attachments: [] }, conv: { drafts: {}, queued: [], sendingNow: false, ...conv } }, "",
    `return (${hasDraft});`)();
  const queued = draft({ queued: [{ text: "and run the tests", images: [], files: [], shown: true }] });
  const onItsWay = draft({ sendingNow: true });
  check("a message queued behind the turn, or still on its way, counts as not sent", queued && onItsWay && !draft({}),
    `queued ${queued}, on its way ${onItsWay}, nothing ${draft({})}`);

  // the X with that message: the window hides and the instance stays; once it has gone, the instance ends
  const app = (hasDraft, visible) => {
    const s = { conv: { hasDraft }, root: { visible }, quits: 0, later: [] };
    s.Qt = { quit: () => s.quits++, callLater: f => s.later.push(f) };
    return s;
  };
  const closing = app(true, true);
  (handler(appSrc, "onClosing", closing)() ?? (() => {}))({});
  const changed = qmlFunction(appSrc, "onHasDraftChanged");
  const gone = s => { if (changed) inScope(s, changed.params, changed.body)(); s.later.splice(0).forEach(f => f()); return s.quits; };
  const sent = app(false, false), shown = app(false, true);
  check("closed with it queued, the app stays; hidden, it ends once the message has gone, and not while shown",
    closing.quits === 0 && gone(sent) === 1 && gone(shown) === 0,
    `quit on close ${closing.quits}, once sent while hidden ${sent.quits}, while shown ${shown.quits}`);
  // the queue hands its head to send(), which marks it on its way in the same call: no quit in between
  const between = app(false, false);
  if (changed) inScope(between, changed.params, changed.body)();
  between.conv.hasDraft = true;
  between.later.splice(0).forEach(f => f());
  check("the moment between the queue giving up its head and send() taking it does not end the app", between.quits === 0);
}

// [5] Aside left on: Ctrl+N gives a new session, whose box hides the Aside chip but still sent Enter as an aside, which a
// new session cannot take, and the text was cleared; another session's next message went out as an aside too
{
  const submit = qmlFunction(boxSrc, "submit");
  const enter = (aside, canAside) => {
    const said = { sent: [], asides: [] };
    const composer = { aside: true, canAside: true, locked: false, attachments: [], needsStep: false, suggest: {},
      isImage: () => false, asideAsked: q => said.asides.push(q), sendFn: t => (said.sent.push(t), true) };
    const input = { text: "fix the login bug" };
    composer.canAside = canAside;                        // the session changes under the box
    handler(boxSrc, "onCanAsideChanged", { composer })();
    if (aside === "switch") {
      const changed = /\bonSessionChanged:\s*\{/.exec(convSrc);
      const body = changed ? readExpression(convSrc, changed.index + changed[0].length - 1).expr.slice(1, -1) : "";
      const conv = { session: { id: "s2", cwd: "/home/a" }, loadedKey: "s1", shownSession: null, drafts: {}, queued: [], closeFind() {}, load() {} };
      inScope({ conv, composer: Object.assign(composer, { text: "", setDraft() {} }) }, "", body)();
    }
    inScope({ composer, input }, submit.params, submit.body)();
    return { ...said, left: input.text, on: composer.aside };
  };
  const fresh = enter(true, false);
  check("a new session's box is not left asking aside: Enter sends the message",
    JSON.stringify(fresh.sent) === '["fix the login bug"]' && !fresh.asides.length,
    `sent ${JSON.stringify(fresh.sent)}, asked aside ${JSON.stringify(fresh.asides)}, box "${fresh.left}"`);
  const other = enter("switch", true);
  check("opening another session leaves aside too", !other.on && JSON.stringify(other.sent) === '["fix the login bug"]',
    `aside ${other.on}, sent ${JSON.stringify(other.sent)}, asked aside ${JSON.stringify(other.asides)}`);
  const same = enter(true, true);
  check("in the same session it stays on, for the next question of the thread", same.on && same.asides.length === 1);
}

// [4] Review's comments sent while the conversation could not take a message (reconnecting, still being read): the
// panel said "Sent 6 comments to Claude." and dropped them, while the conversation said "Nothing was sent"
{
  const sendComments = qmlFunction(reviewSrc, "sendComments");
  // what claude.qml gives the panel to send with (SidePanel passes it on), else nothing
  const m = /\bsendFn:\s*/.exec(appSrc.slice(appSrc.indexOf("SidePanel {")));
  const wired = m ? readExpression(appSrc, appSrc.indexOf("SidePanel {") + m.index + m[0].length).expr : "";
  const press = accepts => {
    const sent = [];
    const conv = { send: t => (sent.push(t), accepts), agentName: "Codex" };
    const panel = { locked: false, agentName: "Codex", sentNote: "", sendRequested: t => conv.send(t),
      comments: [{ path: "src/app.ts", line: 12, text: "this can be null", quote: "" }, { path: "src/app.ts", line: 40, text: "name it", quote: "" }] };
    if (wired) panel.sendFn = inScope({ conv }, "", `return (${wired});`)();
    inScope({ panel, sentNoteFade: { restart() {} }, Quickshell: {} }, sendComments.params, sendComments.body)();
    return { sent: sent.length, kept: panel.comments.length, note: panel.sentNote };
  };
  const refused = press(false), taken = press(true);
  check("comments the conversation refuses stay in the panel, which says they were not sent",
    refused.sent === 1 && refused.kept === 2 && !/^Sent/.test(refused.note), `kept ${refused.kept}, the panel said "${refused.note}"`);
  check("comments it takes are cleared, and the panel names the session's agent",
    taken.kept === 0 && taken.note === "Sent 2 comments to Codex.", `kept ${taken.kept}, "${taken.note}"`);
}

// [2] a hit under "In transcripts" opened at the end of the conversation with nothing marked: the words were searched
// for again by hand
{
  const fn = (name, test = () => true) => [0, 1, 2].map(n => qmlFunction(convSrc, name, n)).find(f => f && test(f));
  const m = /\bonChosen:\s*/.exec(appSrc);
  const chosenExpr = m ? readExpression(appSrc, m.index + m[0].length).expr : "s => {}";
  const choose = session => {
    const asked = [];
    const conv = { findWhenRead: q => asked.push(q) };
    inScope({ root: { choose() {} }, conv, rail: { query: " invoice number " } }, "", `return (${chosenExpr});`)()(session);
    return asked;
  };
  const hit = choose({ id: "s1", snippet: "…the invoice number is on the second page…" }), row = choose({ id: "s2" });
  check("choosing a transcript hit hands its words to the conversation; choosing a session row does not",
    JSON.stringify(hit) === '["invoice number"]' && !row.length, `a hit gave ${JSON.stringify(hit)}, a row ${JSON.stringify(row)}`);

  // the conversation it opens: read, then the words found and marked, the find bar open on them
  const [load, whenRead, quietly] = [fn("load"), fn("findWhenRead"), fn("findQuietly")];
  let reply = null;
  const steps = [];
  const conv = { session: { id: "s1", cwd: "/home/a", fresh: false }, starting: "", watching: "", queued: [], loadGen: 0, live: null,
    pendingUser: "", findOnLoad: "", finding: false, shownSession: null,
    host: { live: {}, request(op, cb) { if (op.op === "transcript") reply = cb; } },
    testLog() {}, emptyReplay: () => ({}), loadChanges() {}, swapIn() { conv.shownSession = conv.session; }, applyQueue: () => [], applyCut() {},
    modeOf: () => "auto", findStep: n => steps.push(n) };
  const findField = { text: "" };
  const timer = { restart() {}, stop() {} };
  const scope = { conv, findField, composer: { dismiss() {} }, slowRead: timer, loadTimeout: timer, errorFade: timer };
  if (load && whenRead && quietly) {
    for (const [name, f] of [["load", load], ["findWhenRead", whenRead], ["findQuietly", quietly]]) conv[name] = inScope(scope, f.params, f.body);
    conv.load();
    conv.findWhenRead("invoice number");
    const early = steps.length;
    reply({ ev: "transcript", items: [{ role: "user", kind: "text", text: "where is the invoice number?" }], offset: 900 });
    check("once the conversation is read the words are found, the find bar shows them, and not before",
      early === 0 && conv.finding && findField.text === "invoice number" && JSON.stringify(steps) === "[1]",
      `found ${steps.length} times (${early} before the read), bar ${conv.finding} "${findField.text}"`);
  } else check("once the conversation is read the words are found, the find bar shows them, and not before", false,
    "the conversation has no way to find words once it is read");
}

// [3] Codex installed, or Claude Code signed in, from a terminal: back in Praxis the box went on saying "Not installed"
// or "isn't signed in" until the host's ten-minute look or a visit to Settings
{
  const focus = qmlFunction(boxSrc, "onActiveChanged");
  const back = ({ active = true, needsStep = false, menu = "" }) => {
    const asked = [];
    const composer = { Window: { window: { active } }, hasAccounts: true, needsStep, menu, accounts: { check: id => asked.push(id) } };
    inScope({ composer, flowProbe: { running: true } }, focus.params, focus.body)();
    return asked;
  };
  const step = back({ needsStep: true }), menu = back({ menu: "agent" });
  check("coming back to the window while the box shows a step, or with the agent menu open, asks the host to look again",
    JSON.stringify(step) === '[""]' && JSON.stringify(menu) === '[""]', `with a step ${JSON.stringify(step)}, with the menu ${JSON.stringify(menu)}`);
  check("and not when nothing needs a step, nor as the window loses the focus",
    !back({}).length && !back({ active: false, needsStep: true }).length);
}
done();
