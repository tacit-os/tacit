// Show in folder (org.freedesktop.FileManager1) while the shell cannot take the call: session/filemanager1/
// quiet-filemanager1.c, built with build.sh's flags, run on a private bus standing for the session bus, with a stand-in
// qs that answers as Quickshell 0.3.2 does: a call taken prints nothing and exits 0, a refusal ("Not ready to accept
// queries yet." while the shell reloads, "Target not found.") is printed on stdout and exits 0, and no shell at all
// exits 255. Without a compiler, gio's headers, dbus-daemon or gdbus, the program is not run and says so.
import { spawn, spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("Show in folder while the shell refuses the call (quiet-filemanager1.c)");

const sh = cmd => spawnSync("sh", ["-c", cmd], { encoding: "utf8" });
const missing = [sh("command -v cc").status ? "cc" : "", sh("pkg-config --exists gio-2.0").status ? "gio's headers" : "",
  sh("command -v dbus-daemon").status ? "dbus-daemon" : "", sh("command -v gdbus").status ? "gdbus" : ""].filter(Boolean);
if (missing.length) {
  console.log(`  skip  the program is not run here: no ${missing.join(", ")}`);
  done();
} else {
  const tmp = mkdtempSync(join(tmpdir(), "tacit-fm1-"));
  const kids = [];
  const until = (ok, ms) => new Promise(res => {
    const t0 = Date.now();
    const tick = () => (ok() ? res(true) : Date.now() - t0 > ms ? res(false) : setTimeout(tick, 50));
    tick();
  });
  // qs as 0.3.2 answers `qs -p <shell> ipc call files <verb> <path>`, by the mode in a file; each call is logged
  const bin = join(tmp, "bin"), mode = join(tmp, "mode"), calls = join(tmp, "calls");
  mkdirSync(bin);
  writeFileSync(join(bin, "qs"), `#!/bin/sh
echo "$*" >> '${calls}'
case "$(cat '${mode}')" in
	reloading) echo "Not ready to accept queries yet." ;;
	notarget) echo "Target not found." ;;
	gone) echo "No running instances for \\"$2/shell.qml\\""; exit 255 ;;
esac
exit 0
`, { mode: 0o755 });
  // nothing here reaches the computer's own session bus: a bus of its own, and no XDG_RUNTIME_DIR/bus to fall back on
  const env = address => ({ PATH: `${bin}:${process.env.PATH}`, HOME: tmp, XDG_RUNTIME_DIR: tmp, TACIT_SHELL: join(tmp, "shell"),
    DBUS_SESSION_BUS_ADDRESS: address, LANG: "C.UTF-8" });
  try {
    const program = join(tmp, "quiet-filemanager1");
    const built = sh(`cc -O2 -Wall -Wextra -o '${program}' '${join(tree, "session/filemanager1/quiet-filemanager1.c")}' $(pkg-config --cflags --libs gio-2.0)`);
    check("the program builds", built.status === 0, built.stderr.trim().split("\n").slice(-3).join(" | "));
    if (built.status === 0) {
      const dbus = spawn("dbus-daemon", ["--config-file=/usr/share/dbus-1/session.conf", "--nofork", "--print-address=1"],
        { env: { PATH: process.env.PATH, HOME: tmp, XDG_RUNTIME_DIR: tmp }, stdio: ["ignore", "pipe", "ignore"] });
      kids.push(dbus);
      let said = "";
      dbus.stdout.on("data", d => (said += d));
      const addressed = await until(() => said.includes("\n"), 5000);
      const address = said.split("\n")[0].trim();
      check("a private bus for it", addressed && address.startsWith("unix:"), said);
      if (addressed && address.startsWith("unix:")) {
        const fm = spawn(program, [], { env: env(address), stdio: ["ignore", "ignore", "ignore"] });
        kids.push(fm);
        const gdbus = (...args) => spawnSync("gdbus", ["call", "--session", ...args], { encoding: "utf8", env: env(address), timeout: 15000 });
        const owned = await until(() => /true/.test(gdbus("--dest", "org.freedesktop.DBus", "--object-path", "/org/freedesktop/DBus",
          "--method", "org.freedesktop.DBus.NameHasOwner", "org.freedesktop.FileManager1").stdout), 5000);
        check("it takes org.freedesktop.FileManager1 on that bus", owned);
        const file = join(tmp, "report.pdf"), dirs = [join(tmp, "a"), join(tmp, "b")];
        writeFileSync(file, "");
        dirs.forEach(d => mkdirSync(d));
        // what the caller (Firefox's Show in folder) hears: "ok", or the error's words
        const ask = (m, method, uris) => {
          writeFileSync(mode, m);
          const r = gdbus("--dest", "org.freedesktop.FileManager1", "--object-path", "/org/freedesktop/FileManager1",
            "--method", `org.freedesktop.FileManager1.${method}`, `[${uris.map(u => `'file://${u}'`).join(", ")}]`, "");
          return r.status === 0 ? "ok" : (r.stderr.match(/the shell did not take the request: (.*)/)?.[1] ?? r.stderr.trim());
        };
        const got = {
          taken: ask("taken", "ShowItems", [file]),
          reloading: ask("reloading", "ShowItems", [file]),
          notarget: ask("notarget", "ShowItems", [file]),
          gone: ask("gone", "ShowItems", [file]),
          folders: ask("reloading", "ShowFolders", dirs),
        };
        const asked = (() => { try { return readFileSync(calls, "utf8"); } catch (e) { return ""; } })();
        check("a call the shell takes is answered as done, after asking it `files reveal` with the path",
          got.taken === "ok" && asked.split("\n")[0] === `-p ${join(tmp, "shell")} ipc call files reveal ${file}`, `${got.taken}; asked ${JSON.stringify(asked.split("\n")[0])}`);
        check("a call refused while the shell reloads (exit 0, \"Not ready to accept queries yet.\" on stdout) is answered as failed, saying so",
          /Not ready to accept queries yet\./.test(got.reloading), got.reloading);
        check("so is one refused for a target the shell lacks (\"Target not found.\"), and ShowFolders refused for its folders",
          /Target not found\./.test(got.notarget) && /Not ready/.test(got.folders), `${got.notarget}; ShowFolders: ${got.folders}`);
        check("and no shell at all (exit 255) is still a failure", got.gone !== "ok" && /No running instances/.test(got.gone), got.gone);
      }
    }
  } finally {
    for (const k of kids) k.kill();
    rmSync(tmp, { recursive: true, force: true });
  }
  done();
}
