// Pinax's Eject (FilesWindow.qml's rail onEject, its Devices Connections and reasonTimer; services/Devices.qml's
// unmount() and the process's onExited): the files' own code, run under node with udisksctl's exit given by hand. The
// "Ejecting" line stays while the stick writes out, then says the stick is safe to pull out; a refusal says why. The
// drive's row in the rail (FilesRail.qml) has a menu with Eject, for a rail folded to its symbols.
import { inScope, matchBrace, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Pinax says when an ejected stick is safe to pull out (FilesWindow.qml, Devices.qml)");
const win = read("modules/ii/files/FilesWindow.qml"), dev = read("services/Devices.qml");
// the body of the "{" that follows `marker` (after `from`)
const bodyAfter = (src, marker, from = 0) => { const open = src.indexOf("{", src.indexOf(marker, from)); return src.slice(open + 1, matchBrace(src, open)); };

// Devices: unmount() makes a process; its onExited is run when udisksctl is done
const procs = [];
const devices = { ejectScript: "", said: [],
  failed(what) { this.said.push(["failed", what]); for (const f of listeners) f.onFailed?.(what); },
  unmounted(d) { this.said.push(["unmounted", d.path]); for (const f of listeners) f.onUnmounted?.(d); } };
const nameFor = qmlFunction(dev, "nameFor");
devices.nameFor = inScope({}, nameFor.params, nameFor.body);
const actProc = { createObject: (parent, props) => { const p = { cb: null, dev: null, ...props, destroy() {} }; procs.push(p); return p; } };
const unmount = qmlFunction(dev, "unmount");
devices.unmount = inScope({ root: devices, actProc }, unmount.params, unmount.body);
const exited = bodyAfter(dev, "onExited: (code) =>");
const finish = (p, code, stderr = "") => inScope({ proc: p, root: devices, out: { text: "" }, err: { text: stderr }, refreshLater: { restart() {} } }, "code", exited)(code);

// the window: its rail's onEject, the Connections on Devices, and the timer that clears its line after 8 s
const timer = { running: false, restart() { this.running = true; } };
const w = { folder: "/home/a/Documents", home: "/home/a", reason: "", ejectedFrom: "", ejecting: "", go(p) { this.folder = p; } };
const scope = { win: w, Devices: devices, reasonTimer: timer };
const onEject = inScope(scope, "dev", bodyAfter(win, "onEject: dev =>"));
const conn = win.slice(win.indexOf("target: Devices"), win.indexOf("target: Devices") + 2000);
const listeners = [{}];
for (const name of ["onUnmounted", "onFailed"]) {
  const f = qmlFunction(conn, name);
  if (f) listeners[0][name] = inScope(scope, f.params, f.body);
}
const runningExpr = readExpression(win, win.indexOf("running:", win.indexOf("id: reasonTimer")) + "running:".length).expr;
// whether the 8 s timer is counting down on the line: started by restart(), or by its binding
const counting = () => timer.running || inScope(scope, "", `return (${runningExpr});`)() === true;

const stick = { path: "/dev/sdb1", name: "sdb1", label: "", size: "14G", mountpoint: "/run/media/a/STICK", usb: true, loop: false };
{
  onEject(stick);
  check("Eject says \"Ejecting USB 14G\"", w.reason === "Ejecting USB 14G", `the line is "${w.reason}"`);
  check("and the line stays while the stick writes out", !counting(), "the 8 s timer clears it while udisksctl is still at it");
  finish(procs.at(-1), 0);                         // a minute on: unmounted and powered off
  check("once it is done, the line says the stick is safe to pull out", w.reason === "USB 14G is safe to pull out", `the line is "${w.reason}"`);
  check("and that line goes after a while", counting());
}
{
  timer.running = false;
  onEject(stick);
  finish(procs.at(-1), 1, "Error unmounting /dev/sdb1: target is busy");
  check("an eject refused says why", w.reason === "Can't: still in use" && counting(), `the line is "${w.reason}"`);
}
{
  timer.running = false;
  const data = { path: "/dev/nvme0n1p3", name: "nvme0n1p3", label: "OYINOS FILE", size: "200G", mountpoint: "/run/media/a/OYINOS FILE", usb: false, loop: false };
  onEject(data);
  finish(procs.at(-1), 0);
  check("a partition of the computer's own disk says it is unmounted", w.reason === "OYINOS FILE is unmounted", `the line is "${w.reason}"`);
}
{
  // folded or narrow, the eject button is not drawn: the drive's row has a menu (a right click, the Menu key) with Eject
  const rail = read("modules/ii/files/FilesRail.qml");
  const section = rail.slice(rail.indexOf('text: "Devices"'), rail.indexOf('glyph: "smartphone"'));
  const at = section.indexOf("onMenu:");
  let asked = null;
  if (at >= 0) inScope({ rail: { deviceActions: (d, x, y) => (asked = { d, x, y }) }, modelData: stick }, "", `return (${readExpression(section, at + 7).expr})`)()(30, 200);
  check("a drive's row in the rail has a menu", asked?.d === stick, "a right click or the Menu key on it does nothing");
  const handler = win.indexOf("onDeviceActions:") >= 0 ? bodyAfter(win, "onDeviceActions: (dev, x, y) =>") : "";
  const actions = { model: [] };
  let opened = false;
  const railView = { eject: d => onEject(d), device() {}, mapToItem: (to, x, y) => ({ x, y }) };
  if (handler) inScope({ actions, railView, body: {}, Devices: devices, win: { ...w, openActionsAt: () => (opened = true) } }, "dev, x, y", handler)(stick, 30, 200);
  const item = actions.model.find(i => i.id === "eject");
  check("and the menu opens with Eject for a mounted stick", opened && item?.label === "Eject", JSON.stringify(actions.model.map(i => i.label)));
  w.reason = ""; w.ejecting = "";
  item?.run();
  check("which ejects it as the button does", w.reason === "Ejecting USB 14G" && w.ejecting === stick.path, `the line is "${w.reason}"`);
}
done();
