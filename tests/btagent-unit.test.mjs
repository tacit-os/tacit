// The quiet Bluetooth agent as tacit-shell installs it, on a computer whose adapter comes after login (a USB dongle):
// the unit's conditions (session/systemd/user/quiet-btagent.service) read as systemd reads them at login, with no
// /sys/class/bluetooth yet, and the agent itself (session/btagent/quiet-btagent.c, with build.sh's flags) run on a
// private bus standing for the system bus: no bluetoothd at first, then a pretend one (its AgentManager1) appearing.
// Without a compiler, gio's headers, dbus-daemon or Python's gi, the agent is not run and says so.
import { spawn, spawnSync } from "child_process";
import { mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("The quiet Bluetooth agent with an adapter plugged in after login (quiet-btagent.service, quiet-btagent.c)");

// [Unit] conditions and asserts, each held or not with nothing under /sys/class/bluetooth (systemd skips the unit for a
// condition that fails and never tries it again; tacit-session.target starts it once, at login)
const unit = read("session/systemd/user/quiet-btagent.service");
const section = unit.match(/^\[Unit\]\n([\s\S]*?)(?=^\[|(?![\s\S]))/m)?.[1] ?? "";
const failing = [];
for (const [, key, value] of section.matchAll(/^((?:Condition|Assert)\w+)=(.*)$/gm)) {
  const neg = value.replace(/^\|/, "").startsWith("!"), path = value.replace(/^[|!]+/, "");
  if (/Path|Directory/.test(key) && (path === "/sys/class/bluetooth" || path.startsWith("/sys/class/bluetooth/")) && !neg) failing.push(`${key}=${value}`);
}
check("the unit starts at login with no adapter yet", failing.length === 0, `skipped for good by ${failing.join(", ")}`);

const sh = cmd => spawnSync("sh", ["-c", cmd], { encoding: "utf8" });
const missing = [sh("command -v cc").status ? "cc" : "", sh("pkg-config --exists gio-2.0 gio-unix-2.0").status ? "gio's headers" : "",
  sh("command -v dbus-daemon").status ? "dbus-daemon" : "", sh("python3 -I -c 'import gi'").status ? "Python's gi" : ""].filter(Boolean);
if (missing.length) {
  console.log(`  skip  the agent is not run here: no ${missing.join(", ")}`);
  done();
} else {
  const tmp = mkdtempSync(join(tmpdir(), "tacit-btagent-"));
  const kids = [];
  const run = (cmd, args, env = {}) => {
    const p = spawn(cmd, args, { env: { ...process.env, ...env }, stdio: ["ignore", "pipe", "pipe"] });
    p.out = "";
    p.stdout.on("data", d => (p.out += d));
    p.stderr.on("data", d => (p.out += d));
    kids.push(p);
    return p;
  };
  const until = (ok, ms) => new Promise(res => {
    const t0 = Date.now();
    const tick = () => (ok() ? res(true) : Date.now() - t0 > ms ? res(false) : setTimeout(tick, 50));
    tick();
  });
  // bluetoothd as the agent sees it: org.bluez on the bus, AgentManager1 at /org/bluez, each call printed
  const bluez = `
import sys
from gi.repository import Gio, GLib
node = Gio.DBusNodeInfo.new_for_xml("""<node><interface name='org.bluez.AgentManager1'>
<method name='RegisterAgent'><arg type='o' direction='in'/><arg type='s' direction='in'/></method>
<method name='RequestDefaultAgent'><arg type='o' direction='in'/></method>
<method name='UnregisterAgent'><arg type='o' direction='in'/></method></interface></node>""")
bus = Gio.DBusConnection.new_for_address_sync(sys.argv[1],
    Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
def call(conn, sender, path, iface, method, params, inv):
    print(method, *params.unpack(), flush=True)
    inv.return_value(None)
bus.register_object("/org/bluez", node.interfaces[0], call, None, None)
Gio.bus_own_name_on_connection(bus, "org.bluez", Gio.BusNameOwnerFlags.NONE, None, None)
GLib.MainLoop().run()
`;
  try {
    const agent = join(tmp, "quiet-btagent");
    const built = sh(`cc -O2 -Wall -Wno-unused-parameter -o '${agent}' '${join(tree, "session/btagent/quiet-btagent.c")}' $(pkg-config --cflags --libs gio-2.0 gio-unix-2.0)`);
    check("the agent builds", built.status === 0, built.stderr.trim().split("\n").slice(-3).join(" | "));
    if (built.status === 0) {
      const dbus = run("dbus-daemon", ["--config-file=/usr/share/dbus-1/session.conf", "--nofork", "--print-address=1"]);
      const addressed = await until(() => dbus.out.includes("\n"), 5000);
      const address = dbus.out.split("\n")[0].trim();
      check("a private bus for it", addressed && address.startsWith("unix:"), dbus.out);
      const a = run(agent, [], { DBUS_SYSTEM_BUS_ADDRESS: address, XDG_RUNTIME_DIR: tmp });
      let ended = null;
      a.on("exit", (code, sig) => (ended = sig || code));
      await until(() => ended !== null, 1500);
      check("with no bluetoothd it stays up, so no restart loop on a computer without Bluetooth", ended === null,
        `it ended (${ended}): ${a.out.trim()}`);
      const b = run("python3", ["-I", "-c", bluez, address]);
      const registered = await until(() => /RegisterAgent \/\S+ \w+/.test(b.out), 5000);
      check("when bluetoothd comes (the dongle plugged in), the agent registers with it", registered && ended === null,
        `bluetoothd heard ${JSON.stringify(b.out.trim())}; the agent ${ended === null ? "is up" : `ended (${ended})`}: ${a.out.trim()}`);
    }
  } finally {
    for (const p of kids) if (p.exitCode === null && p.signalCode === null) p.kill("SIGTERM");
    await new Promise(res => setTimeout(res, 100));
    rmSync(tmp, { recursive: true, force: true });
  }
  done();
}
