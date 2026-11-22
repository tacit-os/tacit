// Files' Devices list has phones in file-transfer mode (Discord, Oyinos): GVfs's MTP volumes from `gio mount -li`, next
// to the disks lsblk gives. Devices.qml's phonesFrom and fusePath run under node on listings in gio's own layout
// (gio-tool-mount.c: "Volume(n): name", details two spaces in, the Mount nested under its Volume); absorb adds the
// phones to the disks; mount and eject are gio's; and the phone's mount script runs under bash with a pretend gio.
import { spawnSync } from "child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Phones in Files' Devices (services/Devices.qml)");
const src = read("services/Devices.qml");
const root = { phones: [], list: [], first: true, leaving: {}, rootDisk: "nvme0n1", runtimeDir: "/run/user/1000", added() {}, removed() {}, failed() {} };
const fns = {};
for (const name of ["phonesFrom", "fusePath", "absorb", "glyphFor", "nameFor", "mount", "unmount"]) {
  const f = qmlFunction(src, name);
  if (f) root[name] = fns[name] = inScope({ root, Translation: { tr: s => s }, actProc: { createObject: (_, o) => (root.started = o, { set running(v) {} }) } }, f.params, f.body);
}
check("Devices.qml reads phones from gio (phonesFrom, fusePath)", fns.phonesFrom && fns.fusePath);

const stickDrive = `Drive(0): SanDisk Cruzer Blade
  Type: GProxyDrive (GProxyVolumeMonitorUDisks2)
  ids:
   unix-device: '/dev/sdb'
  themed icons:  [drive-removable-media-usb]  [drive-removable-media]  [drive-removable]  [drive]
  symbolic themed icons:  [drive-removable-media-usb-symbolic]  [drive-removable-media-symbolic]
  is_removable=1
  is_media_removable=0
  has_media=1
  is_media_check_automatic=1
  can_poll_for_media=0
  can_eject=1
  can_start=0
  can_stop=0
  start_stop_type=shutdown
  sort_key=01hotplug/1763820000000000
  Volume(0): STICK
    Type: GProxyVolume (GProxyVolumeMonitorUDisks2)
    ids:
     class: 'device'
     unix-device: '/dev/sdb1'
     uuid: '1A2B-3C4D'
     label: 'STICK'
    uuid=1A2B-3C4D
    themed icons:  [drive-removable-media-usb]  [drive-removable-media]
    symbolic themed icons:  [drive-removable-media-usb-symbolic]
    can_mount=1
    can_eject=1
    should_automount=1
    sort_key=gvfs.time_detected_usec.1763820000000000
    Mount(0): STICK -> file:///run/media/sam/STICK
      Type: GProxyMount (GProxyVolumeMonitorUDisks2)
      default_location=file:///run/media/sam/STICK
      themed icons:  [drive-removable-media-usb]  [drive-removable-media]
      can_unmount=1
      can_eject=1
      is_shadowed=0
      sort_key=gvfs.time_detected_usec.1763820000000000
`;
const internal = `Drive(1): KIOXIA THGJFJT2T85BAT0A
  Type: GProxyDrive (GProxyVolumeMonitorUDisks2)
  ids:
   unix-device: '/dev/nvme0n1'
  is_removable=0
  can_eject=0
  sort_key=00coldplug/00fixed/nvme0n1
`;
const phone = (name, uri, mounted) => `Volume(0): ${name}
  Type: GProxyVolume (GProxyVolumeMonitorMTP)
  ids:
   unix-device: '/dev/bus/usb/003/007'
  activation_root=${uri}
  themed icons:  [phone]  [multimedia-player]  [phone-symbolic]
  symbolic themed icons:  [phone-symbolic]  [multimedia-player-symbolic]
  can_mount=1
  can_eject=0
  should_automount=1
` + (mounted ? `  Mount(0): ${name} -> ${uri}
    Type: GProxyMount (GProxyVolumeMonitorMTP)
    default_location=${uri}
    themed icons:  [phone]  [multimedia-player]
    can_unmount=1
    can_eject=0
    is_shadowed=0
` : "");
const pixel = "mtp://Google_Pixel_7_2A111FDH200ABC/";
const fuse = "/run/user/1000/gvfs/mtp:host=Google_Pixel_7_2A111FDH200ABC";

const got = (text) => fns.phonesFrom?.(text, "/run/user/1000") ?? [];
const none = got(internal + stickDrive);
check("no phone: a stick and the internal drive give no phone", none.length === 0, JSON.stringify(none));

