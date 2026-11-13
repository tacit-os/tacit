// Praxis's markdown (modules/claude/Markdown.js) run under node: a link whose label is code, as agents write file
// links ([`Composer.qml`](modules/claude/Composer.qml)), threw, and the whole text of the reply was drawn empty.
import { check, done, read } from "./lib/check.mjs";

const md = new Function(`${read("modules/claude/Markdown.js").replace(/^\.pragma library/m, "")}\nreturn { toHtml, plain };`)();
const t = { text: "#t", strong: "#s", dim: "#d", link: "#l", code: "#c", codeBg: "#b", rule: "#r", mono: "Mono", codeSize: 14, lh: 125, gap: 14, h1: 22, h2: 19, h3: 17 };
const html = s => { try { return md.toHtml(s, t); } catch (e) { return `threw: ${e.message}`; } };
const code = c => `font-family:'Mono'; font-size:14px; color:#c; background-color:#b">&#8201;${c}`;

console.log("Praxis's markdown (modules/claude/Markdown.js)");
{
  const h = html("See [`Composer.qml`](modules/claude/Composer.qml) now");
  check("a link whose label is code: the label drawn as code inside the link",
    /<a href="modules\/claude\/Composer\.qml"[^>]*><span style="[^"]*">&#8201;Composer\.qml&#8201;<\/span><\/a> now/.test(h), h);
}
{
  const h = html("Run `make` in [the `tests` folder](tests/) and `qs`.");
  check("code outside a link and inside its label: each span keeps its own text",
    h.includes(code("make")) && h.includes(`the <span style="${code("tests")}`) && h.includes(code("qs")), h);
}
{
  const h = html("- [`a.qml`](a.qml)\n- [**b**](b)\n\n| file |\n|---|\n| [`c.js`](c.js) |");
  check("in a list and a table, and a bold label as before",
    h.includes(code("a.qml")) && h.includes('font-weight:600; color:#s">b</span></a>') && h.includes(code("c.js")), h);
}
// later-praxis-2 [9] a heading's closing run of # was cut with no space before it: "## Learning C#" read "Learning C"
{
  const heads = ["## Learning C#", "### Migrating to F#", "## Done ##", "# Plan #  "].map(s => (html(s).match(/font-weight:600; color:#s">(.*?)<\/p>/) ?? [])[1]);
  check("a heading ending in # keeps it; a closing run after a space still goes",
    JSON.stringify(heads) === JSON.stringify(["Learning C#", "Migrating to F#", "Done", "Plan"]), JSON.stringify(heads));
}

// later-praxis-2 [10] numbered steps were counted from 1 whatever number they started at: a reply's text is converted a
// piece at a time between code blocks, so "3. Start it" after a fence read "1."
{
  const marks = s => [...html(s).matchAll(/color:#d"><p[^>]*>([^<]*)<\/p>/g)].map(m => m[1]);
  const got = [marks("3. Start it\n4. Open the page"), marks("1. a\n1. b\n1. c"), marks("5. five\n   1. sub\n   2. sub\n6. six")];
  check("an ordered list counts on from the number it starts at; one written all 1. counts 1, 2, 3",
    JSON.stringify(got) === JSON.stringify([["3.", "4."], ["1.", "2.", "3."], ["5.", "1.", "2.", "6."]]), JSON.stringify(got));
}

// later-praxis-2 [11] your own message is drawn as rich text, which folds runs of spaces and drops a line's leading ones:
// pasted YAML or a stack trace read flush left
{
  const p = md.plain("server:\n    port:  8080\n\tat Main.run(Main.java:12)");
  check("your own message keeps its indentation and runs of spaces: drawn with white-space:pre-wrap, the text as typed",
    /^<span style="white-space:pre-wrap">[^]*<\/span>$/.test(p) && p.includes("<br/>    port:  8080<br/>\tat Main.run"), p);
}

done();
