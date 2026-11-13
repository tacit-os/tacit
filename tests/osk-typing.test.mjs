// Whether the on-screen keyboard can type (services/Ydotool.qml, modules/ii/onScreenKeyboard/OnScreenKeyboard.qml):
// Ydotool's check runs under bash with a pretend ydotool on PATH and a socket of its own in a scratch folder (nothing
// reaches this computer's ydotoold), its answer goes through the file's own onStreamFinished, and the keyboard's
// onActiveChanged is run as it opens and closes. Keys that light up and type nothing must say so.
import { spawnSync } from "child_process";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the on-screen keyboard says when it cannot type (Ydotool.qml, OnScreenKeyboard.qml)");
const src = read("services/Ydotool.qml");
const osk = read("modules/ii/onScreenKeyboard/OnScreenKeyboard.qml");

const m = /command:\s*(\["bash"[\s\S]*?\])\s*\n\s*stdout:/.exec(src);
const command = m ? inScope({}, "", `return (${m[1]});`)() : null;
const at = src.indexOf("onStreamFinished:");
const finished = at < 0 ? null : readExpression(src, at + "onStreamFinished:".length).expr;
const Translation = { tr: s => s };

const dir = mkdtempSync(join(tmpdir(), "osk-typing-"));
const bin = join(dir, "bin"), run = join(dir, "run");
mkdirSync(bin);
mkdirSync(run);
// what the strip says on a computer with this ydotool and this socket
function says({ installed, socket = null, mode = 0o600, env = {} }) {
  rmSync(join(bin, "ydotool"), { force: true });
  if (installed) { writeFileSync(join(bin, "ydotool"), "#!/bin/sh\nexit 0\n"); chmodSync(join(bin, "ydotool"), 0o755); }
  rmSync(join(run, ".ydotool_socket"), { force: true });
  if (socket) {
    spawnSync("python3", ["-I", "-c", "import socket, sys; socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM).bind(sys.argv[1])", socket]);
    chmodSync(socket, mode);
  }
  if (!command || !finished) return null;
  const r = spawnSync("/bin/bash", command.slice(1), { encoding: "utf8", env: { PATH: bin, XDG_RUNTIME_DIR: run, ...env } });
  const root = { problem: "<unset>" };
  inScope({ root, text: r.stdout, Translation }, "", finished.replace(/^\{|\}$/g, ""))();
  return root.problem;
}
const daemon = join(run, ".ydotool_socket");
check("without ydotool the strip says it is not installed", says({ installed: false }) === "Can't type · ydotool is not installed", says({ installed: false }));
check("with ydotool but no daemon, that ydotoold is not running", says({ installed: true }) === "Can't type · ydotoold is not running", says({ installed: true }));
check("with the daemon's socket in $XDG_RUNTIME_DIR, nothing: the keys type", says({ installed: true, socket: daemon }) === "");
{
  const elsewhere = join(dir, "ydotoold.sock");
  check("$YDOTOOL_SOCKET is where it looks first, as ydotool does",
    says({ installed: true, socket: elsewhere, env: { YDOTOOL_SOCKET: elsewhere } }) === ""
    && says({ installed: true, socket: daemon, env: { YDOTOOL_SOCKET: join(dir, "none") } }) === "Can't type · ydotoold is not running");
  rmSync(elsewhere, { force: true });
}
// root may write to any socket, so this one is only seen as another user
if (process.getuid?.() !== 0)
  check("a socket this user may not write to (ydotoold run as root): no access",
    says({ installed: true, socket: daemon, mode: 0o400 }) === "Can't type · no access to ydotoold", says({ installed: true, socket: daemon, mode: 0o400 }));
rmSync(dir, { recursive: true, force: true });

// the keyboard asks as it opens, and still lets go of every key as it closes
{
  const f = /onActiveChanged:\s*\{/.exec(osk);
  const body = f ? readExpression(osk, f.index + "onActiveChanged:".length).expr.slice(1, -1) : "";
  const calls = [];
  const loader = { active: false };
  const handler = inScope({ oskLoader: loader, Ydotool: { check: () => calls.push("check"), releaseAllKeys: () => calls.push("release") } }, "", body);
  loader.active = true; handler();
  loader.active = false; handler();
  check("opening the keyboard checks, closing it lets go of the keys", calls.join() === "check,release", calls.join());
}
done();
