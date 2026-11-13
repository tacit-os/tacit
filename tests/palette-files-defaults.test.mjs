// What the palette's file search walks and skips (services/PaletteFiles.qml), from the settings a new install writes and
// an updated computer's file comes out of Config.migrate() with (modules/common/Config.qml, tests/config/releases). The
// search was written for depth 8, 12 results and a list of build and cache folders to skip; those must be what it uses.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { adapterDefaults, inScope, loadInto, qmlProperty, runMigrate } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== what the palette's file search walks and skips (PaletteFiles.qml, Config.qml)");
const configSrc = read("modules/common/Config.qml"), filesSrc = read("services/PaletteFiles.qml");
const releases = join(dirname(fileURLToPath(import.meta.url)), "config", "releases");
const releaseFile = v => JSON.parse(readFileSync(join(releases, JSON.parse(readFileSync(join(releases, "index.json"), "utf8")).find(e => e.version === v).file), "utf8"));
const settings = file => runMigrate(configSrc, loadInto(adapterDefaults(configSrc), file)).options;
// what PaletteFiles reads from those settings
const search = options => Object.fromEntries(["maxDepth", "limit", "excludeDirs"].map(name =>
  [name, inScope({ Config: { options } }, "", `return (${qmlProperty(filesSrc, name)});`)()]));
const BUILD = ["build", "dist", "target", "__pycache__", ".venv", "venv"];
const says = s => `depth ${s.maxDepth}, ${s.limit} results, skips ${JSON.stringify(Array.from(s.excludeDirs))}`;

for (const [who, options] of [["a new install", settings({})], ["a computer updated from 1.2.14", settings(releaseFile("1.2.14"))],
  ["a computer updated from 1.2.8", settings(releaseFile("1.2.8"))]]) {
  const s = search(options);
  check(`${who}: the search goes 8 folders deep and keeps the best 12`, s.maxDepth === 8 && s.limit === 12, says(s));
  check(`${who}: it skips build output and Python environments`, BUILD.every(d => Array.from(s.excludeDirs).includes(d)), says(s));
}
{
  const mine = releaseFile("1.2.14");
  mine.commandPalette.files = { ...mine.commandPalette.files, maxDepth: 4, limit: 30, excludeDirs: [".git", "Archive"] };
  const s = search(settings(mine));
  check("values the person wrote into the file are kept", s.maxDepth === 4 && s.limit === 30 && JSON.stringify(Array.from(s.excludeDirs)) === '[".git","Archive"]', says(s));
}
done();
