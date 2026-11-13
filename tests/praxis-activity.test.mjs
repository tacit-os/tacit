// How Praxis draws an agent's steps (modules/claude/ActivityGroup.qml, ThinkingLine.qml, ActivityWords.js): the step
// lines' words and what their text is drawn as. The words' own code runs under node; the rest is read from the QML.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

// the QML item whose own lines hold the index at: { type, text } (text braces and all)
function itemAt(src, at) {
  for (let i = at, depth = 0; i >= 0; i--) {
    if (src[i] === "}") depth++;
    else if (src[i] === "{" && depth-- === 0) return { type: src.slice(0, i).match(/(\w+)\s*$/)?.[1] ?? "", text: src.slice(i, matchBrace(src, i) + 1) };
  }
  return { type: "", text: "" };
}
const itemWith = (src, line) => (src.includes(line) ? itemAt(src, src.indexOf(line)) : { type: "", text: "" });

console.log("How Praxis draws an agent's steps (modules/claude/ActivityGroup.qml, ThinkingLine.qml, ActivityWords.js)");

// later-praxis-1 [4] a Text's default (AutoText) draws a line that starts with a known tag as rich text: the live step's
// command (grep -rn "<h1>" .) became a heading that spilled over the rows around, and a thought starting with <div> lost it
{
  const group = read("modules/claude/ActivityGroup.qml"), think = read("modules/claude/ThinkingLine.qml");
  const texts = [["the running step's command", itemWith(group, "lineCol.now.desc ?? lineCol.now.summary")],
    ["a thought's first words", itemWith(think, 'text: think.text.replace(/\\s+/g, " ").trim()')],
    ["a thought opened whole", itemWith(think, 'text: think.shown ? think.text : ""')]];
  const rich = texts.filter(([, it]) => !/\btextFormat:\s*Text\.PlainText\b/.test(it.text)).map(([name, it]) => `${name} (${it.type || "not found"})`);
  check("the running step's command and a thought, folded or open, are drawn as plain text", !rich.length, `rich text: ${rich.join(", ")}`);
}

// later-praxis-1 [5] the host marks every file a Write gives "write" from the tool's name alone, and the activity line
// and the turn's changes card said "Created" for a config.json the agent wrote over
{
  const Words = new Function(`${read("modules/claude/ActivityWords.js")}\nreturn { says, changed, kindOver, fileKind: typeof fileKind === "function" ? fileKind : undefined };`)();
  const conv = { busy: false, blocksOf: t => [{ type: "text", content: t }] };
  const build = qmlFunction(read("modules/claude/Conversation.qml"), "build");
  const write = (id, path, result) => ({ role: "assistant", kind: "tool", tool: "Write", id, ts: 2, result, files: [{ path, add: 10, del: 0, kind: "write" }] });
  const over = write("w1", "/p/config.json", "The file /p/config.json has been updated successfully.");
  const made = write("w2", "/p/NOTES.md", "File created successfully at: /p/NOTES.md");
  // Codex's apply_patch that only adds files is a Write too (agent-host), its result Codex's own
  const codex = write("c1", "/p/new.txt", "Success. Updated the following files:\nA /p/new.txt");
  const card = steps => {
    const blocks = inScope({ conv, Words }, build.params, build.body)([{ role: "user", kind: "text", text: "rewrite the config", ts: 1 }, ...steps,
      { role: "assistant", kind: "text", text: "Done.", ts: 4 }]);
    const c = blocks.find(b => b.type === "changes");
    return c ? `${Words.changed(c.files)} ${c.files.length}` : "no card";
  };
  const lines = [Words.says("edit", [over]), Words.says("edit", [made]), Words.says("edit", [codex])];
  check("a file written over reads Edited; one Claude Code says it created, or Codex added, reads Created",
    JSON.stringify(lines) === '["Edited config.json","Created NOTES.md","Created new.txt"]', JSON.stringify(lines));
  check("and the turn's changes card is headed the same way", card([over]) === "Edited 1" && card([over, made]) === "Changed 2" && card([made]) === "Created 1",
    `written over: ${card([over])}, both: ${card([over, made])}, made: ${card([made])}`);
}

done();
