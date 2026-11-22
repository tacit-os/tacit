pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common

/**
 * Disks as the desktop sees them: a stick, a card, a phone's storage, a mounted image, and the
 * computer's other internal drives (not the system's own partitions). udisks says when one comes
 * or goes; lsblk says what it is. A phone in file-transfer mode is no disk: GVfs's MTP volume
 * monitor has it, `gio mount -li` lists it and `gio mount -o` says when it comes or goes; without
 * gio or gvfs-mtp there is simply no phone listed. Files' rail lists them,
 * a click mounts and enters, the eject glyph unmounts (and powers a USB device off, so it is
 * safe to pull); the notch peeks when one appears. Nothing is mounted by itself.
 */
Singleton {
    id: root

    property var list: []   // [{ path, name, label, mountpoint, size, fstype, usb, loop, mtp, at }]
    property var phones: []   // the same for the phones gio lists (phonesFrom), added to every listing
    property bool phonesListed: false
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") ?? ""
    property bool first: true
    signal added(var dev)
    signal removed(var dev)
    signal failed(string what)
    signal unmounted(var dev)   // an unmount done: a USB drive is powered off too, safe to pull out

    function glyphFor(d) {
        if (d.mtp)
            return "smartphone";
        if (d.loop)
            return "album";
        if (/mmc|sd_card|card/i.test(d.name + d.label))
            return "sd_card";
        return "usb";
    }
    function nameFor(d) {
        return (d.label ?? "").length > 0 ? d.label : `${d.usb ? "USB" : "Disk"} ${d.size}`;
    }

    Process {
        id: lsblk
        command: ["lsblk", "-J", "-o", "NAME,PATH,LABEL,MOUNTPOINT,MOUNTPOINTS,RM,HOTPLUG,SIZE,TYPE,FSTYPE,TRAN,PARTTYPE"]
        stdout: StdioCollector {
            onStreamFinished: root.absorb(text)
        }
    }
    function refresh() {
        lsblk.running = true;
        gioList.running = true;
    }

    // A phone in file-transfer mode, from `gio mount -li`: a Volume whose activation_root is mtp://. gio prints each
    // Volume as "Volume(n): <name>" with its details two spaces further in and its Mount, once mounted, nested under
    // it; a stick's volume has no activation root (lsblk lists it). Its path is the mtp:// address, its mountpoint the
    // folder gvfsd-fuse shows it at (fusePath). It ejects, as a USB drive does: unmounted, it is safe to pull out.
    function phonesFrom(text, runtimeDir) {
        const vols = [];
        let cur = null;
        for (const line of text.split("\n")) {
            const v = /^( *)Volume\(\d+\): (.*)$/.exec(line);
            if (v) {
                cur = { "depth": v[1].length, "name": v[2].trim(), "uri": "", "mounted": false };
                vols.push(cur);
                continue;
            }
            const depth = line.search(/\S/);
            if (!cur || depth < 0)
                continue;
            if (depth <= cur.depth)
                cur = null;
            else if (/^ *activation_root=/.test(line))
                cur.uri = line.trim().slice("activation_root=".length);
            else if (/^ *Mount\(\d+\): /.test(line))
                cur.mounted = true;
        }
        return vols.filter(v => v.uri.startsWith("mtp://")).map(v => ({ "path": v.uri, "name": v.uri.slice(6).replace(/\/.*$/, ""),
            "label": v.name.length > 0 ? v.name : "Phone", "mountpoint": v.mounted ? root.fusePath(v.uri, runtimeDir) : "",
            "size": "", "fstype": "mtp", "usb": true, "loop": false, "mtp": true }));
    }
    // Where gvfsd-fuse shows a mounted mtp:// address: <runtime dir>/gvfs/ and the mount's name, which is gvfs's
    // g_mount_spec_to_string: "mtp:host=" and the host, escaped as %XX but for letters, digits, -._~$&'()*+ and
    // letters beyond ASCII (mtp://%5Busb%3A001%2C005%5D/ is at gvfs/mtp:host=%5Busb%3A001%2C005%5D).
    function fusePath(uri, runtimeDir) {
        let host = uri.replace(/^mtp:\/\//, "").replace(/\/.*$/, "");
        try { host = decodeURIComponent(host); } catch (e) {}
        const esc = Array.from(host).map(c => c.charCodeAt(0) >= 128 || /[A-Za-z0-9\-._~$&'()*+]/.test(c) ? c
            : "%" + c.charCodeAt(0).toString(16).toUpperCase().padStart(2, "0")).join("");
        return `${runtimeDir}/gvfs/mtp:host=${esc}`;
    }
    Process {
        id: gioList
        command: ["gio", "mount", "-li"]
        stdout: StdioCollector {
            onStreamFinished: {
                const next = root.phonesFrom(text, root.runtimeDir);
                const first = !root.phonesListed;
                root.phonesListed = true;
                if (JSON.stringify(next) === JSON.stringify(root.phones))
                    return;
                if (first)
                    for (const d of next)
                        d.at = 0;   // gio answers after the first disk listing: a phone already there is not news either
                root.phones = next;
                lsblk.running = true;   // the listing adds them and says what came or went
            }
        }
    }

    // The disk the system booted from must never be listed: on a USB install its other
    // partitions (/boot, the ESP, /home) all look removable, and their eject glyph ran
    // `udisksctl power-off`, which cuts power to the drive the system is running on.
    property string rootDisk: ""
    Process {
        id: findRootDisk
        running: true
        command: ["bash", "-c", 'src=$(findmnt -no SOURCE --nofsroot /) || exit 0; lsblk -nso KNAME,TYPE "$src" 2>/dev/null | awk \'$2=="disk"||$2=="loop"{print $1; exit}\'']
        stdout: StdioCollector {
            id: rootDiskCollector
            onStreamFinished: {
                root.rootDisk = rootDiskCollector.text.trim();
                // This owns the first listing: started any earlier it would briefly show the
                // boot disk's own partitions, each with an eject glyph.
                root.refresh();
            }
        }
    }
    Timer {
        id: refreshLater
        interval: 400
        onTriggered: root.refresh()
    }
    function absorb(text) {
        let tree = [];
        try { tree = JSON.parse(text).blockdevices ?? []; } catch (e) {
            root.failed(Translation.tr("couldn't read the disk list"));
            return;
        }
        let next = [];
        // An internal drive is listed unless it is the system's: mounted at / or under /boot, /efi, /home, /usr,
        // /var and the like, a boot (ESP), reserved or recovery partition, or a container (LUKS, LVM, RAID member)
        // that has nothing to mount until it is opened.
        const systemMount = m => m === "/" || m === "[SWAP]" || /^\/(boot|efi|home|usr|var|etc|opt|srv|nix|tmp)(\/|$)/.test(m);
        const hiddenPart = new Set(["c12a7328-f81f-11d2-ba4b-00a0c93ec93b", "e3c9e316-0b5c-4db8-817d-f92df00215ae",
            "de94bba4-06d1-4d40-a16a-bfd50179d6ac", "21686148-6449-6e6f-744e-656564454649", "0xef", "0x27"]);
        const walk = (d, onRootDisk, upUsb, upRemovable) => {
            const usb = upUsb || d.tran === "usb";
            const removable = upRemovable || d.rm === true || d.hotplug === true;
            const loop = d.type === "loop";
            // rootDisk is the whole disk under the root (through a mapper or LVM too), and the flag is
            // handed down so every partition and mapper on it is caught.
            const onBootDisk = onRootDisk || (root.rootDisk.length > 0 && d.name === root.rootDisk);
            const fs = d.fstype ?? "";
            const mounts = (d.mountpoints ?? [d.mountpoint]).filter(m => (m ?? "").length > 0);
            let listed = false;
            if (fs.length > 0 && fs !== "swap" && d.mountpoint !== "/") {
                // the disk the system runs from gets the internal rule however it looks: on a USB install its /boot,
                // ESP and /home look removable, and some laptops' NVMe is hot-pluggable to lsblk, which hid a person's
                // own data partition there (Discord, OYINOS, 2026-11-12)
                if ((usb || removable || loop) && !onBootDisk)
                    listed = true;
                else
                    listed = !mounts.some(systemMount) && !hiddenPart.has((d.parttype ?? "").toLowerCase()) && !/_member$|^crypto_LUKS$|^bcache$/.test(fs);
            }
            // never powered off from the system's own disk: its eject only unmounts
            if (listed)
                next.push({ "path": d.path, "name": d.name, "label": d.label ?? "", "mountpoint": d.mountpoint ?? "", "size": d.size ?? "", "fstype": fs, "usb": usb && !onBootDisk, "loop": loop });
            for (const c of d.children ?? [])
                walk(c, onBootDisk, usb, removable);
        };
        for (const d of tree)
            walk(d, false, false, false);
        next = next.concat((root.phones ?? []).map(d => Object.assign({}, d)));
        const before = root.list;
        const now = Date.now();
        for (const d of next) {
            const b = before.find(x => x.path === d.path);
            d.at = b ? b.at : (d.at === 0 || (before.length === 0 && root.first) ? 0 : now);   // the first listing is not news
        }
        root.first = false;
        root.list = next;
        for (const d of next)
            if (!before.some(b => b.path === d.path))
                root.added(d);
        for (const b of before)
            if (!next.some(d => d.path === b.path))
                root.removed(b);
        for (const p of Object.keys(root.leaving))
            if (!next.some(d => d.path === p && d.mountpoint !== ""))
                delete root.leaving[p];
    }
    // Drives an unmount or an Eject was asked for: one gone before a listing saw it unmounted (Eject powers it off
    // straight after) was ejected, not pulled out. Kept until a listing shows it unmounted or gone, or the unmount fails.
    property var leaving: ({})

    // udisks tells when a device comes or goes; a moment later lsblk says what is there.
    // The monitor dies with udisks2 (a package upgrade, a crash) and nothing used to respawn
    // it, so hot-plug detection stopped for the rest of the session without a word.
    property int monitorBackoff: 2000
    Process {
        id: monitor
        running: true
        command: ["udisksctl", "monitor"]
        stdout: SplitParser {
            onRead: line => {
                if (line.length === 0) return;
                root.monitorBackoff = 2000;
                refreshLater.restart();
            }
        }
        onExited: {
            console.error("[Devices] udisksctl monitor exited; retrying in", root.monitorBackoff, "ms");
            monitorRestart.interval = root.monitorBackoff;
            root.monitorBackoff = Math.min(root.monitorBackoff * 2, 60000);
            monitorRestart.restart();
        }
    }
    Timer {
        id: monitorRestart
        interval: 2000
        onTriggered: {
            monitor.running = true;
            root.refresh();
        }
    }
    // gio's own monitor, for the phones udisks never sees; it is given back the same way. Without gio it never starts,
    // and Process says so once in the log.
    property int phoneMonitorBackoff: 2000
    Process {
        id: phoneMonitor
        running: true
        command: ["gio", "mount", "-o"]
        stdout: SplitParser {
            onRead: line => {
                if (line.length === 0) return;
                root.phoneMonitorBackoff = 2000;
                refreshLater.restart();
            }
        }
        onExited: {
            phoneMonitorRestart.interval = root.phoneMonitorBackoff;
            root.phoneMonitorBackoff = Math.min(root.phoneMonitorBackoff * 2, 60000);
            phoneMonitorRestart.restart();
        }
    }
    Timer {
        id: phoneMonitorRestart
        interval: 2000
        onTriggered: {
            phoneMonitor.running = true;
            root.refresh();
        }
    }

    // mount -> cb(mountpoint) ; "" when it failed (the reason goes through `failed`)
    function mount(path, cb) {
        const cmd = path.startsWith("mtp://") ? ["bash", "-c", root.phoneMountScript, "_", path, root.fusePath(path, root.runtimeDir)]
            : ["udisksctl", "mount", "-b", path];
        const p = actProc.createObject(root, { "cmd": cmd, "cb": cb });
        p.running = true;
    }
    // a phone: mounted by GVfs (already mounted is fine), then said as udisksctl says it, so the folder is read the same way
    readonly property string phoneMountScript: 'out=$(LC_ALL=C gio mount "$1" 2>&1) || case $out in *"already mounted"*) ;; *) printf "%s\\n" "$out" >&2; exit 1 ;; esac; echo "Mounted $1 at $2."'
    // power-off acts on the whole drive, not the partition, so it waits until nothing else on
    // that drive is mounted. The path travels as an argument, not inside the script text.
    readonly property string ejectScript: 'udisksctl unmount -b "$1" || exit 1; disk=$(lsblk -no PKNAME "$1" 2>/dev/null | head -1); if [ -n "$disk" ] && [ "$(lsblk -nro MOUNTPOINT "/dev/$disk" | grep -c .)" -gt 0 ]; then echo "another partition of /dev/$disk is still mounted" >&2; exit 1; fi; udisksctl power-off -b "$1"'

    function unmount(dev) {
        root.leaving[dev.path] = true;
        const cmd = dev.mtp ? ["gio", "mount", "-u", dev.path]
            : dev.usb ? ["bash", "-c", root.ejectScript, "_", dev.path]
            : dev.loop ? ["bash", "-c", 'udisksctl unmount -b "$1"; udisksctl loop-delete -b "$1"', "_", dev.path]
            : ["udisksctl", "unmount", "-b", dev.path];
        const p = actProc.createObject(root, { "cmd": cmd, "cb": null, "dev": dev });
        p.running = true;
    }
    Component {
        id: actProc
        Process {
            id: proc
            property var cmd: []
            property var cb: null
            property var dev: null      // the drive an unmount is for
            command: cmd
            stdout: StdioCollector { id: out }
            stderr: StdioCollector { id: err }
            onExited: (code) => {
                refreshLater.restart();
                const o = out.text.trim(), e = err.text.trim();
                if (code !== 0) {
                    const why = /target is busy|resource busy/i.test(e) ? "still in use" : /not authorized/i.test(e) ? "not allowed"
                        : /MTP device/i.test(e) ? "unlock the phone and allow access to its files" : (e.split("\n").pop() || "it refused");
                    root.failed(why);
                    if (proc.dev) delete root.leaving[proc.dev.path];
                    if (proc.cb) proc.cb("");
                } else if (proc.dev) {
                    root.unmounted(proc.dev);
                } else if (proc.cb) {
                    const m = /\bat (.+?)\.?$/m.exec(o);   // a label may hold spaces
                    proc.cb(m ? m[1] : "");
                }
                proc.destroy();
            }
        }
    }
}
