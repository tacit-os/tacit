// The volume and brightness keys (session/hypr/hyprland/keybinds.lua) while the shell is stuck. Quickshell's IPC client
// waits for an answer with no end, and a stuck shell's socket still takes the call, so the key's own way (wpctl,
// brightnessctl) after "||" never ran and every press landed when the shell came back. Each key's command, put together
// by lua from the file's own locals, runs under sh as Hyprland runs it, with a pretend qs that answers at once or hangs
// as a stuck shell does; then the shell's IpcHandler function it called (Audio.qml, Brightness.qml) gets the press at
// once, or as a stuck shell reads it 3 s later.
import { execFileSync, spawnSync } from "child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the volume and brightness keys with the shell stuck (keybinds.lua, Audio.qml, Brightness.qml)");
const lua = read("session/hypr/hyprland/keybinds.lua");
const locals = lua.match(/^local (?:qs\w+|pressedAt) = .+$/gm).join("\n");
const command = key => {
  const m = lua.match(new RegExp(`hl\\.bind\\("${key}", hl\\.dsp\\.exec_cmd\\((.+?)\\),\\s*\\n`));
  return execFileSync("lua", ["-e", `${locals}\nio.write(${m[1]})`], { encoding: "utf8" });
};
const handlers = { audio: read("services/Audio.qml"), brightness: read("services/Brightness.qml") };
// the shell's answer to "ipc call <target> <function> <args>", read at a time after the press
function shellAnswers(target, fn, args, late) {
  const src = handlers[target], at = src.indexOf(`target: "${target}"`);
  const block = src.slice(src.lastIndexOf("IpcHandler {", at), matchBrace(src, src.lastIndexOf("{", at)) + 1);
  const f = qmlFunction(block, fn);
  if (!f) return `no function ${fn}`;
  const steps = [];
  const root = { incrementVolume: () => steps.push("up"), decrementVolume: () => steps.push("down"),
    increaseBrightness: () => steps.push("up"), decreaseBrightness: () => steps.push("down") };
  const now = globalThis.Date.now() + late;
  inScope({ root, Date: { now: () => now } }, f.params.replace(/:\s*[\w.<>]+/g, ""), f.body)(...args);
  return steps;
}

const dir = mkdtempSync(join(tmpdir(), "tacit-keys-"));
try {
  const bin = join(dir, "bin"), log = join(dir, "calls");
  execFileSync("mkdir", [bin]);
  // qs: the shell answering, or stuck (it never answers); wpctl and brightnessctl: the key's own way
  writeFileSync(join(bin, "qs"), `#!/bin/bash\necho "qs $*" >> "${log}"\n[ "$STUCK" = 1 ] && exec sleep 4\nexit 0\n`);
  for (const t of ["wpctl", "brightnessctl"]) writeFileSync(join(bin, t), `#!/bin/bash\necho "${t} $*" >> "${log}"\n`);
  for (const t of ["qs", "wpctl", "brightnessctl"]) chmodSync(join(bin, t), 0o755);
  const press = (cmd, stuck) => {
    writeFileSync(log, "");
    const started = Date.now();
    spawnSync("sh", ["-c", cmd], { stdio: "ignore", timeout: 3000, env: { PATH: `${bin}:/usr/bin:/bin`, TACIT_SHELL: dir, STUCK: stuck ? "1" : "0" } });
    return { calls: readFileSync(log, "utf8").trim().split("\n").filter(Boolean), ms: Date.now() - started };
  };

  for (const [key, own, step] of [["XF86AudioRaiseVolume", "wpctl", "up"], ["XF86AudioLowerVolume", "wpctl", "down"],
    ["XF86MonBrightnessUp", "brightnessctl", "up"], ["XF86MonBrightnessDown", "brightnessctl", "down"]]) {
    const cmd = command(key);
    const ok = press(cmd, false);
    const call = (ok.calls.find(c => c.startsWith("qs ")) ?? "").match(/ipc call (\w+) (\w+)(.*)$/);
    const args = call ? call[3].trim().split(/\s+/).filter(Boolean) : [];
    check(`${key} with the shell answering: the shell steps it once, and ${own} is not run`,
      call && JSON.stringify(shellAnswers(call[1], call[2], args, 20)) === JSON.stringify([step]) && !ok.calls.some(c => c.startsWith(own)),
      `${ok.calls.join("; ")} (${cmd})`);
    const stuck = press(cmd, true);
    check(`${key} with the shell stuck: ${own} steps it within 2 s`, stuck.calls.some(c => c.startsWith(own)) && stuck.ms < 2000,
      `after ${stuck.ms} ms: ${stuck.calls.join("; ")}`);
    if (call) {
      const late = shellAnswers(call[1], call[2], args, 3000);
      check(`${key}: the press the stuck shell reads 3 s later is not made again`, Array.isArray(late) && late.length === 0,
        `the shell steps ${JSON.stringify(late)} for "${call[0]}"`);
    }
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}
done();
