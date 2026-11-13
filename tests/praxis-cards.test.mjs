// Praxis's permission, question and choose cards (modules/claude/*Card.qml): what they answer to and what they show
// before the person says yes. Their own expressions run under node; the rest is read from the QML.
import { inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { logged, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

const perm = read("modules/claude/PermissionCard.qml"), perm_src = perm;
// the QML item whose own lines hold the index at: { type, at, text } (text braces and all), or an empty one
function itemAt(src, at) {
  for (let i = at, depth = 0; i >= 0; i--) {
    if (src[i] === "}") depth++;
    else if (src[i] === "{" && depth-- === 0)
      return { type: src.slice(0, i).match(/(\w+)\s*$/)?.[1] ?? "", at: i, text: src.slice(i, matchBrace(src, i) + 1) };
  }
  return { type: "", at: -1, text: "" };
}
const itemWith = (src, line) => (src.includes(line) ? itemAt(src, src.indexOf(line)) : itemAt(src, -1));
const detail = itemWith(perm, "text: card.detail"), detailText = detail.text;
// a property of the card as it evaluates for this pending request (undefined when the card has no such property)
function cardValue(name, pending, more = {}) {
  const expr = qmlProperty(perm, name);
  if (expr === null) return undefined;
  const body = expr.startsWith("{") ? expr.slice(1, -1) : `return (${expr});`;
  return inScope({ card: { pending, canAlways: true, ...more } }, "", body)();
}

console.log("Praxis's cards (modules/claude/PermissionCard.qml, QuestionCard.qml, ChooseCard.qml)");

// later-praxis-2 [14], as the owner decided (r14): one set of keys on every card, from the box, which keeps the
// keyboard (Tab too) while a card waits: Enter its first answer, Esc its no, 1-9 its nth; no hints on the cards (b64089c).
// The cards had Alt chords each of their own (Alt+Shift+Enter, Alt+S, Alt+0, Alt+Left), found by nobody.
{
  const Qt = { Key_Escape: 0x01000000, Key_Tab: 0x01000001, Key_Return: 0x01000004, Key_Enter: 0x01000005, Key_Down: 0x01000015, Key_Up: 0x01000013,
    Key_V: 0x56, Key_3: 0x33, ShiftModifier: 0x02000000, ControlModifier: 0x04000000, AltModifier: 0x08000000, MetaModifier: 0x10000000, KeypadModifier: 0x20000000 };
  const srcs = Object.fromEntries(["PermissionCard", "QuestionCard", "ChooseCard"].map(f => [f, read(`modules/claude/${f}.qml`)]));
  const left = Object.entries(srcs).filter(([, src]) => /\bShortcut\s*\{|\bsequences?:/.test(src)).map(([f]) => f);
  check("no card keeps a Shortcut of its own, and the choose card shows no key at its rows",
    !left.length && !/text:\s*row\.index\s*\+\s*1/.test(srcs.ChooseCard), `Shortcuts in ${left.join(", ") || "none"}`);

  // each card's key(), run under node: what Enter, Esc and a digit answer
  const keyOf = (f, scope) => { const q = qmlFunction(srcs[f], "key"); return q ? inScope(scope, q.params, q.body) : () => false; };
  const perm = (tool, suggestions) => {
    const said = [];
    const card = { pending: { tool, input: {}, suggestions }, canAlways: suggestions.length > 0, keyed: true, sent: false, answered: (...a) => said.push(a) };
    Object.defineProperty(card, "buttons", { get: () => cardValue("buttons", card.pending, { canAlways: card.canAlways }) });
    card.pick = inScope({ card }, qmlFunction(perm_src, "pick").params, qmlFunction(perm_src, "pick").body);
    const key = keyOf("PermissionCard", { card });
    return k => { card.sent = false; said.length = 0; const took = key(k); return took ? `${said[0]?.[0] ? "allow" : "deny"}${said[0]?.[1] ? " always" : ""}${said[0]?.[2]?.scope ? " " + said[0][2].scope : ""}` : "-"; };
  };
  const bash = perm("Bash", [{}]), door = perm("Door", []), plan = perm("ExitPlanMode", []);
  const permSaid = [bash("enter"), bash(2), bash("esc"), bash(3), bash(4), door(2), door(3), door("esc"), plan("esc")];
  const question = () => {
    const log = [];
    const card = { keyed: true, sent: false, multi: false, current: { question: "Which?", options: [{ label: "A" }, { label: "B" }] },
      toggle: (q, l) => log.push(`pick ${l}`), next: () => log.push("next"), skipped: () => log.push("skip") };
    const key = keyOf("QuestionCard", { card });
    return [2, 3, "enter", "esc"].map(k => (key(k) ? log.pop() : "-"));
  };
  const choose = () => {
    const log = [];
    const card = { keysOn: true, sent: false, picked: [], items: ["/a", "/b"], toggle: p => { card.picked = [p]; log.push(`tick ${p}`); },
      submit: none => log.push(`answer ${card.picked}`), declined: () => log.push("leave") };
    const key = keyOf("ChooseCard", { card });
    const out = [key("enter") ? log.pop() ?? "nothing" : "-"];
    for (const k of [2, 3, "enter", "esc"]) out.push(key(k) ? log.pop() : "-");
    return out;
  };
  check("Enter allows and Esc denies (or keeps planning) on a permission card; a digit is never an answer there, it is typed",
    JSON.stringify(permSaid) === JSON.stringify(["allow", "-", "deny", "-", "-", "-", "-", "deny", "deny"]), JSON.stringify(permSaid));
  check("on a question card a digit picks that choice, Enter goes on and Esc skips; on a choose card a digit ticks, Enter answers, Esc leaves it to the agent",
    JSON.stringify(question()) === '["pick B","-","next","skip"]' && JSON.stringify(choose()) === '["nothing","tick /b","-","answer /b","leave"]',
    `question ${JSON.stringify(question())}, choose ${JSON.stringify(choose())}`);

  // the box hands them over only while nothing is typed in it; Tab stays in the box
  const boxSrc = read("modules/claude/Composer.qml");
  const m = /Keys\.onPressed:\s*/.exec(boxSrc);
  const handler = m ? readExpression(boxSrc, m.index + m[0].length).expr : "e => {}";
  const press = (key, { text = "", typed = "", mods = 0, aside = false, card = true } = {}) => {
    const log = [];
    const composer = { suggest: { items: [] }, aside, attachments: [], working: true, pick: 0,
      card: card ? { key: k => (log.push(`card ${k}`), true) } : null, submit: () => log.push("send"), stop: () => log.push("stop") };
    const scope = { composer, Qt, input: { text: typed }, pasteImage: {} };
    const f = qmlFunction(boxSrc, "cardKey");
    if (f) composer.cardKey = inScope(scope, f.params, f.body);
    const e = { key, text, modifiers: mods, accepted: false };
    inScope(scope, "", `return (${handler});`)()(e);
    return log.join(",") + (e.accepted ? "" : " (to the text)");
  };
  const got = {
    enter: press(Qt.Key_Return, { text: "\r" }), pad: press(Qt.Key_Enter, { text: "\r", mods: Qt.KeypadModifier }), esc: press(Qt.Key_Escape),
    digit: press(Qt.Key_3, { text: "3" }), typedEnter: press(Qt.Key_Return, { text: "\r", typed: "no, use rsync" }),
    typedDigit: press(Qt.Key_3, { text: "3", typed: "step " }), typedEsc: press(Qt.Key_Escape, { typed: "x" }),
    shiftEnter: press(Qt.Key_Return, { text: "\r", mods: Qt.ShiftModifier }), altDigit: press(Qt.Key_3, { text: "3", mods: Qt.AltModifier }),
    aside: press(Qt.Key_Return, { text: "\r", aside: true }), none: press(Qt.Key_Return, { text: "\r", card: false }), tab: press(Qt.Key_Tab, { text: "\t" }),
  };
  const want = { enter: "card enter", pad: "card enter", esc: "card esc", digit: "card 3", typedEnter: "send", typedDigit: " (to the text)",
    typedEsc: "stop", shiftEnter: " (to the text)", altDigit: " (to the text)", aside: "send", none: "send", tab: " (to the text)" };
  const wrong = Object.keys(want).filter(k => got[k] !== want[k]);
  check("the box hands Enter, Esc and 1-9 to the card while it is empty; typed words keep them, and Tab is the box's",
    !wrong.length, wrong.map(k => `${k}: ${JSON.stringify(got[k])} (want ${JSON.stringify(want[k])})`).join("; "));
  // a reply's text holding the keyboard (a click to read it) passes typing on to the box, and the card's keys with it
  const conv = read("modules/claude/Conversation.qml");
  const reply = (key, text, typed = "") => {
    const log = [];
    const composer = { aside: false, attachments: [], card: { key: k => (log.push(`card ${k}`), true) },
      focusInput: () => log.push("focus"), insertAtCursor: t => log.push(`type ${t}`) };
    const scope = { composer, Qt, input: { text: typed } };
    const c = qmlFunction(boxSrc, "cardKey"), f = qmlFunction(conv, "typeInto");
    if (c) composer.cardKey = inScope(scope, c.params, c.body);
    const e = { key, text, modifiers: 0, accepted: false };
    inScope(scope, f.params, f.body)(e);
    return log.join(",");
  };
  const fromReply = [reply(Qt.Key_Return, "\r"), reply(Qt.Key_Escape, "\u001b"), reply(Qt.Key_3, "3"), reply(Qt.Key_3, "3", "step ")];
  check("from a reply's text the card's keys answer it as from the box, and with words in the box a digit is typed there",
    JSON.stringify(fromReply) === '["card enter,focus","card esc,focus","card 3,focus","focus,type 3"]', JSON.stringify(fromReply));
  const at = conv.indexOf("Composer {");
  const bound = at < 0 ? "" : conv.slice(at, matchBrace(conv, conv.indexOf("{", at)) + 1).match(/\n\s*card:\s*([^\n]*)/)?.[1] ?? "";
  check("the conversation gives the box the first card waiting, when it takes keys", /asks\.itemAt\(0\)/.test(bound) && /\.keys\b/.test(bound), bound || "no card: on the Composer");

  // Qt's TextArea keeps a Tab it is given (it types one) beside a button that takes Tab focus, as the box beside a card
  const out = runScene({ "tst_tab.qml": `import QtQuick
import QtQuick.Controls
import QtTest
Item {
    width: 400; height: 300
    TextArea { id: box; width: 300; height: 100; focus: true }
    Rectangle { y: 150; width: 80; height: 32; activeFocusOnTab: true }
    TestCase {
        name: "tab"; when: windowShown
        function test_tab() { box.forceActiveFocus(); keyClick(Qt.Key_Tab); console.log("TAB " + JSON.stringify({ focus: box.activeFocus, text: box.text })) }
    }
}
` });
  let tab = {};
  try { tab = logged(out, "TAB"); } catch (e) { tab = { error: e.message }; }
  check("a Tab in a TextArea stays there (Qt types it), so the box keeps the keyboard while a card waits", tab.focus === true && tab.text === "\t", JSON.stringify(tab));
}

// a Text's default (AutoText) draws a line that starts with a known tag as rich text: echo "<b>done</b>" showed "done"
check("the command, path or address is drawn as plain text", /\btextFormat:\s*Text\.PlainText\b/.test(detailText),
  detailText ? "no textFormat: Text.PlainText on the item showing card.detail" : "no item shows card.detail");

// cut at six lines with an ellipsis, the rest of a heredoc or a long pipeline could not be read before Allow once
{
  const box = itemAt(perm, detail.at - 1);
  check("the whole command is shown, scrolling in a Flickable as the diff does",
    detailText && !/\b(maximumLineCount|elide):/.test(detailText) && box.type === "Flickable" && /\bcontentHeight:/.test(box.text),
    `the detail ${/maximumLineCount/.test(detailText) ? "stops at maximumLineCount" : "shows every line"}, inside a ${box.type || "nothing"}`);
}

// the diff stops at 3000 characters of each side: a Write of 10,000 showed its first 3000 as if they were the file
{
  const cut = (tool, input) => cardValue("change", { tool, input })?.cut;
  const long = "x".repeat(10000), cuts = [cut("Write", { content: long }), cut("Edit", { old_string: "a", new_string: long }),
    cut("MultiEdit", { edits: [{ old_string: long, new_string: "b" }, { old_string: "c", new_string: "d" }] }), cut("Write", { content: "short" })];
  const m = /\bcard\.change\??\.cut\b/.exec(perm.slice(perm.indexOf("ColumnLayout")));
  const said = m ? itemAt(perm, perm.indexOf("ColumnLayout") + m.index) : { type: "" };
  check("a diff cut at 3000 characters counts what it left out, and the card says it under the diff",
    JSON.stringify(cuts) === "[7000,7000,7002,0]" && said.type !== "" && said.type !== "DiffView" && /\bvisible:[^\n]*\bcut\b/.test(said.text),
    `left out ${JSON.stringify(cuts)} (should be [7000,7000,7002,0]), said by ${said.type || "nothing"}`);
}

// Plan mode ends by asking for ExitPlanMode with { plan }: the card read "Use ExitPlanMode?" over one cut-off line of JSON
{
  const pending = { tool: "ExitPlanMode", input: { plan: "## Steps\n1. Move the card\n2. Test it" } };
  const label = cardValue("label", pending), plan = cardValue("plan", pending);
  const drawn = itemWith(perm, "markdown: card.plan");
  check("a plan to start on has its own question and is drawn as markdown, scrolling with the detail",
    !/ExitPlanMode/.test(label) && plan === pending.input.plan && cardValue("plan", { tool: "Bash", input: { command: "ls" } }) === ""
      && drawn.type === "ClaudeText" && itemAt(perm, drawn.at - 1).type === "Flickable",
    `"${label}", plan ${JSON.stringify(plan)}, drawn by ${drawn.type || "nothing"}`);
}

// the plan's answers were Allow once / Always allow / Deny in a 220 px area: Claude Code's are start, or keep planning
{
  const pending = { tool: "ExitPlanMode", input: { plan: "## Steps" }, suggestions: [{}] };
  const buttons = cardValue("buttons", pending) ?? [];
  const sent = [];
  const pick = qmlFunction(perm, "pick");
  const answer = b => inScope({ card: { sent: false, pending, answered: (...a) => sent.push(a) } }, pick.params, pick.body)(b);
  buttons.forEach(answer);
  const keep = sent[1] ?? [];
  check("a plan is answered with Start on this plan or Keep planning, and Keep planning tells the agent so",
    JSON.stringify(buttons.map(b => [b.label, b.allow])) === '[["Start on this plan",true],["Keep planning",false]]'
      && sent[0]?.[0] === true && sent[0]?.[3] === "" && keep[0] === false && /keep planning/i.test(keep[3] ?? ""),
    `${JSON.stringify(buttons.map(b => b.label))}, Keep planning sends ${JSON.stringify(keep)}`);
  const flick = itemWith(perm, "readonly property Item shown"), m = /Layout\.preferredHeight:\s*/.exec(flick.text);
  const height = (plan, implicit, maxHeight) => m ? inScope({ card: { plan, maxHeight }, detailFlick: { shown: { implicitHeight: implicit } } }, "",
    `return (${flick.text.slice(m.index + m[0].length).split("\n")[0]});`)() : 0;
  const conv = read("modules/claude/Conversation.qml");
  const at = conv.indexOf("PermissionCard {"), inConv = at < 0 ? "" : conv.slice(at, matchBrace(conv, conv.indexOf("{", at)) + 1);
  check("the plan grows into the room the conversation gives it, a command still stops at 220 px",
    height("## Steps", 2000, 1000) > 600 && height("## Steps", 2000, 0) === 220 && height("", 2000, 1000) === 220 && height("## Steps", 90, 1000) === 90
      && /\bmaxHeight:/.test(inConv) && /req\.message\s*=\s*message/.test(inConv),
    `a long plan gets ${height("## Steps", 2000, 1000)} px of a 1000 px room, a command ${height("", 2000, 1000)}; Conversation ${/\bmaxHeight:/.test(inConv) ? "gives" : "gives no"} maxHeight and ${/req\.message/.test(inConv) ? "passes" : "drops"} the message`);
}
done();
