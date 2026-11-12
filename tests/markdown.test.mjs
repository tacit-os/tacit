// Praxis's markdown (modules/claude/Markdown.js) run under node: a link whose label is code, as agents write file
// links ([`Composer.qml`](modules/claude/Composer.qml)), threw, and the whole text of the reply was drawn empty.
import { check, done, read } from "./lib/check.mjs";

const md = new Function(`${read("modules/claude/Markdown.js").replace(/^\.pragma library/m, "")}\nreturn { toHtml };`)();
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
done();
