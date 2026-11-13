// Settings > Palette & search's two text rows and what they set: "Look in" (services/PaletteFiles.qml searchRoot), where
// a leading ~ is the home folder, and "Web search address" (tacit-settings.qml), which an empty entry does not clear, as
// the palette's web search adds the words to it as they are (PaletteSearch.qml). Both run under node.
import { inScope, qmlProperty, readExpression } from "./lib/qml.mjs";
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
done();
