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
 * or goes; lsblk says what it is. Files' rail lists them,
 * a click mounts and enters, the eject glyph unmounts (and powers a USB device off, so it is
 * safe to pull); the notch peeks when one appears. Nothing is mounted by itself.
 */
Singleton {
    id: root

    property var list: []   // [{ path, name, label, mountpoint, size, fstype, usb, loop, at }]
    property bool first: true
    signal added(var dev)
    signal removed(var dev)
    signal failed(string what)

    function glyphFor(d) {
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
    function refresh() { lsblk.running = true; }

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
        const before = root.list;
        const now = Date.now();
        for (const d of next) {
            const b = before.find(x => x.path === d.path);
            d.at = b ? b.at : (before.length === 0 && root.first ? 0 : now);   // the first listing is not news
        }
        root.first = false;
        root.list = next;
        for (const d of next)
            if (!before.some(b => b.path === d.path))
                root.added(d);
        for (const b of before)
            if (!next.some(d => d.path === b.path))
                root.removed(b);
    }

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

    // mount -> cb(mountpoint) ; "" when it failed (the reason goes through `failed`)
    function mount(path, cb) {
        const p = actProc.createObject(root, { "cmd": ["udisksctl", "mount", "-b", path], "cb": cb });
        p.running = true;
    }
    // power-off acts on the whole drive, not the partition, so it waits until nothing else on
    // that drive is mounted. The path travels as an argument, not inside the script text.
    readonly property string ejectScript: 'udisksctl unmount -b "$1" || exit 1; disk=$(lsblk -no PKNAME "$1" 2>/dev/null | head -1); if [ -n "$disk" ] && [ "$(lsblk -nro MOUNTPOINT "/dev/$disk" | grep -c .)" -gt 0 ]; then echo "another partition of /dev/$disk is still mounted" >&2; exit 1; fi; udisksctl power-off -b "$1"'

    function unmount(dev) {
        const cmd = dev.usb
            ? ["bash", "-c", root.ejectScript, "_", dev.path]
            : dev.loop ? ["bash", "-c", 'udisksctl unmount -b "$1"; udisksctl loop-delete -b "$1"', "_", dev.path]
            : ["udisksctl", "unmount", "-b", dev.path];
        const p = actProc.createObject(root, { "cmd": cmd, "cb": null });
        p.running = true;
    }
    Component {
        id: actProc
        Process {
            id: proc
            property var cmd: []
            property var cb: null
            command: cmd
            stdout: StdioCollector { id: out }
            stderr: StdioCollector { id: err }
            onExited: (code) => {
                refreshLater.restart();
                const o = out.text.trim(), e = err.text.trim();
                if (code !== 0) {
                    const why = /target is busy/i.test(e) ? "still in use" : /not authorized/i.test(e) ? "not allowed" : (e.split("\n").pop() || "it refused");
                    root.failed(why);
                    if (proc.cb) proc.cb("");
                } else if (proc.cb) {
                    const m = /\bat (.+?)\.?$/m.exec(o);   // a label may hold spaces
                    proc.cb(m ? m[1] : "");
                }
                proc.destroy();
            }
        }
    }
}
