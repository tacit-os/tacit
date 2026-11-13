// Settings > Palette & search's two text rows and what they set: "Look in" (services/PaletteFiles.qml searchRoot), where
// a leading ~ is the home folder, and which says "No such folder" for one that is not there (its own check, run under
// bash on folders of the test's own), and "Web search address" (tacit-settings.qml), which an empty entry does not clear,
// whose description gives an example with %s where the words go, as the palette's web search puts them there or at the
// end (PaletteSearch.qml). The rest runs under node.
import { spawnSync } from "child_process";
import { mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlProperty, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the palette's Look in and Web search address (PaletteFiles.qml, tacit-settings.qml)");
{
  const e = qmlProperty(read("services/PaletteFiles.qml"), "searchRoot");
  const root = set => inScope({
    Config: { options: { commandPalette: { files: { root: set } } } },
    Directories: { home: "file:///home/someone" },
    FileUtils: { trimFileProtocol: s => (String(s).startsWith("file://") ? String(s).slice(7) : String(s)) },
  }, "", e.slice(1, -1))();
  const cases = [["~/Documents", "/home/someone/Documents"], ["~", "/home/someone"], ["", "/home/someone"],
    ["/data/work", "/data/work"], ["file:///data/work", "/data/work"]];
  const wrong = cases.filter(([set, want]) => root(set) !== want).map(([set, want]) => `${JSON.stringify(set)} gave ${root(set)}, not ${want}`);
  check("Look in: ~/Documents and ~ are in the home folder, a full path is itself, nothing is the home folder", wrong.length === 0, wrong.join("; "));
}
{
  const app = read("tacit-settings.qml");
  const at = app.indexOf("onCommitted:", app.indexOf('label: "Web search address"'));
  const handler = readExpression(app, at + "onCommitted:".length).expr;
  const commit = value => {
    const search = { engineBaseUrl: "https://duckduckgo.com/?q=" };
    let reverted = false;
    const row = { revert() { reverted = true; } };
    inScope({ Config: { options: { search } }, engineRow: row }, "", `return (${handler});`)()(value);
    return { url: search.engineBaseUrl, reverted };
  };
  const emptied = commit("");
  check("Web search address emptied: the address stays and the field shows it again", emptied.url === "https://duckduckgo.com/?q=" && emptied.reverted,
    JSON.stringify(emptied));
  check("another address is taken", commit("https://www.startpage.com/do/search?q=").url === "https://www.startpage.com/do/search?q=");
}
{
  const app = read("tacit-settings.qml");
  const row = objectWith(app, 'label: "Look in"');
  const expr = name => { const m = new RegExp(`\\n\\s*${name}:`).exec(row); return m ? readExpression(row, m.index + m[0].length).expr : null; };
  const command = expr("command"), exited = expr("onExited"), description = expr("description");
  check("Look in checks the folder the palette searches", command !== null && command.includes("PaletteFiles.searchRoot"), command ?? "no check");
  if (command && exited && description) {
    const home = mkdtempSync(join(tmpdir(), "look-in-"));
    try {
      const says = folder => {
        const argv = inScope({ PaletteFiles: { searchRoot: folder } }, "", `return (${command});`)();
        const lookIn = { missing: false };
        inScope({ lookIn }, "", `return (${exited});`)()(spawnSync(argv[0], argv.slice(1)).status);
        return inScope({ lookIn }, "", `return (${description});`)();
      };
      check('a folder that is there says nothing', says(home) === "", says(home));
      check('one that is not says "No such folder"', says(join(home, "Documents")) === "No such folder", says(join(home, "Documents")));
    } finally {
      rmSync(home, { recursive: true, force: true });
    }
    check("and it looks again when the folder set changes", /onSearchRootChanged\(\)\s*\{\s*lookInCheck\.running = true/.test(row));
  }
  const engine = objectWith(app, 'label: "Web search address"');
  check("Web search address's description gives the example https://duckduckgo.com/?q=%s",
    /description:\s*"[^"]*https:\/\/duckduckgo\.com\/\?q=%s/.test(engine));

  const palette = read("services/PaletteSearch.qml");
  const at = palette.indexOf("execute:", palette.indexOf("type: root.sectionTitles.web"));
  const execute = readExpression(palette, at + "execute:".length).expr;
  const opened = url => {
    const got = [];
    inScope({ Config: { options: { search: { engineBaseUrl: url, excludedSites: [] } } }, Qt: { openUrlExternally: u => got.push(u) },
      terms: "café au lait" }, "", `return (${execute});`)()();
    return got[0];
  };
  check("the example's %s takes the words", opened("https://duckduckgo.com/?q=%s") === "https://duckduckgo.com/?q=caf%C3%A9%20au%20lait",
    opened("https://duckduckgo.com/?q=%s"));
  check("and an address with no %s still has them at its end", opened("https://www.google.com/search?q=") === "https://www.google.com/search?q=caf%C3%A9%20au%20lait",
    opened("https://www.google.com/search?q="));
}
done();
