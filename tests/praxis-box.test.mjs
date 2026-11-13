// Praxis's message box and what stands over it (modules/claude/Composer.qml, QuestionCard.qml, ModelChooser.qml,
// Conversation.qml): a pasted picture, the attachments, a half-answered question, the model menu. The files' own code runs
// under node and bash.
import { mkdirSync, mkdtempSync, rmSync, statSync, writeFileSync, chmodSync, readdirSync } from "fs";
import { spawnSync } from "child_process";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const boxSrc = read("modules/claude/Composer.qml");
// the QML item whose own lines hold the index at: { type, at, text } (text braces and all)
function itemAt(src, at) {
  for (let i = at, depth = 0; i >= 0; i--) {
    if (src[i] === "}") depth++;
    else if (src[i] === "{" && depth-- === 0)
      return { type: src.slice(0, i).match(/(\w+)\s*$/)?.[1] ?? "", at: i, text: src.slice(i, matchBrace(src, i) + 1) };
  }
  return { type: "", at: -1, text: "" };
}

console.log("Praxis's message box (modules/claude/Composer.qml, QuestionCard.qml, Conversation.qml)");

// later-praxis-1 [16] a picture pasted into the box is saved under ~/.cache/agent-host/paste, and with the default umask
// the folder and every screenshot in it (a bank page, a password manager) were readable by any other user
{
  const at = boxSrc.indexOf("id: pasteImage");
  const cmd = inScope({}, "", `return (${readExpression(boxSrc, boxSrc.indexOf("command:", at) + "command:".length).expr});`)();
  const home = mkdtempSync(join(tmpdir(), "praxis-paste-")), bin = join(home, "bin");
  mkdirSync(bin);
  // a clipboard holding a PNG, as wl-paste lists and gives it
  writeFileSync(join(bin, "wl-paste"), '#!/bin/sh\nif [ "$1" = --list-types ]; then echo image/png; else printf "\\211PNG\\r\\n\\032\\n"; fi\n');
  chmodSync(join(bin, "wl-paste"), 0o755);
  const paste = () => spawnSync("/bin/bash", ["-c", `umask 022; ${cmd[2]}`], { env: { HOME: home, PATH: `${bin}:/usr/bin:/bin` }, encoding: "utf8" }).stdout.trim();
  const first = paste();
  const dir = join(home, ".cache/agent-host/paste");
  chmodSync(dir, 0o755);   // a folder made by an older Praxis
  const second = paste();
  const mode = p => (statSync(p).mode & 0o777).toString(8);
  check("a pasted picture is saved for its owner alone, in a folder only they can open, one an older Praxis made too",
    first && second && mode(first) === "600" && mode(second) === "600" && mode(dir) === "700" && readdirSync(dir).length === 2,
    `files ${first ? mode(first) : "none"} and ${second ? mode(second) : "none"}, folder ${mode(dir)}`);
  rmSync(home, { recursive: true });
}

// later-praxis-1 [18] the attachments' row lay beside the box's clipped tray area with no width limit: six PDFs or twenty
// screenshots ran on past the box's right edge, over the conversation, the later ones' remove buttons out of reach
{
  const row = itemAt(boxSrc, boxSrc.indexOf("id: tray\n")), holder = itemAt(boxSrc, row.at - 1);
  const own = holder.text.slice(0, holder.text.indexOf("Row {"));   // the holder's own lines, before the row
  check("the attachments scroll sideways inside the box: the row sits in a clipped Flickable as wide as the box",
    row.type === "Row" && holder.type === "Flickable" && /\bclip:\s*true/.test(own) && /\bcontentWidth:\s*tray\.width/.test(own)
      && /\bleft:\s*parent\.left/.test(own) && /\bright:\s*parent\.right/.test(own) && /HorizontalFlick/.test(own),
    `the row is held by ${holder.type || "nothing"}${holder.type === "Flickable" ? "" : " (the box, unclipped)"}`);
}

