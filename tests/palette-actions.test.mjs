// The palette's Actions rows (services/PaletteSearch.qml actionEntries), run under node over LauncherSearch's own
// action words and names: typed with the "/" prefix (/todo milk) or by name with no prefix ("clipboard").
import { inScope, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("services/PaletteSearch.qml");
const actions = [...read("services/LauncherSearch.qml").matchAll(/action: "(\w+)",\s*label: Translation\.tr\("([^"]+)"\)/g)]
  .map(([, action, label]) => ({ action, label }));

function rows(query) {
  const prefixed = query.startsWith("/");
  const root = { live: true, query, pfxAction: "/", activeSection: prefixed ? "actions" : "", body: prefixed ? query.slice(1) : query,
    sectionLimit: prefixed ? 40 : 8, sectionTitles: { actions: "Actions" }, wants: () => true };
  return inScope({ root, LauncherSearch: { allActions: actions }, resultComp: { createObject: (p, props) => props },
    Translation: { tr: s => s } }, "", qmlProperty(src, "actionEntries").slice(1, -1))().map(r => r.name);
}

console.log("== the palette's Actions rows (services/PaletteSearch.qml)");
check("LauncherSearch's actions are read", actions.some(a => a.label === "Clear clipboard history") && actions.length >= 5, JSON.stringify(actions));
const cases = [["clipboard", ["Clear clipboard history"]], ["paste", ["Paste several"]], ["add", ["Add a to-do"]],
  ["t", ["Add a to-do"]], ["x", []], ["/todo milk", ["Add a to-do"]], ["/clip", ["Clear clipboard history"]]];
const wrong = cases.filter(([q, want]) => JSON.stringify(rows(q)) !== JSON.stringify(want)).map(([q, want]) => `"${q}" gave ${JSON.stringify(rows(q))}, not ${JSON.stringify(want)}`);
check("a name typed without the prefix finds its action, from its first letter, and a letter no name has finds none", wrong.length === 0, wrong.join("; "));
check("'/' alone still lists every action", rows("/").length === actions.length, JSON.stringify(rows("/")));
done();