const one = got(internal + stickDrive + phone("Pixel 7", pixel, false));
check("a phone plugged in is listed with its name, the smartphone glyph and its mtp:// address", one.length === 1
  && one[0].label === "Pixel 7" && one[0].path === pixel && one[0].mountpoint === "" && fns.glyphFor?.(one[0]) === "smartphone"
  && fns.nameFor?.(one[0]) === "Pixel 7", JSON.stringify(one));

const mounted = got(internal + stickDrive + phone("Pixel 7", pixel, true));
check("a mounted phone's folder is gvfsd-fuse's", mounted[0]?.mountpoint === fuse, mounted[0]?.mountpoint);

// what gvfs's own g_mount_spec_to_string gives (libgvfscommon, gvfs 1.62) for the host of the mtp:// address
const fuseNames = [
  ["mtp://SAMSUNG_SAMSUNG_Android_R58M12345/", "mtp:host=SAMSUNG_SAMSUNG_Android_R58M12345"],
  ["mtp://%5Busb%3A001%2C005%5D/", "mtp:host=%5Busb%3A001%2C005%5D"],
  ["mtp://Google_Pixel%207_2A1B%24%26'()*%2B%3D~%C3%A9", "mtp:host=Google_Pixel%207_2A1B$&'()*+%3D~é"],
];
for (const [uri, name] of fuseNames)
  check(`${uri} is at gvfs/${name}`, fns.fusePath?.(uri, "/run/user/1000") === `/run/user/1000/gvfs/${name}`, fns.fusePath?.(uri, "/run/user/1000"));

// the disk listing adds the phones
if (fns.absorb && one.length) {
  root.phones = one;
  fns.absorb(JSON.stringify({ blockdevices: [{ name: "sdb", path: "/dev/sdb", type: "disk", rm: true, hotplug: true, tran: "usb", children: [
    { name: "sdb1", path: "/dev/sdb1", type: "part", rm: true, hotplug: true, tran: null, fstype: "vfat", label: "STICK", mountpoint: null, mountpoints: [null], size: "15G" }] }] }));
  check("Files' list has the stick and the phone", root.list.map(d => d.label).join(",") === "STICK,Pixel 7", JSON.stringify(root.list.map(d => d.label)));
}

// open and eject go through gio
root.started = null;
fns.mount?.(pixel, () => {});
const mcmd = root.started?.cmd ?? [];
check("opening a phone mounts it with gio and goes to its folder", mcmd[0] === "bash" && mcmd.includes(pixel) && mcmd.at(-1) === fuse, JSON.stringify(mcmd));
root.started = null;
fns.unmount?.(mounted[0] ?? { path: pixel, mtp: true, usb: true });
check("ejecting a phone is gio mount -u, not udisksctl", JSON.stringify(root.started?.cmd) === JSON.stringify(["gio", "mount", "-u", pixel]), JSON.stringify(root.started?.cmd));

// the mount script with a pretend gio: mounted, already mounted, refused
const script = (qmlProperty(src, "phoneMountScript") ?? "''").replace(/^'|'$/g, "").replace(/\\\\/g, "\\");
const tmp = mkdtempSync(join(tmpdir(), "tacit-phones-"));
try {
  writeFileSync(join(tmp, "gio"), '#!/bin/bash\ncase $GIO_SAYS in ok) exit 0 ;; already) echo "gio: $3: Location is already mounted" >&2; exit 2 ;; *) echo "gio: $3: Unable to open MTP device “003,007”" >&2; exit 2 ;; esac\n');
  chmodSync(join(tmp, "gio"), 0o755);
  const run = says => spawnSync("bash", ["-c", script, "_", pixel, fuse], { encoding: "utf8", env: { PATH: `${tmp}:${process.env.PATH}`, GIO_SAYS: says } });
  const at = o => /\bat (.+?)\.?$/m.exec(o)?.[1];
  const ok = run("ok"), again = run("already"), no = run("locked");
  check("mounted: the folder is said as udisksctl says it", ok.status === 0 && at(ok.stdout) === fuse, ok.stdout + ok.stderr);
  check("already mounted: it opens all the same", again.status === 0 && at(again.stdout) === fuse, again.stdout + again.stderr);
  check("refused (a locked phone): it fails with gio's reason", no.status !== 0 && /MTP device/.test(no.stderr), no.stdout + no.stderr);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
