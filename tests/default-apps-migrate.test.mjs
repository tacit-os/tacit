// Default apps chosen before 1.2.15, brought up to date once: Config.qml's migrate() run under node on a 1.2.14 settings
// file (version 5) and on one already at this version, with a pretend Quickshell.execDetached, and what it starts,
// scripts/settings/default_apps.py migrate, under python3 in a home of its own whose mimeapps.list holds the choices
// the old `set` wrote (a role's first few types), with a pretend xdg-mime that writes down what it is asked to set.
import { execFileSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== old default-app choices cover every type of their kind, once (Config.qml migrate, default_apps.py migrate)");

// ---- the settings migration starts it once, for a file from before this version
const config = read("modules/common/Config.qml");
const version = +(config.match(/currentConfigVersion:\s*(\d+)/)?.[1] ?? 0);
const migrate = qmlFunction(config, "migrate");
const started = from => {
  const calls = [];
  const options = { configVersion: from, sidebar: { cornerOpen: {} },
    background: { widgets: { calendar: {}, notes: {}, todo: {}, media: {}, visualizer: {} } }, appearance: { transparency: { enable: true } }, dock: { pinnedApps: [] },
    audio: { protection: {} }, hyprland: { input: {} }, commandPalette: { files: {} } };
  const root = { options, currentConfigVersion: version, writeNow() {} };
  inScope({ root, Quickshell: { execDetached: c => calls.push(c), shellPath: p => `<shell>/${p}` }, Directories: { config: "<config>" }, FileUtils: { trimFileProtocol: p => p } },
    migrate.params, migrate.body)();
  return { calls: calls.filter(c => c.some(a => /default_apps\.py/.test(a))), version: options.configVersion };
};
{
  const old = started(5), now = started(version);
  check("a 1.2.14 settings file starts default_apps.py migrate once, and is marked with the new version",
    version > 5 && old.calls.length === 1 && old.calls[0].includes("<shell>/scripts/settings/default_apps.py") && old.calls[0].at(-1) === "migrate" && old.version === version,
    `version ${version}; it started ${JSON.stringify(old.calls)}`);
  check("a file already at this version starts nothing", now.calls.length === 0, JSON.stringify(now.calls));
}

// ---- what it starts
const tmp = mkdtempSync(join(tmpdir(), "tacit-default-apps-migrate-"));
try {
  const bin = join(tmp, "bin"), apps = join(tmp, "data/applications"), conf = join(tmp, "config"), set = join(tmp, "set");
  for (const d of [bin, apps, conf, join(tmp, "none")]) mkdirSync(d, { recursive: true });
  writeFileSync(join(bin, "xdg-mime"), `#!/bin/bash\n[ "$1" = default ] && { shift; echo "$*" >> "$SET"; }\nexit 0\n`);
  chmodSync(join(bin, "xdg-mime"), 0o755);
  for (const [id, mime] of [["other-images", "image/png"], ["gimp", "image/tiff"], ["other-text", "text/plain"]])
    writeFileSync(join(apps, `${id}.desktop`), `[Desktop Entry]\nType=Application\nName=${id}\nExec=${id} %f\nMimeType=${mime};\n`);
  // what 1.2.14's set wrote for Images and Text, a .tiff given to GIMP by hand, and a music player since removed
  writeFileSync(join(conf, "mimeapps.list"), ["[Added Associations]", "video/mp4=other-images.desktop;", "", "[Default Applications]",
    ...["image/png", "image/jpeg", "image/webp", "image/gif"].map(m => `${m}=other-images.desktop`), "image/tiff=gimp.desktop;",
    "text/plain=other-text.desktop;", ...["audio/mpeg", "audio/flac", "audio/ogg"].map(m => `${m}=gone.desktop`), ""].join("\n"));
  let code = 0;
  try {
    execFileSync("python3", ["-I", join(tree, "scripts/settings/default_apps.py"), "migrate"], { stdio: "pipe", env: {
      PATH: `${bin}:${process.env.PATH}`, HOME: join(tmp, "home"), XDG_CONFIG_HOME: conf, XDG_DATA_HOME: join(tmp, "data"), XDG_DATA_DIRS: join(tmp, "none"), SET: set } });
  } catch (e) {
    code = e.status;
  }
  const calls = existsSync(set) ? readFileSync(set, "utf8").trim().split("\n").filter(Boolean) : [];
  const forApp = id => calls.filter(c => c.startsWith(`${id} `)).flatMap(c => c.split(" ").slice(1));
  const images = forApp("other-images.desktop"), text = forApp("other-text.desktop");
  check("Images chosen before: the chosen app gets .bmp, .svg and .ico too, and the .tiff set by hand stays GIMP's",
    code === 0 && ["image/bmp", "image/svg+xml", "image/x-icon"].every(m => images.includes(m)) && !images.includes("image/tiff") && !images.includes("image/png")
      && forApp("gimp.desktop").length === 0, `exit ${code}; it set ${JSON.stringify(calls)}`);
  check("Text chosen before: Markdown, JSON, Python and the rest go to it as well", ["text/markdown", "application/json", "text/x-python", "text/x-shellscript"].every(m => text.includes(m)),
    JSON.stringify(text));
  check("a kind never chosen (video) and an app since removed (music) are left alone", forApp("gone.desktop").length === 0
    && !calls.some(c => /video\//.test(c)), JSON.stringify(calls));
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
