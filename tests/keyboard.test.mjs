// The keyboard layout an updated computer types with, and the one Settings' Layout row writes. Config.migrate() is run
// under node on 1.2.13's settings file, and the command it starts is run by bash on a pretend shellOverrides/main.lua
// and /etc/vconsole.conf, with the tree's own hyprconfigurator.py and a pretend hyprctl first on PATH; the row's own
// bindings are run under node on the layouts Hyprland reports.
import { spawnSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { adapterDefaults, inScope, loadInto, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

const releases = join(dirname(fileURLToPath(import.meta.url)), "config", "releases");
const index = JSON.parse(readFileSync(join(releases, "index.json"), "utf8"));
const file1213 = JSON.parse(readFileSync(join(releases, index.find(e => e.version === "1.2.13").file), "utf8"));

const config = read("modules/common/Config.qml");
const defaults = adapterDefaults(config);
const trim = qmlFunction(read("modules/common/functions/FileUtils.qml"), "trimFileProtocol");
const FileUtils = { trimFileProtocol: inScope({}, trim.params, trim.body) };
const version = +(config.match(/currentConfigVersion:\s*(\d+)/)?.[1] ?? 0);

const OLD_LINE = 'hl.config({ input = { kb_layout = "us" } })';
const NUMLOCK = "hl.config({ input = { numlock_by_default = true } })";

console.log("The keyboard layout after the update (modules/common/Config.qml)");

// A settings file as it comes to migrate(), the overrides file and vconsole.conf as given: what the overrides file holds
// afterwards, and whether Hyprland was told to reload.
function update(settings, overrides, vconsole) {
  const dir = mkdtempSync(join(tmpdir(), "tacit-keyboard-"));
  try {
    const main = join(dir, "config", "hypr", "hyprland", "shellOverrides", "main.lua");
    mkdirSync(dirname(main), { recursive: true });
    if (overrides !== null) writeFileSync(main, overrides);
    writeFileSync(join(dir, "vconsole.conf"), vconsole);
    const bin = join(dir, "bin");
    mkdirSync(bin);
    writeFileSync(join(bin, "hyprctl"), `#!/bin/bash\necho "$*" >> "${join(dir, "hyprctl.log")}"\n`);
    chmodSync(join(bin, "hyprctl"), 0o755);

    const started = [];
    const Quickshell = { execDetached: args => started.push(args), shellPath: p => join(tree, p) };
    const Directories = { config: `file://${join(dir, "config")}` };
    const root = { options: loadInto(defaults, settings), currentConfigVersion: version, writeNow() {} };
    const m = qmlFunction(config, "migrate");
    inScope({ root, Quickshell, Directories, FileUtils }, m.params, m.body)();
    for (const args of started.filter(a => a[0] === "bash"))
      spawnSync("bash", args.slice(1).map(a => (a === "/etc/vconsole.conf" ? join(dir, "vconsole.conf") : a)),
        { env: { ...process.env, PATH: `${bin}:${process.env.PATH}` }, stdio: "pipe" });
    return {
      kbLayout: root.options.hyprland.input.kbLayout,
      overrides: existsSync(main) ? readFileSync(main, "utf8") : null,
      reloaded: existsSync(join(dir, "hyprctl.log")) && readFileSync(join(dir, "hyprctl.log"), "utf8").includes("reload"),
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
const says = r => `kbLayout ${JSON.stringify(r.kbLayout)}, main.lua ${JSON.stringify(r.overrides)}, reloaded ${r.reloaded}`;

// installed with German, and the old Settings > Hyprland page opened once: its "us" written over the layout
{
  const r = update(structuredClone(file1213), `${NUMLOCK}\n${OLD_LINE}\n`, "KEYMAP=de-latin1\nXKBLAYOUT=de\n");
  check("installed with German: the old page's US line goes, the rest stays, and Hyprland reloads",
    r.kbLayout === "" && r.overrides === `${NUMLOCK}\n` && r.reloaded, says(r));
}
// installed with Russian: Setup's pair comes back
{
  const r = update(structuredClone(file1213), `${OLD_LINE}\n`, "XKBLAYOUT=us,ru\nXKBOPTIONS=grp:alt_shift_toggle\n");
  check("installed with US + Russian: the US line goes, so the pair is back", r.overrides === "" && r.reloaded, says(r));
}
// installed with US: the line changes nothing, so it stays and nothing reloads
{
  const r = update(structuredClone(file1213), `${OLD_LINE}\n`, 'XKBLAYOUT="us"\n');
  check("installed with US: the file is left as it is", r.overrides === `${OLD_LINE}\n` && !r.reloaded, says(r));
}
// a layout chosen in Settings is not the old page's line
{
  const r = update(structuredClone(file1213), 'hl.config({ input = { kb_layout = "fr" } })\n', "XKBLAYOUT=de\n");
  check("a French layout chosen in Settings stays", r.overrides === 'hl.config({ input = { kb_layout = "fr" } })\n' && !r.reloaded, says(r));
}
// no overrides file, no vconsole layout: nothing to do and nothing fails
{
  const r = update(structuredClone(file1213), null, "KEYMAP=us\n");
  check("no overrides file: none is made", r.overrides === null && !r.reloaded, says(r));
}
// "us" chosen after the migration ran is the person's
{
  const now = structuredClone(file1213);
  now.configVersion = version;
  const r = update(now, `${OLD_LINE}\n`, "XKBLAYOUT=de\n");
  check(`US chosen in a version ${version} file stays`, r.kbLayout === "us" && r.overrides === `${OLD_LINE}\n` && !r.reloaded, says(r));
}

// Settings > Keyboard & touchpad > Layout, on the layouts Hyprland reports: the layout the row names, and what a pick writes
const settings = read("tacit-settings.qml");
const row = settings.indexOf("id: layoutRow");
const binding = key => {
  const k = settings.indexOf(`${key}:`, row);
  return readExpression(settings, k + key.length + 1).expr;
};
const ui = { nonLatinLayouts: inScope({}, "", `return (${qmlProperty(settings, "nonLatinLayouts") ?? "[]"});`)() };
for (const name of ["typedLayout", "pickLayout"]) {
  const f = qmlFunction(settings, name);
  if (f) ui[name] = inScope({ root: ui }, f.params, f.body);
}
function layoutRow(reported, pick) {
  const wrote = {};
  const scope = { root: ui, layoutRow: { codes: reported.split(",") }, inputCol: { liveLayout: reported },
    Config: { options: { hyprland: { input: { kbLayout: "" } } } },
    HyprlandConfig: { set: (k, v) => (wrote[k] = String(v)), setMany: e => Object.keys(e).forEach(k => (wrote[k] = String(e[k]))) } };
  const named = inScope(scope, "", `return (${binding("current")});`)();
  if (pick) inScope(scope, "", `return (${binding("onPicked")});`)()(pick);
  return { named, layout: wrote["input:kb_layout"], options: wrote["input:kb_options"], saved: scope.Config.options.hyprland.input.kbLayout };
}
const rowSays = r => `names ${JSON.stringify(r.named)}, writes ${JSON.stringify(r.layout)}${r.options ? ` with ${r.options}` : ""}`;

{
  const r = layoutRow("us,ru");
  check("a US + Russian install: the row names Russian, the layout typed in", r.named === "ru", rowSays(r));
}
{
  const r = layoutRow("us,ru", "ru");
  check("a US + Russian install picking Russian keeps US first", r.layout === "us,ru" && r.saved === "us,ru", rowSays(r));
}
{
  const r = layoutRow("us,ru", "de");
  check("a US + Russian install picking German types German", r.layout === "de", rowSays(r));
}
{
  const r = layoutRow("de", "ru");
  check("a German install picking Russian gets US first and Alt + Shift, as Setup gives",
    r.layout === "us,ru" && r.options === "grp:alt_shift_toggle", rowSays(r));
}
{
  const r = layoutRow("us", "fr");
  check("a US install picking French gets French, nothing else written", r.layout === "fr" && r.options === undefined, rowSays(r));
}
{
  const r = layoutRow("de,fr", "es");
  check("German then French, picking Spanish: Spanish then French", r.layout === "es,fr", rowSays(r));
}
{
  const setupd = read("scripts/setup/setupd.py").match(/NON_LATIN = \{([^}]*)\}/)?.[1] ?? "";
  const theirs = [...setupd.matchAll(/"([a-z]+)"/g)].map(m => m[1]).sort();
  const ours = [...ui.nonLatinLayouts].sort();
  check("Settings' non-Latin layouts are Setup's", theirs.length > 0 && JSON.stringify(theirs) === JSON.stringify(ours),
    `Setup ${theirs.length}, Settings ${ours.length}`);
}

done();
