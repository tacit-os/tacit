// Praxis's permission, question and choose cards (modules/claude/*Card.qml): what they answer to and what they show
// before the person says yes. Their own expressions run under node; the rest is read from the QML.
import { inScope, matchBrace, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const perm = read("modules/claude/PermissionCard.qml");
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

// The composer keeps the keyboard while a card is up and sends on Enter with Ctrl too: a card's key must be one a
// reply is never typed or sent with. 7657c6c chose Alt chords; the 1.2.14 merge put back Ctrl+Enter for Allow once.
{
  const keys = [];
  for (const tool of ["Bash", "Edit", "Door", "Wall"])
    for (const b of cardValue("buttons", { tool, input: {}, suggestions: [{}] })) for (const k of b.keys ?? []) keys.push(`${tool} ${b.label}: ${k}`);
  for (const f of ["QuestionCard", "ChooseCard"]) {
    const src = read(`modules/claude/${f}.qml`);
    for (const m of src.matchAll(/\bsequences?:\s*(\[[^\]\n]*\]|"[^"\n]*"|`[^`\n]*`)/g))
      for (const k of [].concat(inScope({ index: 0, row: { index: 0 }, opt: { index: 0 } }, "", `return (${m[1]});`)())) keys.push(`${f}: ${k}`);
  }
  const bad = keys.filter(k => !/: Alt\+/.test(k));
  check(`every key that answers a card is an Alt chord (${keys.length} keys)`, keys.length > 10 && !bad.length, bad.join(", "));
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
done();
