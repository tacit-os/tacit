pragma Singleton

import QtQuick
import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root
    signal gammaChangeAttempt()

    readonly property real gammaLowerLimit: 25
    readonly property bool isNiri: WM.compositor === "niri"

    property string from: Config.options?.light?.night?.from ?? "19:00"
    property string to: Config.options?.light?.night?.to ?? "06:30"
    property bool automatic: (Config.options?.light?.night?.automatic ?? false) && (Config?.ready ?? true)
    property int colorTemperature: Config.options?.light?.night?.colorTemperature ?? 5000
    property int gamma: 100
    property bool shouldBeOn
    property bool firstEvaluation: true
    property bool temperatureActive: false
    property bool loaded: false   // the start's reset (load) is done: the schedule may apply a tint after it

    property int fromHour: Number(from.split(":")[0])
    property int fromMinute: Number(from.split(":")[1])
    property int toHour: Number(to.split(":")[0])
    property int toMinute: Number(to.split(":")[1])

    property int clockHour: DateTime.clock.hours
    property int clockMinute: DateTime.clock.minutes

    property var manualActive
    property int manualActiveHour
    property int manualActiveMinute

    onClockMinuteChanged: reEvaluate()
    onAutomaticChanged: {
        root.manualActive = undefined;
        root.firstEvaluation = true;
        if (root.automatic && Persistent.ready)
            Persistent.states.nightLight.on = false;   // the schedule decides from now on
        reEvaluate();
    }

    function inBetween(t, from, to) {
        if (from < to) {
            return (t >= from && t <= to);
        } else {
            return (t >= from || t <= to);
        }
    }

    function reEvaluate() {
        const t = clockHour * 60 + clockMinute;
        const from = fromHour * 60 + fromMinute;
        const to = toHour * 60 + toMinute;
        const manualActive = manualActiveHour * 60 + manualActiveMinute;

        if (root.manualActive !== undefined && (inBetween(from, manualActive, t) || inBetween(to, manualActive, t))) {
            root.manualActive = undefined;
        }
        root.shouldBeOn = inBetween(t, from, to);

        // The first evaluation (the shell starting, Automatic switched on) applies here, once: its change of
        // shouldBeOn is skipped below, and waiting for the next minute left the screen cold meanwhile.
        firstEvaluation = false;
        root.ensureState();
    }

    onShouldBeOnChanged: {
        if (!root.firstEvaluation)
            root.ensureState();
    }

    function ensureState() {
        if (!root.loaded || !root.automatic || root.manualActive !== undefined)
            return;
        if (root.shouldBeOn) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    // hyprsunset registers its hyprctl handler a moment after it starts, so the change has to
    // follow the daemon inside ONE shell: as a second detached process it missed every time the
    // daemon was not already up, and the first enable applied no tint at all. The trailing
    // pidof is the verification - hyprctl exits 0 with nothing listening, which is how the
    // toggle used to read ON with a cold screen and no hyprsunset installed.
    function applyHyprsunset(request, done, startDaemon = true) {
        const prelude = startDaemon
            ? "pidof hyprsunset >/dev/null || { hyprsunset & disown; sleep 0.3; }; "
            : "pidof hyprsunset >/dev/null || exit 1; ";
        const proc = applyProcComponent.createObject(root, {
            "command": ["bash", "-c", `${prelude}hyprctl hyprsunset ${request} >/dev/null 2>&1; pidof hyprsunset >/dev/null`],
            "done": done
        });
        proc.running = true;
    }

    // One Process per request, so a gamma drag cannot cut off an enable before it answers.
    Component {
        id: applyProcComponent
        Process {
            id: proc
            property var done: null
            onExited: (exitCode, exitStatus) => {
                if (exitCode !== 0)
                    console.error("[Hyprsunset] hyprsunset did not take the change - is it installed?");
                if (proc.done)
                    proc.done(exitCode === 0);
                proc.destroy();
            }
        }
    }

    // Starts from no tint, whatever the last session left, then lets the schedule apply: a tint set
    // before the reset would be wiped by it.
    function load() {
        root.temperatureActive = false;
        if (root.isNiri) {
            root.disableTemperature();
            root.loaded = true;
            root.ensureState();
            root.restoreManual();
            return;
        }
        root.applyHyprsunset("identity", () => {
            root.loaded = true;
            root.ensureState();
            root.restoreManual();
        });
    }

    // A night light switched on by hand (Settings' "On", the pill, the panel) comes back after a restart, a reload or
    // an update of the shell, as Do not disturb does: the reset above wiped it, and only "By time of day" came back.
    // Once the reset is done and both Persistent and Config are read (either may come first: lazy singletons).
    property bool manualRestored: false
    function restoreManual() {
        if (root.manualRestored || !root.loaded || !Persistent.ready || !(Config?.ready ?? true))
            return;
        root.manualRestored = true;
        if (!root.automatic && Persistent.states.nightLight.on)
            root.toggleTemperature(true);
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            root.restoreManual();
        }
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.restoreManual();
        }
    }

    function enableTemperature() {
        if (root.isNiri) {
            root.startNiriSunset(root.colorTemperature);
            root.temperatureActive = true;
            return;
        }
        root.applyHyprsunset(`temperature ${root.colorTemperature}`, ok => root.temperatureActive = ok);
    }

    function disableTemperature() {
        if (root.isNiri) {
            root.stopNiriSunset();
            root.temperatureActive = false;
            return;
        }
        // No daemon means no tint, so off is true either way here; there is nothing to start.
        root.applyHyprsunset("identity", () => root.temperatureActive = false, false);
    }

    function setGamma(gamma) {
        const previousGamma = root.gamma;
        root.gamma = Math.max(root.gammaLowerLimit, Math.min(100, gamma));
        root.gammaChangeAttempt();

        if (root.isNiri) {
            return;
        }
        root.applyHyprsunset(`gamma ${root.gamma}`, ok => {
            if (!ok)
                root.gamma = previousGamma;
        });
    }

    function startNiriSunset(temp) {
        const low = temp;
        const high = temp + 50;
        Quickshell.execDetached(["bash", "-c",
            `pkill -x wlsunset; sleep 0.05; wlsunset -T ${high} -t ${low} -S 23:59 -s 00:00 -d 1 & disown`]);
    }

    function stopNiriSunset() {
        Quickshell.execDetached(["bash", "-c", "pkill -x wlsunset"]);
    }

    function fetchState() {
        if (root.isNiri) {
            niriFetchProc.running = true;
        } else {
            fetchProc.running = true;
        }
    }

    Process {
        id: fetchProc
        running: false
        command: ["bash", "-c", "pidof hyprsunset >/dev/null || exit 0; hyprctl hyprsunset temperature"]
        stdout: StdioCollector {
            id: stateCollector
            onStreamFinished: {
                const output = stateCollector.text.trim();
                if (output.length == 0 || output.startsWith("Couldn't")) {
                    // Nothing running to hold a tint.
                    root.temperatureActive = false;
                    return;
                }
                // Only a Kelvin value proves anything. An error reply used to read as "on"
                // because it merely differed from the string "6500". Neutral daylight is
                // 6500 K and hyprsunset's own default is 6000 K, so below 6000 is a tint.
                const kelvin = Number((output.match(/(\d{4,5})/) ?? [])[1]);
                if (!kelvin) {
                    console.error("[Hyprsunset] Unexpected reply to a temperature query:", output);
                    return;
                }
                root.temperatureActive = kelvin < 6000;
            }
        }
    }

    Process {
        id: niriFetchProc
        running: false
        command: ["bash", "-c", "pgrep -x wlsunset"]
        stdout: StdioCollector {
            id: niriStateCollector
            onStreamFinished: {
                root.temperatureActive = niriStateCollector.text.trim().length > 0;
            }
        }
    }

    // For the Settings app, which runs in its own process: a second copy of this singleton there
    // would run its own schedule against this one's.
    IpcHandler {
        target: "nightLight"
        function active(): bool {
            return root.temperatureActive;
        }
        function set(on: bool): void {
            root.toggleTemperature(on);
        }
    }

    function toggleTemperature(active = undefined) {
        if (root.manualActive === undefined) {
            root.manualActive = root.temperatureActive;
            root.manualActiveHour = root.clockHour;
            root.manualActiveMinute = root.clockMinute;
        }

        root.manualActive = active !== undefined ? active : !root.manualActive;
        if (!root.automatic && Persistent.ready)
            Persistent.states.nightLight.on = root.manualActive;
        if (root.manualActive) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    Connections {
        target: Config.options.light.night
        function onColorTemperatureChanged() {
            if (!root.temperatureActive) return;
            // Re-applying is exactly an enable at the new temperature, verification included.
            root.enableTemperature();
        }
    }
}
