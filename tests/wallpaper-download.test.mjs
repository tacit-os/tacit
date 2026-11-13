// An online wallpaper's download (services/Wallpapers.qml downloadAndApply()): the command it builds, run under bash
// with a stand-in curl. A stalled transfer must give up, and one cut off must leave no picture in the folder.
import { spawnSync } from "child_process";
import { chmodSync, existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== an online wallpaper's download (Wallpapers.qml)");
const f = qmlFunction(read("services/Wallpapers.qml"), "downloadAndApply");
const dir = mkdtempSync(join(tmpdir(), "wallpaper-download-"));
// curl as the network would answer: it writes what came, then exits with CURL_EXIT (18: the transfer was cut off)
writeFileSync(join(dir, "curl"), '#!/bin/bash\nprintf "%s\\n" "$@" > "$CURL_ARGS"\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done\n'
  + 'printf "%s" "$CURL_BODY" > "$out"\nexit "${CURL_EXIT:-0}"\n');
chmodSync(join(dir, "curl"), 0o755);

function download(curlExit, body) {
  const pictures = mkdtempSync(join(dir, "Pictures-"));
  const proc = { running: false, command: null, target: "" };
  inScope({ downloadProc: proc, FileUtils: { trimFileProtocol: s => s }, Directories: { pictures } }, f.params, f.body)(
    { full: "https://w.wallhaven.cc/full/9d/wallhaven-9dx1k8.jpg", id: "9dx1k8", provider: "wallhaven" }, true);
  const r = spawnSync(proc.command[0], proc.command.slice(1), { encoding: "utf8",
    env: { PATH: `${dir}:/usr/bin:/bin`, CURL_ARGS: join(dir, "args"), CURL_EXIT: String(curlExit), CURL_BODY: body } });
  const folder = join(pictures, "Wallpapers");
  return { code: r.status, target: proc.target, files: existsSync(folder) ? readdirSync(folder) : [],
    args: readFileSync(join(dir, "args"), "utf8").split("\n") };
}

const cut = download(18, "half a pic");
check("a transfer cut off fails and leaves nothing in the wallpaper folder", cut.code !== 0 && cut.files.length === 0,
  `exit ${cut.code}, folder holds ${JSON.stringify(cut.files)}`);
const whole = download(0, "a whole picture");
check("a whole one is the picture, under its own name, and nothing else",
  whole.code === 0 && whole.files.join() === "wallhaven-9dx1k8.jpg" && readFileSync(whole.target, "utf8") === "a whole picture",
  `exit ${whole.code}, folder holds ${JSON.stringify(whole.files)}`);
const limit = name => whole.args.includes(name);
check("curl gives up on a connection that does not open, and on one that stalls once open",
  limit("--connect-timeout") && (limit("--speed-time") || limit("--max-time")), JSON.stringify(whole.args));
rmSync(dir, { recursive: true });
done();
