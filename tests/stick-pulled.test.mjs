// A USB stick pulled out while mounted, and one ejected first: services/Devices.qml's own absorb() and unmount() with the
// eject process's onExited, wired to the notch's Devices handlers (services/IslandController.qml), under node. lsblk is a
// pretend listing; udisks' order is the real one: Eject unmounts and powers the drive off in one go, so the next listing
// can find it gone without ever having seen it unmounted.
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a stick pulled out without Eject (Devices.qml, IslandController.qml)");
const devices = read("services/Devices.qml"), island = read("services/IslandController.qml");
const exitAt = devices.indexOf("onExited:", devices.indexOf("id: actProc"));
const exitOpen = devices.indexOf("{", exitAt);
const exitBody = devices.slice(exitOpen + 1, matchBrace(devices, exitOpen));
const connAt = island.lastIndexOf("Connections {", island.indexOf("target: Devices"));
const conn = island.slice(connAt, matchBrace(island, island.indexOf("{", connAt)) + 1);

const stick = mounted => JSON.stringify({ blockdevices: [{ name: "sdb", path: "/dev/sdb", rm: true, hotplug: true, tran: "usb", size: "14.9G", type: "disk",
  children: [{ name: "sdb1", path: "/dev/sdb1", label: "", mountpoint: mounted ? "/run/media/a/STICK" : null,
    mountpoints: [mounted ? "/run/media/a/STICK" : null], fstype: "vfat", size: "14.9G", type: "part" }] }] });
const nothing = JSON.stringify({ blockdevices: [] });

function desk() {
  const peeks = [], procs = [];
  const Devices = { list: [], first: true, rootDisk: "", leaving: {}, added() {}, failed() {}, unmounted() {} };
  const IslandController = { warmedUp: true, request: (name, data, priority) => peeks.push(data.text) };
  for (const name of ["glyphFor", "nameFor"]) { const f = qmlFunction(devices, name); Devices[name] = inScope({ root: Devices }, f.params, f.body); }
  const handlers = {};
  for (const name of ["onAdded", "onRemoved", "onFailed"]) {
    const f = qmlFunction(conn, name);
    if (f) handlers[name] = inScope({ root: IslandController, Devices, Voice: { cant: w => `Can't: ${w}` } }, f.params, f.body);
  }
  Devices.removed = dev => handlers.onRemoved?.(dev);
  Devices.added = dev => handlers.onAdded?.(dev);
  const scope = { root: Devices, Translation: { tr: s => s }, refreshLater: { restart() {} },
    actProc: { createObject: (_, props) => { const p = Object.assign({ running: false, destroy() {} }, props); procs.push(p); return p; } } };
  for (const name of ["absorb", "unmount"]) { const f = qmlFunction(devices, name); Devices[name] = inScope(scope, f.params, f.body); }
  // the eject's process ends: code 0 done, else refused with what udisks said
  const ends = (code, stderr = "") => {
    const p = procs.shift();
    inScope({ root: Devices, refreshLater: { restart() {} }, proc: p, out: { text: "" }, err: { text: stderr } }, "code", exitBody)(code);
  };
  // plugged in: listed, and its arrival's own peek is not what these checks are about
  const plug = t => { Devices.absorb(t); peeks.length = 0; };
  return { Devices, peeks, ends, plug, list: t => Devices.absorb(t) };
}

{
  const d = desk();
  d.plug(stick(true));
  d.list(nothing);                     // pulled out while mounted
  check("a mounted stick pulled out says so in the notch", d.peeks.length === 1 && /pulled out/.test(d.peeks[0]), JSON.stringify(d.peeks));
  check("by its name, and that it was not ejected", d.peeks[0] === "USB 14.9G pulled out · without Eject", JSON.stringify(d.peeks[0]));
}
{
  const d = desk();
  d.plug(stick(true));
  d.Devices.unmount(d.Devices.list[0]);
  d.list(nothing);                     // Eject: unmounted and powered off before any listing saw it unmounted
  d.ends(0);
  check("an ejected stick that goes at once says nothing of being pulled", d.peeks.length === 0, JSON.stringify(d.peeks));
}
{
  const d = desk();
  d.plug(stick(true));
  d.Devices.unmount(d.Devices.list[0]);
  d.list(stick(false));                // the listing sees it unmounted first
  d.ends(0);
  d.list(nothing);
  check("nor one seen unmounted before it went", d.peeks.length === 0, JSON.stringify(d.peeks));
}
{
  const d = desk();
  d.plug(stick(false));
  d.list(nothing);
  check("a stick never mounted goes without a word", d.peeks.length === 0, JSON.stringify(d.peeks));
}
{
  const d = desk();
  d.plug(stick(true));
  d.Devices.unmount(d.Devices.list[0]);
  d.ends(1, "Error unmounting /dev/sdb1: target is busy");
  d.list(nothing);                     // Eject refused (a file open on it), then pulled anyway
  check("a stick whose Eject was refused, then pulled, says so", d.peeks.length === 1 && /pulled out/.test(d.peeks[0]), JSON.stringify(d.peeks));
}
done();
