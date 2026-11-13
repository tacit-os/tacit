// A connected phone's battery, and its remote input (scripts/phone/phone-link.py, services/PhoneLink.qml,
// modules/ii/files/FilesPhone.qml). phone-link.py's `state` runs with busctl on a private bus of its own (no service
// files, so nothing real is started on it), against a stand-in for kdeconnectd 26.08.2 and for the portal: the device's
// properties (core/device.h:26-38), its battery object at <device>/battery (plugins/battery/batteryplugin.h:16-20,
// charge -1 until the phone sends one, :52-53), and org.freedesktop.portal.Desktop with or without the RemoteDesktop
// interface the phone's touchpad and keyboard need (xdg-desktop-portal 1.22.1, which offers it only when a backend has
// it). What it prints goes through PhoneLink's own reading and bindings to the phone page's own lines, under node.
import { spawn, spawnSync } from "child_process";
import { mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, matchBrace, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== a connected phone's battery and remote input (phone-link.py, PhoneLink.qml, FilesPhone.qml)");
const sh = cmd => spawnSync("sh", ["-c", cmd], { encoding: "utf8" });
const missing = [sh("command -v dbus-daemon").status ? "dbus-daemon" : "", sh("command -v busctl").status ? "busctl" : "",
  sh("python3 -I -c 'import gi; gi.require_version(\"Gio\", \"2.0\")'").status ? "PyGObject" : ""].filter(Boolean);

const standIn = `import json, sys
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib
cfg = json.load(open(sys.argv[2]))
xml = """<node>
<interface name="org.kde.kdeconnect.daemon">
  <method name="devices"><arg type="b" direction="in"/><arg type="b" direction="in"/><arg type="as" direction="out"/></method>
  <method name="announcedName"><arg type="s" direction="out"/></method>
  <method name="forceOnNetworkChange"/>
</interface>
<interface name="org.kde.kdeconnect.device">
  <property name="name" type="s" access="read"/>
  <property name="isReachable" type="b" access="read"/>
  <property name="isPaired" type="b" access="read"/>
  <method name="isPairRequestedByPeer"><arg type="b" direction="out"/></method>
  <method name="isPairRequested"><arg type="b" direction="out"/></method>
  <method name="verificationKey"><arg type="s" direction="out"/></method>
  <method name="hasPlugin"><arg type="s" direction="in"/><arg type="b" direction="out"/></method>
</interface>
<interface name="org.kde.kdeconnect.device.battery">
  <property name="charge" type="i" access="read"/>
  <property name="isCharging" type="b" access="read"/>
  <property name="hasBattery" type="b" access="read"/>
</interface>
<interface name="org.freedesktop.portal.RemoteDesktop">
  <property name="AvailableDeviceTypes" type="u" access="read"/>
  <property name="version" type="u" access="read"/>
</interface>
<interface name="org.freedesktop.portal.Screenshot">
  <property name="version" type="u" access="read"/>
</interface>
</node>"""
ifaces = {i.name: i for i in Gio.DBusNodeInfo.new_for_xml(xml).interfaces}
conn = Gio.DBusConnection.new_for_address_sync(sys.argv[1],
    Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
devices = cfg["devices"]

def method(conn, sender, path, iface, name, params, inv):
    d = devices.get(path.rsplit("/", 1)[-1], {})
    answers = {"devices": GLib.Variant("(as)", (list(devices),)), "announcedName": GLib.Variant("(s)", ("This computer",)),
               "isPairRequestedByPeer": GLib.Variant("(b)", (False,)), "isPairRequested": GLib.Variant("(b)", (False,)),
               "verificationKey": GLib.Variant("(s)", ("",)), "hasPlugin": GLib.Variant("(b)", (False,))}
    inv.return_value(answers.get(name))

def prop(conn, sender, path, iface, name):
    if iface == "org.kde.kdeconnect.device.battery":
        b = devices[path.split("/")[-2]]["battery"]
        return {"charge": GLib.Variant("i", b["charge"]), "isCharging": GLib.Variant("b", b["charging"]),
                "hasBattery": GLib.Variant("b", b["charge"] >= 0)}[name]
    if iface == "org.kde.kdeconnect.device":
        d = devices[path.rsplit("/", 1)[-1]]
        return {"name": GLib.Variant("s", d["name"]), "isReachable": GLib.Variant("b", d["reachable"]),
                "isPaired": GLib.Variant("b", d["paired"])}[name]
    return GLib.Variant("u", 7 if name == "AvailableDeviceTypes" else 2)

conn.register_object("/modules/kdeconnect", ifaces["org.kde.kdeconnect.daemon"], method, None, None)
for i, d in devices.items():
    conn.register_object(f"/modules/kdeconnect/devices/{i}", ifaces["org.kde.kdeconnect.device"], method, prop, None)
    if d.get("battery") is not None:   # the plugin is loaded
        conn.register_object(f"/modules/kdeconnect/devices/{i}/battery", ifaces["org.kde.kdeconnect.device.battery"], None, prop, None)
names = ["org.kde.kdeconnect"]
if cfg.get("portal") is not None:
    names.append("org.freedesktop.portal.Desktop")
    conn.register_object("/org/freedesktop/portal/desktop", ifaces["org.freedesktop.portal.Screenshot"], None, prop, None)
    if cfg["portal"] == "remote":
        conn.register_object("/org/freedesktop/portal/desktop", ifaces["org.freedesktop.portal.RemoteDesktop"], None, prop, None)
for n in names:
    conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
                   GLib.Variant("(su)", (n, 4)), None, Gio.DBusCallFlags.NONE, -1, None)
print("ready", flush=True)
GLib.MainLoop().run()
`;

// what kdeconnectd and the portal hold, and what the page should then say
const phone = (name, battery) => ({ [name.toLowerCase().replace(/\W/g, "")]: { name, paired: true, reachable: true, battery } });
const cases = [
  { what: "an Android phone that sent its battery, on Hyprland's portals", devices: phone("Pixel 10", { charge: 82, charging: true }), portal: "plain",
    battery: 82, charging: true, remote: false },
  { what: "an iPhone, which sends none (the daemon holds -1)", devices: phone("iPhone", { charge: -1, charging: false }), portal: "plain",
    battery: -1, charging: false, remote: false },
  { what: "a phone without the battery plugin, with a portal that has remote desktop", devices: phone("Pixel 10", null), portal: "remote",
    battery: -1, charging: false, remote: true },
  { what: "no portal running at all", devices: phone("Pixel 10", { charge: 15, charging: false }), portal: null,
    battery: 15, charging: false, remote: false },
];

// PhoneLink's reading of `state` and its phone, then the page's lines: the ones shown, with their words
const link = read("services/PhoneLink.qml"), page = read("modules/ii/files/FilesPhone.qml");
const procAt = link.indexOf("id: stateProc");
const finished = readExpression(link, link.indexOf("onStreamFinished:", procAt) + "onStreamFinished:".length).expr;
function pageSays(text) {
  const PhoneLink = { loaded: false, installed: true, running: false, devices: [], sends: [], setup: "", pump() {} };
  inScope({ root: PhoneLink, text }, "", finished.replace(/^\{|\}$/g, ""))();
  for (const name of ["phone", "asking", "paired", "phoneName", "phoneReachable", "phoneBattery", "phoneCharging", "usable"]) {
    const e = qmlProperty(link, name);
    if (e) PhoneLink[name] = inScope({ root: PhoneLink }, "", `return (${e});`)();
  }
  const shown = [];
  // the lines of the connected page (its own section, to the end of the page's column)
  for (let at = page.indexOf("K.TacitText {", page.indexOf("// ---- connected")); at >= 0; at = page.indexOf("K.TacitText {", at + 1)) {
    const block = page.slice(at, matchBrace(page, page.indexOf("{", at)) + 1);
    const scope = { PhoneLink, page: { waitingFiles: [], waitingWords: "" }, col: { width: 600 } };
    const v = /\n\s*visible:/.exec(block);
    const t = /\n\s*text:/.exec(block);
    if (!t || (v && !inScope(scope, "", `return (${readExpression(block, v.index + v[0].length).expr});`)())) continue;
    shown.push(String(inScope(scope, "", `return (${readExpression(block, t.index + t[0].length).expr});`)()));
  }
  return { PhoneLink, shown };
}

if (missing.length) {
  console.log(`  skip  phone-link.py is not run here: no ${missing.join(", ")}`);
  done();
} else {
  const tmp = mkdtempSync(join(tmpdir(), "tacit-phone-battery-"));
  const kids = [];
  const until = (ok, ms) => new Promise(res => {
    const t0 = Date.now();
    const tick = () => (ok() ? res(true) : Date.now() - t0 > ms ? res(false) : setTimeout(tick, 50));
    tick();
  });
  // a bus with no service files: nothing it is asked for is started (no kdeconnectd, no portal of the computer's)
  writeFileSync(join(tmp, "bus.conf"), `<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:dir=${tmp}</listen>
  <auth>EXTERNAL</auth>
  <policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>
`);
  writeFileSync(join(tmp, "stand-in.py"), standIn);
  // nothing here reaches the computer's own session bus: the private one, and no XDG_RUNTIME_DIR/bus to fall back on
  const env = address => ({ PATH: process.env.PATH, HOME: tmp, XDG_RUNTIME_DIR: tmp, DBUS_SESSION_BUS_ADDRESS: address, LANG: "C.UTF-8" });
  try {
    const dbus = spawn("dbus-daemon", [`--config-file=${join(tmp, "bus.conf")}`, "--nofork", "--print-address=1"],
      { env: { PATH: process.env.PATH, HOME: tmp, XDG_RUNTIME_DIR: tmp }, stdio: ["ignore", "pipe", "ignore"] });
    kids.push(dbus);
    let said = "";
    dbus.stdout.on("data", d => (said += d));
    const address = (await until(() => said.includes("\n"), 5000)) ? said.split("\n")[0].trim() : "";
    check("a private bus for it", address.startsWith("unix:"), said);
    if (address.startsWith("unix:")) {
      for (const c of cases) {
        writeFileSync(join(tmp, "cfg.json"), JSON.stringify({ devices: c.devices, portal: c.portal }));
        const s = spawn("python3", ["-I", join(tmp, "stand-in.py"), address, join(tmp, "cfg.json")], { env: env(address), stdio: ["ignore", "pipe", "pipe"] });
        kids.push(s);
        let ready = "", err = "";
        s.stdout.on("data", d => (ready += d));
        s.stderr.on("data", d => (err += d));
        if (!(await until(() => ready.includes("ready"), 10000))) {
          check(`${c.what}: the stand-in answers`, false, err.trim().split("\n").slice(-2).join(" | "));
          s.kill();
          continue;
        }
        const r = spawnSync("python3", ["-I", join(tree, "scripts/phone/phone-link.py"), "state"], { encoding: "utf8", env: env(address), timeout: 30000 });
        s.kill();
        await until(() => s.exitCode !== null || s.signalCode !== null, 3000);
        let st = null;
        try { st = JSON.parse(r.stdout); } catch (e) { st = null; }
        const d = st?.devices?.[0];
        check(`${c.what}: the state names the phone, with its battery as the daemon holds it`,
          d?.paired === true && d?.battery === c.battery && d?.charging === c.charging,
          st ? JSON.stringify(d) : `${r.stdout}${r.stderr}`.trim().slice(0, 200));
        check(`${c.what}: and says whether its touchpad and keyboard can work here`, st?.remoteInput === c.remote, JSON.stringify(st?.remoteInput));
        if (!st) continue;
        const { shown } = pageSays(r.stdout);
        const battery = shown.filter(t => /battery/i.test(t));
        const want = c.battery >= 0 ? [`Battery ${c.battery}%${c.charging ? ", charging" : ""}`] : [];
        check(`${c.what}: the phone's page says ${want.length ? JSON.stringify(want[0]) : "no battery"}`, JSON.stringify(battery) === JSON.stringify(want),
          JSON.stringify(shown));
        const remote = shown.filter(t => /touchpad|keyboard/i.test(t));
        check(`${c.what}: ${c.remote ? "no line about remote input" : "a line saying remote input doesn't work here, and why"}`,
          c.remote ? remote.length === 0 : remote.length === 1 && /missing/.test(remote[0]), JSON.stringify(remote));
      }
    }
  } finally {
    for (const k of kids) if (k.exitCode === null && k.signalCode === null) k.kill();
    rmSync(tmp, { recursive: true, force: true });
  }
  done();
}