// later-praxis-1 [19] a card asking four questions, three answered, then another session opened and this one again: the
// card was made anew, every pick and typed answer gone, back on question 1 of 4
{
  const cardSrc = read("modules/claude/QuestionCard.qml"), convSrc = read("modules/claude/Conversation.qml");
  const at = convSrc.indexOf("QuestionCard {"), inConv = convSrc.slice(at, matchBrace(convSrc, convSrc.indexOf("{", at)) + 1);
  const binding = name => { const m = new RegExp(`\\b${name}:\\s*`).exec(inConv); return m ? readExpression(inConv, m.index + m[0].length).expr : ""; };
  const pending = { request: "r7", tool: "AskUserQuestion", input: { questions: ["Colour", "Size", "Name", "Ship"].map(q => ({ question: q, options: [{ label: "A" }, { label: "B" }] })) } };
  const conv = { asksKept: {} }, ask = { request: "r7", modelData: pending, keys: true };
  // a card as the Loader makes it: its bindings, then Component.onCompleted
  const make = () => {
    const other = { text: "" };
    const card = { pending, picked: {}, typed: {}, step: 0, shown: 0 };
    const scope = { card, other, conv, ask, swap: { restart() {} } };
    for (const name of ["questions", "current", "half"]) { const e = qmlProperty(cardSrc, name); if (e) Object.defineProperty(card, name, { get: () => inScope(scope, "", `return (${e});`)() }); }
    const kept = binding("kept");
    card.kept = kept ? inScope(scope, "", `return (${kept});`)() : null;
    const restore = qmlFunction(cardSrc, "restore");
    if (restore) card.restore = inScope(scope, restore.params, restore.body);
    const done = /\bComponent\.onCompleted:\s*/.exec(cardSrc);
    if (done) { const e = readExpression(cardSrc, done.index + done[0].length).expr; inScope(scope, "", /^if\b/.test(e) ? `${e};` : `return (${e});`)(); }
    const halfChanged = binding("onHalfChanged");
    // in the handler, a bare name is the card's own (half)
    const own = { conv, ask, get half() { return card.half; } };
    return { card, other, changed: () => { if (halfChanged) inScope(own, "", `return (${halfChanged});`)(); } };
  };
  const first = make();
  Object.assign(first.card, { picked: { Colour: ["B"], Size: ["A"] }, typed: { Name: "Tacit" }, shown: 2, step: 2 });
  first.changed();
  const again = make();   // another session opened and this one again: syncAsks dropped the row, the Loader made a new card
  check("coming back, the card has its picks and typed answer and is on the question it was on",
    JSON.stringify(again.card.picked) === '{"Colour":["B"],"Size":["A"]}' && again.card.typed.Name === "Tacit" && again.card.shown === 2 && again.other.text === "Tacit",
    `picked ${JSON.stringify(again.card.picked)}, typed ${JSON.stringify(again.card.typed)}, on question ${again.card.shown + 1}, the well "${again.other.text}"`);
  conv.asksKept = {};
  const fresh = make();
  check("a question never answered starts empty on question 1", JSON.stringify(fresh.card.picked) === "{}" && fresh.card.shown === 0);
}

// the same for a choose card (mcp__tacit__choose): its ticks and its note went with the card on a session switch
{
  const cardSrc = read("modules/claude/ChooseCard.qml"), convSrc = read("modules/claude/Conversation.qml");
  const at = convSrc.indexOf("ChooseCard {"), inConv = convSrc.slice(at, matchBrace(convSrc, convSrc.indexOf("{", at)) + 1);
  const binding = name => { const m = new RegExp(`\\b${name}:\\s*`).exec(inConv); return m ? readExpression(inConv, m.index + m[0].length).expr : ""; };
  const pending = { request: "r9", tool: "Choose", input: { question: "Which?", items: ["/a/one", "/a/two", "/a/three"], multiSelect: true } };
  const conv = { asksKept: {} }, ask = { request: "r9", modelData: pending, keys: true };
  const make = () => {
    const other = { text: "" };
    const card = { pending, picked: [] };
    const scope = { card, other, conv, ask };
    for (const name of ["items", "half"]) { const e = qmlProperty(cardSrc, name); if (e) Object.defineProperty(card, name, { get: () => inScope(scope, "", `return (${e});`)() }); }
    const kept = binding("kept");
    card.kept = kept ? inScope(scope, "", `return (${kept});`)() : null;
    const done = /\bComponent\.onCompleted:\s*/.exec(cardSrc);
    if (done) { const e = readExpression(cardSrc, done.index + done[0].length).expr; inScope(scope, "", /^if\b/.test(e) ? `${e};` : `return (${e});`)(); }
    const halfChanged = binding("onHalfChanged");
    const own = { conv, ask, get half() { return card.half; } };
    return { card, other, changed: () => { if (halfChanged) inScope(own, "", `return (${halfChanged});`)(); } };
  };
  const first = make();
  first.card.picked = ["/a/one", "/a/three"];
  first.other.text = "keep the newest";
  first.changed();
  const again = make();
  check("coming back, a choose card has its ticks and its note",
    JSON.stringify(again.card.picked) === '["/a/one","/a/three"]' && again.other.text === "keep the newest",
    `ticked ${JSON.stringify(again.card.picked)}, the note "${again.other.text}"`);
  conv.asksKept = {};
  const fresh = make();
  check("a choose card never touched starts with nothing ticked", JSON.stringify(fresh.card.picked) === "[]" && fresh.other.text === "");
}

