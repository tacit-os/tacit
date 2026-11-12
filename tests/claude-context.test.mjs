// What bin/claude-context gives Claude about the focused window, run under sh with a pretend hyprctl first on PATH and
// a home of its own: a private browser window's title never goes out, whatever the browser and its language.
import { execFileSync } from "child_process";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== the focused window's title for Claude (bin/claude-context)");
const tmp = mkdtempSync(join(tmpdir(), "tacit-context-"));
try {
  const bin = join(tmp, "bin"), apps = join(tmp, "share", "applications");
  mkdirSync(bin); mkdirSync(apps, { recursive: true });
  writeFileSync(join(bin, "hyprctl"), '#!/bin/sh\nprintf %s "$WINDOW"\n');
  writeFileSync(join(bin, "focus-folder"), "#!/bin/sh\necho /tmp\n");
  for (const f of ["hyprctl", "focus-folder"]) chmodSync(join(bin, f), 0o755);
  // a browser whose class says nothing: only its launcher says what it is
  writeFileSync(join(apps, "org.example.Surf.desktop"), "[Desktop Entry]\nName=Surf\nExec=surf\nCategories=Network;WebBrowser;\n");
  writeFileSync(join(apps, "org.example.Notes.desktop"), "[Desktop Entry]\nName=Notes\nExec=notes\nCategories=Utility;\n");
  const title = (cls, t) => JSON.parse(execFileSync("sh", [join(tree, "bin/claude-context")], { encoding: "utf8", env: {
    PATH: `${bin}:${process.env.PATH}`, HOME: tmp, XDG_DATA_HOME: join(tmp, "share"), XDG_DATA_DIRS: join(tmp, "none"),
    TACIT_BIN: bin, TACIT_SHELL: tmp, WINDOW: JSON.stringify({ class: cls, title: t, pid: 1 }) } })).title;

  for (const [cls, t] of [
    ["microsoft-edge", "Bank statement - [InPrivate] - Microsoft​ Edge"],
    ["librewolf", "Kontoauszug — LibreWolf Privater Modus"],
    ["floorp", "Relevé — Floorp Navigation privée"],
    ["firefox-developer-edition", "Konto — Firefox Developer Edition (Privater Modus)"],
    ["org.example.Surf", "Bank statement"],
    ["firefox", "Konto — Mozilla Firefox (Privater Modus)"],
    ["google-chrome", "Página - Google Chrome (Incógnito)"],
    ["browser-cef", "Private · Bank statement"],
  ]) check(`a private ${cls} window gives no title`, title(cls, t) === "", `gave "${title(cls, t)}"`);

  for (const [cls, t] of [
    ["firefox", "Release notes — Mozilla Firefox"],
    ["browser", "Release notes · Tacit"],
    ["foot", "~/dev/tacit"],
    ["org.example.Notes", "groceries.txt"],
  ]) check(`a ${cls} window keeps its title`, title(cls, t) === t, `gave "${title(cls, t)}"`);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
