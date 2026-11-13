// Files' Devices list (absorb) on lsblk trees: a data partition on the system's own disk is listed, unmount only (Discord, OYINOS, 2026-11-12)
import { readFileSync } from "fs";
import { tree } from "./lib/check.mjs";
import { join } from "path";
console.log("== Files' Devices list (services/Devices.qml)");
const src = readFileSync(join(tree, "services/Devices.qml"), "utf8");
const at = src.indexOf("function absorb(text) {") + "function absorb(text) {".length;
let depth = 1, i = at; for (; depth; i++) { if (src[i] === "{") depth++; if (src[i] === "}") depth--; }
const absorb = new Function("root", "Translation", "text", src.slice(at, i - 1));
const P = (name, o) => ({ name, path: `/dev/${name}`, rm: false, hotplug: false, tran: null, type: "part", mountpoint: null, mountpoints: [null], parttype: "0fc63daf-8483-4772-8e79-3d69d8477de4", label: null, size: "10G", ...o });
const ESP = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b";
function nvme(hotplug) {
  return { name: "nvme0n1", path: "/dev/nvme0n1", type: "disk", rm: false, hotplug, tran: "nvme", fstype: null, children: [
    P("nvme0n1p1", { fstype: "vfat", parttype: ESP, mountpoint: "/boot", mountpoints: ["/boot"], hotplug }),
    P("nvme0n1p2", { fstype: "ext4", mountpoint: "/", mountpoints: ["/"], hotplug }),
    P("nvme0n1p3", { fstype: "ext4", label: "OYINOS FILE", hotplug }) ] };
}
const stick = { name: "sdb", path: "/dev/sdb", type: "disk", rm: true, hotplug: true, tran: "usb", children: [P("sdb1", { fstype: "vfat", label: "STICK", rm: true, hotplug: true })] };
const usbInstall = { name: "sda", path: "/dev/sda", type: "disk", rm: true, hotplug: true, tran: "usb", children: [
  P("sda1", { fstype: "vfat", parttype: ESP, mountpoint: "/boot", mountpoints: ["/boot"], rm: true, hotplug: true }),
  P("sda2", { fstype: "ext4", mountpoint: "/", mountpoints: ["/"], rm: true, hotplug: true }),
  P("sda3", { fstype: "exfat", label: "DATA", rm: true, hotplug: true }) ] };
const cases = [
  ["OYINOS: NVMe that lsblk calls hot-pluggable", [nvme(true), stick], "nvme0n1", { "nvme0n1p3": "unmount", sdb1: "eject" }],
  ["the same NVMe, not hot-pluggable", [nvme(false)], "nvme0n1", { "nvme0n1p3": "unmount" }],
  ["Tacit installed on a USB stick", [usbInstall], "sda", { sda3: "unmount" }],
];
let bad = 0;
for (const [name, tree, rootDisk, want] of cases) {
  const root = { rootDisk, list: [], first: true, leaving: {}, added() {}, removed() {}, failed(w) { throw new Error(w); } };
  absorb(root, { tr: s => s }, JSON.stringify({ blockdevices: tree }));
  const got = Object.fromEntries(root.list.map(d => [d.name, d.usb ? "eject" : "unmount"]));
  const ok = JSON.stringify(got) === JSON.stringify(want);
  bad += !ok;
  console.log(`${ok ? "ok  " : "FAIL"} ${name}: listed ${JSON.stringify(got)}${ok ? "" : ` (should be ${JSON.stringify(want)})`}`);
}
console.log(`${cases.length - bad} of ${cases.length} as they should be`);
process.exit(bad ? 1 : 0);