// later-praxis-2 [1] a key pressed while a reply has the keyboard goes into the box as typed: Delete's text is DEL
// (U+007F), which passed the "below 32" test and was put in the box, unseen, and sent with the next message
{
  const convSrc = read("modules/claude/Conversation.qml");
  const f = qmlFunction(convSrc, "typeInto");
  const press = (key, text) => {
    let box = "", focused = 0;
    const e = { key, text, modifiers: 0, accepted: false };
    const Qt = { ControlModifier: 0x04000000, AltModifier: 0x08000000, MetaModifier: 0x10000000, Key_Return: 0x01000004, Key_Enter: 0x01000005 };
    inScope({ Qt, composer: { cardKey: () => false, focusInput() { focused++; }, insertAtCursor(s) { box += s; } } }, f.params, f.body)(e);
    return { box, focused, accepted: e.accepted };
  };
  const del = press(0x01000007, "\u007f"), letter = press(0x41, "a"), back = press(0x01000003, "\b");
  check("Delete puts nothing in the box and does not take the keyboard there; a letter is typed into it as before",
    del.box === "" && !del.focused && !del.accepted && back.box === "" && letter.box === "a" && letter.accepted,
    `Delete put [${[...del.box].map(c => c.charCodeAt(0))}] in the box (focused ${del.focused}), a put "${letter.box}"`);
}

// later-praxis-2 [12] the model menu on a folder that keeps Opus at high: Auto lit on Opus compared the saved level with
// itself ("" || "high"), so the keep line read "Saved for new sessions" and, still, took no click: Auto could not be kept
{
  const mcSrc = read("modules/claude/ModelChooser.qml");
  const opus = { id: "claude-opus-4-7", label: "Opus", aliases: ["opus"], efforts: ["low", "medium", "high", "max"] };
  const kept = (level, m = opus, saved = { model: "opus", effort: "high" }) => {
    const mc = { level, wish: "", lit: m, agent: "claude", keepFolder: "/home/a/dev/app", isCurrent: () => true,
      model: { defaults: { folders: { "/home/a/dev/app": { agent: "claude", run: { claude: saved } } } } } };
    mc.levelFor = inScope({ mc }, qmlFunction(mcSrc, "levelFor").params, qmlFunction(mcSrc, "levelFor").body);
    const e = qmlProperty(mcSrc, "kept");
    return inScope({ mc }, "", e.startsWith("{") ? e.slice(1, -1) : `return (${e});`)();
  };
  const got = { auto: kept(""), high: kept("high"), low: kept("low"), autoSaved: kept("", opus, { model: "opus", effort: null }),
    noLevels: kept("", { id: "sonnet", label: "Sonnet", efforts: [] }, { model: "sonnet", effort: "high" }) };
  check("Auto lit on a model the folder keeps at high is not kept yet; high is, low is not, Auto is once saved",
    !got.auto && got.high && !got.low && got.autoSaved, JSON.stringify(got));
  check("a model that names no levels is kept whatever level was saved, as before", got.noLevels, JSON.stringify(got));
}

// later-praxis-2 [13] Ctrl+, in the model menu: the window's Ctrl+, Shortcut fires before the focused item sees the key
// unless that item accepts the ShortcutOverride (Qt sends it to the focus item and up its parents first), so the menu's
// own Ctrl+, (close, then Preferences) never ran and the menu stayed open beside the sheet
{
  const mcSrc = read("modules/claude/ModelChooser.qml");
  const Qt = { Key_Comma: 0x2c, Key_N: 0x4e, Key_Escape: 0x01000000, Key_Down: 0x01000015, Key_Tab: 0x01000001, Key_Up: 0x01000013,
    Key_Backtab: 0x01000002, Key_PageDown: 0x01000017, Key_PageUp: 0x01000016, Key_Left: 0x01000012, Key_Right: 0x01000014,
    Key_Return: 0x01000004, Key_Enter: 0x01000005, ControlModifier: 0x04000000 };
  const handler = name => { const m = new RegExp(`Keys\\.${name}:\\s*`).exec(mcSrc); return m ? readExpression(mcSrc, m.index + m[0].length).expr : ""; };
  const press = (key, keepShown) => {
    let prefs = 0;
    const mc = { keepShown, allDefaults() { prefs++; }, levels: [], pick: 0, step() {}, use() {}, closed() {} };
    const scope = { mc, Qt, field: { text: "" } };
    const e = { key, modifiers: Qt.ControlModifier, accepted: false };
    const over = handler("onShortcutOverride");
    const claimed = over ? (inScope(scope, "", `return (${over});`)()(e), e.accepted) : false;
    // the window's Shortcut runs unless the key was claimed; the menu's own handler sees it only then
    if (claimed) { e.accepted = false; inScope(scope, "", `return (${handler("onPressed")});`)()(e); }
    return { claimed, prefs };
  };
  const comma = press(Qt.Key_Comma, true), noKeep = press(Qt.Key_Comma, false), ctrlN = press(Qt.Key_N, true);
  check("Ctrl+, in the model menu is the menu's: it goes to its Preferences once, not to the window's Shortcut",
    comma.claimed && comma.prefs === 1, JSON.stringify(comma));
  check("without the keep line (no Preferences there), and for other keys, the window's shortcuts run as before",
    !noKeep.claimed && !ctrlN.claimed, `no keep line ${JSON.stringify(noKeep)}, Ctrl+N ${JSON.stringify(ctrlN)}`);
}

done();
