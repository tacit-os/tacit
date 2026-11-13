// An emoji picked in the palette (services/Emojis.qml insert()): the command the file runs, under bash, with a pretend
// compositor (hyprctl or niri), wtype and notify-send first on PATH, so nothing is typed into this computer. With a window
// focused, the pick is typed into it on either compositor; with none, it is copied and the notice says so.
import { execFileSync } from "child_process";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== an emoji picked in the palette, on Hyprland and on niri (Emojis.qml)");
const src = read("services/Emojis.qml");
const sq = qmlFunction(read("modules/common/functions/StringUtils.qml"), "shellSingleQuoteEscape");
const StringUtils = { shellSingleQuoteEscape: inScope({}, sq.params, sq.body) };
const f = qmlFunction(src, "insert");

const work = mkdtempSync(join(tmpdir(), "emoji-insert-"));
// focused: a window holds the keyboard; compositor: the one running (the other's command fails as it would)
function pick(compositor, focused) {
  const bin = join(work, `${compositor}-${focused}`), log = join(bin, "log");
  mkdirSync(bin, { recursive: true });
  const tool = (name, body) => writeFileSync(join(bin, name), `#!/bin/bash\n${body}\n`, { mode: 0o755 });
  tool("hyprctl", compositor === "hyprland"
    ? `case "$1" in layers) echo 'Layer 0x1: namespace: quickshell:bar' ;; activewindow) ${focused ? `echo '{"address":"0x5a1"}'` : "echo '{}'"} ;; esac`
    : `echo "HYPRLAND_INSTANCE_SIGNATURE not set! (is hyprland running?)" >&2; exit 1`);
  tool("niri", compositor === "niri"
    ? `[ "$1 $2" = "msg layers" ] && { echo 'Surface: namespace "quickshell:bar"'; exit 0; }; [ "$1 $2 $3" = "msg -j focused-window" ] && ${focused ? `echo '{"id":12,"app_id":"foot"}'` : "echo null"}`
    : `echo "Error: NIRI_SOCKET is not set" >&2; exit 1`);
  tool("wtype", `printf 'typed %s\\n' "$2" >> "${log}"`);
  tool("notify-send", `printf 'notice %s\\n' "$2" >> "${log}"`);
  let cmd = null;
  const scope = { Quickshell: { set clipboardText(v) {}, execDetached: c => { cmd = c; } }, StringUtils, Translation: { tr: s => s },
    WM: { compositor } };
  inScope(scope, f.params.replace(/:\s*\w+/g, ""), f.body)("🙂");   // a typed parameter (glyph: string) is QML's, not JS
  execFileSync(cmd[0], cmd.slice(1), { env: { PATH: `${bin}:/usr/bin:/bin`, HOME: work }, stdio: "pipe" });
  return existsSync(log) ? readFileSync(log, "utf8").trim() : "";
}

for (const [compositor, name] of [["hyprland", "Hyprland"], ["niri", "niri"]]) {
  const typed = pick(compositor, true), copied = pick(compositor, false);
  check(`on ${name}, with a window focused, the pick is typed into it`, typed === "typed 🙂", typed || "nothing happened");
  check(`on ${name} with nothing focused, it is copied and the notice says so`, /^notice Copied/.test(copied), copied || "nothing happened");
}
rmSync(work, { recursive: true, force: true });
done();
