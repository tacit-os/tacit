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
    Key_Left: 0x01000012, Key_Right: 0x01000014, Key_Space: 0x20, Key_Delete: 0x01000007, Key_F2: 0x01000031, Key_F10: 0x01000039, Key_Menu: 0x01000055,
    Key_Z: 0x5a, Key_V: 0x56, Key_3: 0x33, ShiftModifier: 0x02000000, ControlModifier: 0x04000000, AltModifier: 0x08000000, MetaModifier: 0x10000000,
    KeypadModifier: 0x20000000, Key_Backspace: 0x01000003, Key_2: 0x32, Key_Shift: 0x01000020, Key_Control: 0x01000021, Key_Meta: 0x01000022,
    Key_Alt: 0x01000023, Key_CapsLock: 0x01000024, Key_NumLock: 0x01000025, Key_Super_L: 0x01000053, Key_Super_R: 0x01000054, Key_AltGr: 0x01001103 };
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
  const press = (key, { text = "", typed = "", mods = 0, aside = false, card = true, held = false } = {}) => {
    const log = [];
    // a box the person has clicked in since the card came up (carried-r1 [0], below, is the box not yet touched)
    const composer = { suggest: { items: [] }, aside, attachments: [], working: true, pick: 0, touched: true,
      card: card ? { key: k => (log.push(`card ${k}`), true) } : null, submit: () => log.push("send"), stop: () => log.push("stop") };
    const scope = { composer, Qt, input: { text: typed }, pasteImage: {} };
    for (const name of ["cardKey", "arms"]) { const f = qmlFunction(boxSrc, name); if (f) composer[name] = inScope(scope, f.params, f.body); }
    const e = { key, text, modifiers: mods, accepted: false, isAutoRepeat: held };
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
  // shell-praxis review r1 [1]: a held key repeats (Tacit's repeat_delay is 250 ms) into the box once its press has
  // moved the keyboard there, as the rail's Enter does: the repeats answered the card the press never reached
  const held = { enter: press(Qt.Key_Return, { text: "\r", held: true }), esc: press(Qt.Key_Escape, { held: true }),
    digit: press(Qt.Key_3, { text: "3", held: true }), typed: press(Qt.Key_Return, { text: "\r", typed: "go on", held: true }) };
  check("a held Enter, Esc or digit's repeats answer no card and do nothing else while it waits; with words in the box a held Enter sends them",
    JSON.stringify(held) === '{"enter":"","esc":"","digit":"","typed":"send"}', JSON.stringify(held));
  // shell-praxis review r1 [1]: a reply's text holding the keyboard (a click to read it) and the rail (claude.qml's
  // onTyped) hand their keys to typeInto, which typed them into the box and handed the card's keys to the card: Enter on
  // the rail's session, pressed to go and type there, allowed its waiting Bash card before it was read
  const conv = read("modules/claude/Conversation.qml");
  const c = qmlFunction(boxSrc, "cardKey"), f = qmlFunction(conv, "typeInto");
  const passOn = (from, key, text, { typed = "", bash = false } = {}) => {
    const log = [], said = [];
    const card = bash ? { pending: { tool: "Bash", input: { command: "rm -rf build" }, suggestions: [{}] }, canAlways: true, keyed: true, sent: false,
      answered: (...a) => said.push(a) } : { key: k => (log.push(`card ${k}`), true) };
    if (bash) {
      Object.defineProperty(card, "buttons", { get: () => cardValue("buttons", card.pending) });
      for (const name of ["key", "pick"]) { const q = qmlFunction(perm_src, name); card[name] = inScope({ card }, q.params, q.body); }
    }
    const composer = { aside: false, attachments: [], card, focusInput: () => log.push("focus"), insertAtCursor: t => log.push(`type ${t}`) };
    const scope = { composer, Qt, input: { text: typed } };
    if (c) composer.cardKey = inScope(scope, c.params, c.body);
    const typeInto = inScope(scope, f.params, f.body);
    const e = { key, text, modifiers: 0, accepted: false };
    if (from === "rail") {
      const row = { key: "s:abc", type: "session", id: "abc", session: { id: "abc" } };
      const rail = { cursorKey: row.key, currentId: "abc", rows: [row], rowOf: k => (k === row.key ? row : null), typed: typeInto, fold: () => log.push("fold") };
      const k = qmlFunction(read("modules/claude/SessionList.qml"), "key");
      inScope({ rail, Qt }, k.params, k.body)(e);
    } else typeInto(e);
    return log.join(",") + (said.length ? ` (card ${said[0][0] ? "allowed" : "denied"})` : "");
  };
  const fromReply = [passOn("reply", Qt.Key_Return, "\r"), passOn("reply", Qt.Key_Escape, "\u001b"), passOn("reply", Qt.Key_3, "3"), passOn("reply", Qt.Key_3, "3", { typed: "step " })];
  check("from a reply's text Enter gives the box the keyboard, Esc is not taken and a digit is typed into the box: no card is answered",
    JSON.stringify(fromReply) === '["focus","","focus,type 3","focus,type 3"]', JSON.stringify(fromReply));
  const fromRail = [passOn("rail", Qt.Key_Return, "\r", { bash: true }), passOn("rail", Qt.Key_3, "3")];
  check("Enter on a session in the rail only gives the box the keyboard, its Bash card unanswered, and a digit there is typed into the box",
    /onTyped:\s*e\s*=>\s*conv\.typeInto\(e\)/.test(read("claude.qml")) && JSON.stringify(fromRail) === '["focus","focus,type 3"]', JSON.stringify(fromRail));
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

  // carried-r1 [0]: opening a session moves the keyboard into the box (Conversation's closeFind), and the first Enter
  // there, pressed to go and type, allowed the Bash card waiting in it. The card's keys now arm only once the person has
  // clicked in the box or typed a key there (not Enter, Esc or a digit) since the session opened or the card came up.
  {
    const app = read("claude.qml"), list = read("modules/claude/SessionList.qml");
    const exprAfter = (src, re) => { const m = re.exec(src); return m ? readExpression(src, m.index + m[0].length).expr : ""; };
    const changed = /\bonSessionChanged:\s*\{/.exec(conv), sessionBody = changed ? readExpression(conv, changed.index + changed[0].length - 1).expr.slice(1, -1) : "";
    const cardChanged = exprAfter(boxSrc, /\bonCardChanged:\s*/);
    // the text's own onPressed (a click in it), between `id: input` and its Keys.onPressed
    const ti = boxSrc.indexOf("id: input"), tk = boxSrc.indexOf("Keys.onPressed", ti);
    const pressRe = /\n\s*onPressed:\s*/g;
    pressRe.lastIndex = ti;
    const pm = pressRe.exec(boxSrc), clickLine = pm && pm.index < tk ? readExpression(boxSrc, pm.index + pm[0].length).expr : "";
    const bash = () => {
      const said = [];
      const card = { pending: { tool: "Bash", input: { command: "rm -rf build" }, suggestions: [{}], request: "7" }, canAlways: true, keyed: true, sent: false,
        answered: (...a) => said.push(a[0] ? "allowed" : "denied") };
      Object.defineProperty(card, "buttons", { get: () => cardValue("buttons", card.pending) });
      for (const name of ["key", "pick"]) { const q = qmlFunction(perm_src, name); card[name] = inScope({ card }, q.params, q.body); }
      return { card, said };
    };
    // Praxis as one piece: the box, the conversation's onSessionChanged and opened(), the rail's move() and key(), its
    // row click, claude.qml's choose(), openId(), onChosen and the notch's open(id), Alt+Down's Shortcut
    const world = () => {
      const log = [], a = bash(), b = bash();
      const sA = { id: "a", tool: "claude", cwd: "/home/x/a" }, sB = { id: "b", tool: "codex", cwd: "/home/x/b" };
      const input = { text: "" };
      const composer = { suggest: { items: [] }, aside: false, attachments: [], working: true, locked: false, pick: 0, menu: "", needsStep: false,
        card: null, cardUp: null, touched: false, text: "", stop: () => log.push("stop"), sendFn: t => (log.push(`send ${t}`), true),
        isImage: () => false, focusInput: () => log.push("focus"), setDraft() {}, insertAtCursor: t => { input.text += t; } };
      const scope = { composer, Qt, input, pasteImage: {} };
      for (const name of ["cardKey", "arms", "submit"]) { const f = qmlFunction(boxSrc, name); if (f) composer[name] = inScope(scope, f.params, f.body); }
      const keys = inScope(scope, "", `return (${handler});`)();
      // the card on top as the conversation binds it: each session's own Bash card
      const setCard = c => { composer.card = c; if (cardChanged) inScope(scope, "", cardChanged)(); };
      const convObj = { session: sA, loadedKey: "a", shownSession: sA, drafts: {}, queued: [], findOnLoad: "", closeFind: () => composer.focusInput(), load() {} };
      const convScope = { conv: convObj, composer };
      for (const name of ["opened", "typeInto"]) { const f = qmlFunction(conv, name); if (f) convObj[name] = inScope(convScope, f.params, f.body); }
      const onSession = inScope(convScope, "", sessionBody);
      const rows = [sA, sB].map(s => ({ key: "s:" + s.id, type: "session", id: s.id, session: s }));
      const root = { history: [sA, sB], allHistory: [sA, sB], loaded: true, wantedId: "", visible: true, reveal() {} };
      Object.defineProperty(root, "selected", { get: () => convObj.session, set: s => {
        if (s === convObj.session) return;   // QML sends no change for the same object
        convObj.session = s; onSession(); setCard(s === sA ? a.card : b.card);
      } });
      const rail = { rows, currentId: "a", cursorKey: "s:a", openBy: "", rowOf: k => rows.find(r => r.key === k) ?? null,
        indexOf: k => rows.findIndex(r => r.key === k), navigable: () => true, fold() {}, armDwell() {}, typed: e => convObj.typeInto(e) };
      const appScope = { root, rail, conv: convObj, host: { live: {} }, Quickshell: { env: () => "" }, cove: { close() {} } };
      for (const name of ["choose", "openId"]) { const f = qmlFunction(app, name); root[name] = inScope(appScope, f.params, f.body); }
      const onChosen = inScope(appScope, "", `return (${exprAfter(app, /\bonChosen:\s*/)});`)();
      rail.chosen = s => { onChosen(s); rail.currentId = s.id; };
      const railScope = { rail, Qt, list: { forceActiveFocus() {}, positionViewAtIndex() {} } };
      for (const name of ["move", "stepCursor", "key"]) { const f = qmlFunction(list, name); rail[name] = inScope(railScope, f.params, f.body); }
      const ipcOpen = qmlFunction(app.slice(app.indexOf('target: "claudeapp"')), "open");
      const notch = inScope(appScope, ipcOpen.params.replace(/:\s*\w+/g, ""), ipcOpen.body);
      // where the person was: session A, its box clicked into while its card waited
      setCard(a.card);
      composer.touched = true;
      const press = (key, text = "", mods = 0, held = false) => { const e = { key, text, modifiers: mods, accepted: false, isAutoRepeat: held }; keys(e); return e; };
      const click = () => { if (clickLine) inScope(scope, "", clickLine)(); };
      const ways = {
        "a rail click": () => rail.chosen(rows[1].session),
        "Down from the rail's search": () => inScope({ rail }, "", exprAfter(list, /Keys\.onDownPressed:\s*/))(),
        "Down in the rail": () => { rail.cursorKey = "s:a"; rail.key({ key: Qt.Key_Down, text: "", modifiers: 0, accepted: false }); },
        "Alt+Down": () => { press(Qt.Key_Alt, "", Qt.AltModifier); inScope(appScope, "", exprAfter(app, /sequence:\s*"Alt\+Down";\s*onActivated:\s*/))(); },
        "the notch": () => notch("b"),
      };
      return { log, a, b, composer, input, press, click, ways, notch, setCard, on: () => convObj.session.id };
    };
    const enter = w => { w.log.length = 0; w.press(Qt.Key_Return, "\r"); return [...w.a.said, ...w.b.said, ...w.log].join(",") || "nothing"; };
    const opened = {}, clicked = {};
    for (const way of Object.keys(world().ways)) {
      const w = world();
      w.ways[way]();
      w.press(Qt.Key_Return, "\r", 0, true);   // the repeats of a held Enter
      opened[way] = `${w.on()}: ${enter(w)}`;
      w.click();
      clicked[way] = enter(w);
    }
    check("a session opened with a Bash card waiting, by a rail click, Down from the search or in the rail, Alt+Down or the notch: Enter in its box answers nothing and sends nothing",
      Object.values(opened).every(v => v === "b: nothing"), JSON.stringify(opened));
    check("then a click in the box, and Enter allows the card",
      Object.values(clicked).every(v => v === "allowed"), JSON.stringify(clicked));
    // the notch's way back to the session already open, the box touched before: the same
    const back = world();
    back.notch("a");
    const backSaid = [`${back.on()}: ${enter(back)}`];
    back.click();
    backSaid.push(enter(back));
    check("the notch's way back to the session already open: Enter answers nothing until the box is clicked",
      JSON.stringify(backSaid) === '["a: nothing","allowed"]', JSON.stringify(backSaid));
    // untouched, Esc stops nothing and denies nothing, a digit is typed; a modifier alone, a held key's repeats, Esc and
    // a digit do not touch the box; a key typed there (Backspace in the empty box) does
    const keysSaid = {};
    {
      const w = world();
      w.ways["a rail click"]();
      w.log.length = 0;
      w.press(Qt.Key_Escape, "\u001b");
      keysSaid.esc = [...w.b.said, ...w.log].join(",") || "nothing";
      const two = w.press(Qt.Key_2, "2");
      keysSaid.digit = w.b.said.join(",") || (two.accepted ? "taken" : "typed");
      w.input.text = "";
      w.press(Qt.Key_Shift, "", Qt.ShiftModifier); w.press(Qt.Key_Down, "", 0, true); w.press(Qt.Key_Escape, "\u001b"); w.press(Qt.Key_3, "3");
      w.input.text = "";
      keysSaid.untouched = enter(w);
      w.press(Qt.Key_Backspace, "\b");
      keysSaid.typed = enter(w);
    }
    check("until the box is touched Esc stops and denies nothing and a digit is not an answer; Shift, a held Down, Esc and 3 leave it untouched, Backspace touches it",
      JSON.stringify(keysSaid) === '{"esc":"nothing","digit":"typed","untouched":"nothing","typed":"allowed"}', JSON.stringify(keysSaid));
    // another card coming up in the session open takes the keys back from a box touched before it
    {
      const w = world(), c = bash();
      w.setCard(c.card);
      w.press(Qt.Key_Return, "\r");
      const first = c.said.join(",") || "nothing";
      w.click();
      w.press(Qt.Key_Return, "\r");
      check("a card that comes up after the box was touched answers Enter only after another click there",
        first === "nothing" && c.said.join(",") === "allowed", `${first}, then ${c.said.join(",") || "nothing"}`);
    }
    // the click: Qt's TextArea inside its Flickable, as the box is, says pressed for a click in it (the tree's own line)
    const out = runScene({ "tst_click.qml": `import QtQuick
import QtQuick.Controls
import QtTest
Item {
    id: composer
    width: 400; height: 300
    property bool touched: false
    Flickable {
        width: 300; height: 60
        TextArea.flickable: TextArea { id: input; ${clickLine ? `onPressed: ${clickLine}` : ""} }
    }
    TestCase {
        name: "click"; when: windowShown; visible: true
        function test_click() { mouseClick(input, 20, 10); console.log("CLICK " + JSON.stringify({ touched: composer.touched, focus: input.activeFocus })) }
    }
}
` });
    let clickOut = {};
    try { clickOut = logged(out, "CLICK"); } catch (e) { clickOut = { error: e.message }; }
    check("a click in the box's text (a TextArea in its Flickable) touches it", clickOut.touched === true && clickOut.focus === true, JSON.stringify(clickOut));
  }
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
