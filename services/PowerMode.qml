pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

/**
 * The power mode, chosen for the charger and for the battery, as Windows has it: Settings > Battery sets both, the
 * control panel the one in use now, and plugging in or out switches between them. tacit-cpu-policy applies it as root
 * (the governor, Intel's and AMD's energy preference, the firmware's profile) whenever /var/lib/tacit/power-mode
 * changes; this only reads and writes that file. Without a choice: fastest on the charger, balanced on battery.
 * The power profile button did nothing before: it asked power-profiles-daemon, which Tacit does not install.
 */
Singleton {
    id: root

    // TACIT_POWER_MODE: another file, as tacit-cpu-policy takes it (a test)
    readonly property string path: Quickshell.env("TACIT_POWER_MODE") || "/var/lib/tacit/power-mode"
    // the policy package that reads the file is installed (it makes the file, writable by the wheel group)
    property bool available: false
    property string onCharger: "fastest"
    property string onBattery: "balanced"
    // the last choice could not be written (outside the wheel group, a read-only disk): Settings' rows say so instead
    // of only snapping back
    property bool refused: false

    readonly property bool charging: !UPower.onBattery
    readonly property string current: root.charging ? root.onCharger : root.onBattery

    readonly property var modes: [
        { value: "saver", label: "Saves battery", glyph: "energy_savings_leaf" },
        { value: "balanced", label: "Balanced", glyph: "airwave" },
        { value: "fastest", label: "Fastest", glyph: "speed" }
    ]
    function labelOf(mode: string): string {
        return (root.modes.find(m => m.value === mode) ?? root.modes[1]).label;
    }
    function glyphOf(mode: string): string {
        return (root.modes.find(m => m.value === mode) ?? root.modes[1]).glyph;
    }
    // what a mode does, in a line
    function say(mode: string): string {
        switch (mode) {
        case "fastest": return "Full speed. Uses more power, and the fan may run";
        case "saver": return "Slower and cooler, so the battery lasts longer";
        default: return "Speeds up for work and slows down when there is none";
        }
    }

    function set(source: string, mode: string): void {
        if (!root.modes.some(m => m.value === mode))
            return;
        if (source === "charger")
            root.onCharger = mode;
        else
            root.onBattery = mode;
        modeFile.setText(`charger=${root.onCharger}\nbattery=${root.onBattery}\n`);
    }
    // the control panel: the mode for whichever is in use now
    function setCurrent(mode: string): void {
        root.set(root.charging ? "charger" : "battery", mode);
    }
    function cycleCurrent(): void {
        const order = ["saver", "balanced", "fastest"];
        root.setCurrent(order[(order.indexOf(root.current) + 1) % order.length]);
    }

    FileView {
        id: modeFile
        path: root.path
        watchChanges: true
        printErrors: false
        // in place: the folder is root's, only the file is the wheel group's
        atomicWrites: false
        onFileChanged: reload()
        // not allowed to write (outside the wheel group, a read-only disk): show the modes the file really holds
        onSaveFailed: {
            root.refused = true;
            reload();
        }
        onSaved: root.refused = false
        onLoaded: {
            root.available = true;
            for (const line of text().split("\n")) {
                const [key, value] = line.split("=");
                if (!root.modes.some(m => m.value === value))
                    continue;
                if (key === "charger")
                    root.onCharger = value;
                else if (key === "battery")
                    root.onBattery = value;
            }
        }
        onLoadFailed: root.available = false
    }
}
