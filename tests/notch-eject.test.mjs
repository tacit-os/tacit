// "<drive> is safe to pull out" in the notch once an Eject is done: services/Devices.qml's own absorb() and unmount() with
// the eject process's onExited, wired to the notch's Devices handlers (services/IslandController.qml), under node. lsblk
// is a pretend listing, as in stick-pulled.test.mjs.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the notch after an Eject (Devices.qml, IslandController.qml)");
const devices = read("services/Devices.qml"), island = read("services/IslandController.qml");
const exitAt = devices.indexOf("onExited:", devices.indexOf("id: actProc"));
const exitOpen = devices.indexOf("{", exitAt);
const exitBody = devices.slice(exitOpen + 1, matchBrace(devices, exitOpen));
const connAt = island.lastIndexOf("Connections {", island.indexOf("target: Devices"));
const conn = island.slice(connAt, matchBrace(island, island.indexOf("{", connAt)) + 1);

// a stick on USB, or a second internal disk (sata), mounted or not
const listing = (mounted, tran = "usb") => JSON.stringify({ blockdevices: [{ name: "sdb", path: "/dev/sdb", rm: tran === "usb", hotplug: tran === "usb", tran, size: "14.9G", type: "disk",
  children: [{ name: "sdb1", path: "/dev/sdb1", label: tran === "usb" ? "" : "Data", mountpoint: mounted ? "/run/media/a/STICK" : null,
    mountpoints: [mounted ? "/run/media/a/STICK" : null], fstype: "ext4", size: "14.9G", type: "part", parttype: "0fc63daf-8483-4772-8e79-3d69d8477de4" }] }] });
const nothing = JSON.stringify({ blockdevices: [] });

function desk() {
  const peeks = [], procs = [];
  const Devices = { list: [], first: true, rootDisk: "", leaving: {} };
  const IslandController = { warmedUp: true, request: (name, data) => peeks.push(data.text) };
  for (const name of ["glyphFor", "nameFor"]) { const f = qmlFunction(devices, name); Devices[name] = inScope({ root: Devices }, f.params, f.body); }
  const handlers = {};
  for (const name of ["onAdded", "onRemoved", "onFailed", "onUnmounted"]) {
    const f = qmlFunction(conn, name);
    if (f) handlers[name] = inScope({ root: IslandController, Devices, Voice: { cant: w => `Can't: ${w}` } }, f.params, f.body);
  }
  for (const s of ["added", "removed", "failed", "unmounted"]) Devices[s] = x => handlers[`on${s[0].toUpperCase()}${s.slice(1)}`]?.(x);
  const scope = { root: Devices, Translation: { tr: s => s }, refreshLater: { restart() {} },
    actProc: { createObject: (_, props) => { const p = Object.assign({ running: false, destroy() {} }, props); procs.push(p); return p; } } };
  for (const name of ["absorb", "unmount"]) { const f = qmlFunction(devices, name); Devices[name] = inScope(scope, f.params, f.body); }
  const ends = (code, stderr = "") => {
    const p = procs.shift();
    inScope({ root: Devices, refreshLater: { restart() {} }, proc: p, out: { text: "" }, err: { text: stderr } }, "code", exitBody)(code);
  };
  const plug = t => { Devices.absorb(t); peeks.length = 0; };
  return { Devices, peeks, ends, plug, list: t => Devices.absorb(t) };
}

{
  const d = desk();
  d.plug(listing(true));
  d.Devices.unmount(d.Devices.list[0]);
  d.ends(0);
  check("once Eject is done the notch says the stick is safe to pull out", JSON.stringify(d.peeks) === JSON.stringify(["USB 14.9G is safe to pull out"]), JSON.stringify(d.peeks));
  d.list(nothing);                     // powered off: gone from the list
  check("and nothing more when it leaves the list", d.peeks.length === 1, JSON.stringify(d.peeks));
}
{
  const d = desk();
  d.plug(listing(true));
  d.Devices.unmount(d.Devices.list[0]);
  d.ends(1, "Error unmounting /dev/sdb1: target is busy");
  check("an Eject refused says why, and never that it is safe", d.peeks.length === 1 && !/safe/.test(d.peeks[0]), JSON.stringify(d.peeks));
}
{
  const d = desk();
  d.plug(listing(true, "sata"));
  d.Devices.unmount(d.Devices.list[0]);
  d.ends(0);
  check("an internal disk unmounted is not called safe to pull out", !d.peeks.some(p => /safe to pull/.test(p)), JSON.stringify(d.peeks));
}
done();
