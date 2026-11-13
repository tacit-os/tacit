// Praxis's message box and what stands over it (modules/claude/Composer.qml, QuestionCard.qml, Conversation.qml): a
// pasted picture, the attachments, a half-answered question. The files' own code runs under node and bash.
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

done();
