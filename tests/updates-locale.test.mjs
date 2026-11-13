// The updater's reading of pacman on a German or French system (services/Updates.qml): pacman translates the
// " [ignored]" it puts after a package held back with IgnorePkg ("[Ignoriert]", "[ignoré]"), and the reads leave out
// only the English one. The list read's and the download watch's own commands run by bash, with each Process's own
// environment over LANG=de_DE.UTF-8, and a pretend pacman that translates as pacman does; then the list read's handler.
import { execFileSync } from "child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

const src = read("services/Updates.qml");
const after = (id, key) => {
  const at = src.indexOf(`id: ${id}`), next = src.indexOf("Process {", at);
  const k = src.indexOf(`${key}:`, at);
  return k < 0 || (next > 0 && k > next) ? -1 : k + key.length + 1;
};
const envOf = id => (after(id, "environment") < 0 ? {} : inScope({}, "", `return (${readExpression(src, after(id, "environment")).expr});`)());
const handler = id => { const open = src.indexOf("{", after(id, "onStreamFinished")); return src.slice(open + 1, matchBrace(src, open)); };

console.log("== the updater on a German system (services/Updates.qml)");
const bin = mkdtempSync(join(tmpdir(), "tacit-updates-locale-"));
try {
  writeFileSync(join(bin, "pacman"), `#!/bin/bash
tag='[ignored]'; [ "\${LC_ALL:-}" = C ] || tag='[Ignoriert]'
case "$*" in
  -Qu) [ -n "$ONLY_HELD" ] || printf 'linux 6.17.1.arch1-1 -> 6.17.2.arch1-1\\ntacit 1.2.14-2 -> 1.2.15-1\\n'; printf 'hyprland 0.57.0-1 -> 0.57.1-1 %s\\n' "$tag" ;;
  "-Sup --print-format %l") [ -n "$ONLY_HELD" ] || printf 'file:///var/cache/pacman/pkg/linux-6.17.2.arch1-1-x86_64.pkg.tar.zst\\nfile:///var/cache/pacman/pkg/tacit-1.2.15-1-any.pkg.tar.zst\\n' ;;
  "-Sup --print-format %s %l") printf '%s\\n' '150000000 https://mirror.example/linux-6.17.2.arch1-1-x86_64.pkg.tar.zst' '9000000 file:///var/cache/pacman/pkg/tacit-1.2.15-1-any.pkg.tar.zst' ;;
esac
`);
  writeFileSync(join(bin, "systemctl"), `#!/bin/bash
case "$1" in
  is-active) shift; for u; do [ "$u" = tacit-fetch-updates-now.service ] && echo activating || echo inactive; done ;;
  show) echo success ;;
esac
`);
  for (const n of ["pacman", "systemctl"]) chmodSync(join(bin, n), 0o755);
  const run = (id, cmd, extra = {}) => execFileSync(cmd[0], cmd.slice(1), { encoding: "utf8",
    env: { PATH: `${bin}:${process.env.PATH}`, LANG: "de_DE.UTF-8", ...extra, ...envOf(id) } });

  // the list read, with the check for Tacit's own updater taken as true (this computer may not have it)
  const listCmd = inScope({}, "", `return (${readExpression(src, after("waitingProc", "command")).expr});`)()
    .map(a => a.replace("[ -x /usr/lib/tacit/tacit-update ]", "true"));
  const read1 = extra => {
    const root = { count: 0, downloaded: false, tacitVersion: "", lastCheckFailed: false, fetchFailed: false, lastChecked: 0, tonightSet: false,
      nextNotes: [], nightSkipped: "", nightWords: {}, lastNight: () => ({ why: "", key: "" }), announce() {}, say() {} };
    Object.defineProperty(root, "ready", { get: () => inScope({ root }, "", `return (${qmlProperty(src, "ready")});`)() });
    inScope({ root, stateFile: { setText() {} }, nextNotesProc: {}, nightSeenFile: { text: () => "" } }, "text", handler("waitingProc"))(run("waitingProc", listCmd, extra));
    return root;
  };
  const mixed = read1();
  check("two waiting and hyprland held back: two counted, and they are ready", mixed.count === 2 && mixed.ready, `count ${mixed.count}, ready ${mixed.ready}`);
  const held = read1({ ONLY_HELD: "1" });
  check("only hyprland held back: nothing waits, rather than '1 update to download' for good", held.count === 0, `count ${held.count}`);

  const watchCmd = inScope({ full: true }, "", `return (${readExpression(src, after("watchProc", "command")).expr});`)();
  const waiting = run("watchProc", watchCmd).split("\n").find(l => l.startsWith("waiting "));
  check("the download watch counts the two, not the held one", waiting === "waiting 2", waiting);
} finally {
  rmSync(bin, { recursive: true, force: true });
}
done();
