// A palette section hidden in Settings > Palette & search ("gone from the palette, its shortcut included"): its prefix
// character is then plain text, so ".bashrc" with Symbols off still finds files and apps (services/PaletteSearch.qml's
// own prefixOf(), sectionEnabled(), activeSection and wants(), run under node with the default prefixes).
import { adapterDefaults, inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("services/PaletteSearch.qml");
const prefix = adapterDefaults(read("modules/common/Config.qml")).search.prefix;

function palette(query, sections) {
  const root = { query, live: true, sectionConfig: sections,
    pfxMath: prefix.math, pfxApp: prefix.app, pfxFiles: prefix.files, pfxClipboard: prefix.clipboard,
    pfxDictation: prefix.dictation, pfxEmojis: prefix.emojis, pfxSymbols: prefix.symbols, pfxKeybinds: prefix.keybinds,
    pfxWindows: prefix.windows, pfxAction: prefix.action, pfxCommand: prefix.shellCommand, pfxWeb: prefix.webSearch };
  const scope = { root };
  root.sectionForPrefix = inScope(scope, "", qmlProperty(src, "sectionForPrefix").slice(1, -1))();
  for (const name of ["sectionEnabled", "prefixOf", "bodyOf", "wants"]) {
    const f = qmlFunction(src, name);
    root[name] = inScope(scope, f.params, f.body);
  }
  for (const name of ["activePrefix", "activeSection", "body"])
    Object.defineProperty(root, name, { get: () => inScope(scope, "", `return (${qmlProperty(src, name)});`)() });
  return root;
}

console.log("== a hidden palette section's prefix (services/PaletteSearch.qml)");
{
  const on = palette(".bashrc", { symbols: true });
  check("with Symbols on, '.bashrc' is a symbol search, as before", on.activeSection === "symbols" && on.wants("symbols") && !on.wants("files"));
  const cases = [[".bashrc", "symbols"], ["/usr/bin/foo", "actions"], ["~notes", "files"], ["=1+1", "calculator"], [":smile", "emoji"]];
  const wrong = cases.map(([q, key]) => {
    const p = palette(q, { [key]: false });
    const other = key === "files" ? "apps" : "files";
    return p.activePrefix === "" && p.body === q && p.wants(other) && !p.wants(key) ? null
      : `${q} with ${key} off: prefix "${p.activePrefix}", section "${p.activeSection}", ${other} ${p.wants(other) ? "built" : "not built"}`;
  }).filter(Boolean);
  check("with its section off, the prefix is plain text: the other sections search the whole query", wrong.length === 0, wrong.join("; "));
}
done();
