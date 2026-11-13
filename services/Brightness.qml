pragma Singleton
pragma ComponentBehavior: Bound

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

/**
 * For managing brightness of monitors. Supports both brightnessctl and ddcutil.
 */
Singleton {
    id: root
    signal brightnessChanged()

    property var ddcMonitors: []
    readonly property list<BrightnessMonitor> monitors: Quickshell.screens.map(screen => monitorComp.createObject(root, {
        screen
    }))
    property var previousMonitors: []

    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.screen === screen);
    }

    // A key on a screen that was asked and has no way to be driven (no backlight, no DDC answer): the notch says so,
    // as there is no level to show. Not while the screen is still being asked.
    signal cantDim()

    function increaseBrightness(): void {
        const focusedName = Hyprland.focusedMonitor?.name;
        const monitor = monitors.find(m => focusedName === m.screen.name);
        if (monitor?.ready)
            monitor.setBrightness(monitor.brightness + 0.05);
        else if (monitor?.settled)
            root.cantDim();
    }

    function decreaseBrightness(): void {
        const focusedName = Hyprland.focusedMonitor?.name;
        const monitor = monitors.find(m => focusedName === m.screen.name);
        if (monitor?.ready)
            monitor.setBrightness(monitor.brightness - 0.05);
        else if (monitor?.settled)
            root.cantDim();
    }

    reloadableId: "brightness"

    onMonitorsChanged: {
        // The binding builds a whole new generation on every screen change, and each object is
        // parented here, so the previous one has to be freed or its timers outlive the screen.
        for (const stale of root.previousMonitors)
            stale.destroy();
        root.previousMonitors = root.monitors.slice();
        ddcMonitors = [];
        ddcProc.running = true;
    }

    // Anti-flashbang leaves a screen below the level the person chose, and the device only says where it is now.
    // For each screen the chosen level is kept with the level written to the device, in the user state folder
    // (a restart or a reboot starts with the backlight where it was left): a device still at what was written is
    // at the chosen level dimmed, one found elsewhere was changed by someone else and is taken as it is.
    // { "eDP-1": { "level": 0.6, "written": 0.3 } }
    property var dimLevels: null
    function dimState(): var {
        if (root.dimLevels === null) {
            let parsed = null;
            try {
                parsed = JSON.parse(dimFile.text());
            } catch (e) {}
            root.dimLevels = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({});
        }
        return root.dimLevels;
    }
    function userLevel(name: string, current: real): real {
        if (!Config.options.light.antiFlashbang.enable)
            return current;
        const saved = root.dimState()[name];
        if (saved && typeof saved.level === "number" && typeof saved.written === "number"
                && Math.abs(saved.written - current) <= 0.02 && saved.level >= current && saved.level <= 1)
            return saved.level;
        return current;
    }
    function rememberLevel(name: string, level: real, written: real): void {
        const state = root.dimState();
        if (Config.options.light.antiFlashbang.enable)
            state[name] = { "level": level, "written": written };
        else if (state[name] === undefined)
            return;
        else
            delete state[name];
        dimSaveTimer.restart();
    }
    FileView {
        id: dimFile
        path: `${Directories.userStateDir}/brightness-levels.json`
        blockLoading: true
        blockWrites: true
        printErrors: false
    }
    Timer {
        id: dimSaveTimer
        interval: 800
        onTriggered: dimFile.setText(JSON.stringify(root.dimState()))
    }

    function initializeMonitor(i: int): void {
        if (i >= monitors.length) {
            // Every level is read: leave the panel's where Settings watches it, so a page that
            // was already open starts from the value the shell found.
            root.writePanelLevel();
            return;
        }
        monitors[i].initialize();
    }

    function ddcDetectFinished(): void {
        initializeMonitor(0);
    }

    Process {
        id: ddcProc

        command: ["ddcutil", "detect", "--brief"]
        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: data => {
                if (data.startsWith("Display ")) {
                    const lines = data.split("\n").map(l => l.trim());
                    root.ddcMonitors.push({
                        name: lines.find(l => l.startsWith("DRM connector:")).split("-").slice(1).join('-'),
                        busNum: lines.find(l => l.startsWith("I2C bus:")).split("/dev/i2c-")[1]
                    });
                }
            }
        }
        onExited: root.ddcDetectFinished()
    }

    component BrightnessMonitor: QtObject {
        id: monitor

        required property ShellScreen screen
        property bool isDdc
        property string busNum
        property int rawMaxBrightness: 100
        property real brightness
        property real brightnessMultiplier: 1.0
        property real multipliedBrightness: Math.max(0, Math.min(1, brightness * (Config.options.light.antiFlashbang.enable ? brightnessMultiplier : 1)))
        // The level is read and this screen's brightness can be driven: a DDC monitor that answered, or the
        // built-in panel with a backlight. A screen with neither stays false, and the keys, the control panel's
        // slider and the OSD leave it alone.
        property bool ready: false
        // Asking this screen is over, whatever came of it: false while ddcutil detect, a read or a retry is to come
        property bool settled: false
        // A DDC monitor that did not answer is asked again a few times (it can be slow to wake after being plugged in)
        property int ddcTries: 0
        property bool retrying: false
        // Only the built-in panel is driven by the backlight: brightnessctl moves that one device, whichever screen is focused
        readonly property bool isInternal: /^(eDP|LVDS|DSI)/i.test(monitor.screen.name)
        property bool animateChanges: !monitor.isDdc

        onBrightnessChanged: {
            if (!monitor.ready) return;
            root.brightnessChanged();
        }

        // Not while reading the panel's level at start: that would animate up from 0 and write each step, a dip of the
        // backlight (58 % at boot, during the sunrise, 2026-10-08). The value read is taken as it is and not written back.
        Behavior on multipliedBrightness {
            enabled: monitor.animateChanges && monitor.ready
            NumberAnimation {
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
        onMultipliedBrightnessChanged: {
            if (!monitor.ready) return;
            // The 200 ms Behavior changes this once per frame: for the internal panel let a
            // pending write stand instead of re-execing brightnessctl per frame. DDC panels
            // keep their trailing debounce - they misbehave on rapid writes.
            if (monitor.isDdc)
                setTimer.restart();
            else if (!setTimer.running)
                setTimer.start();
        }

        function initialize() {
            monitor.ready = false;
            monitor.settled = false;
            monitor.ddcTries = 0;
            monitor.retrying = false;
            retryTimer.stop();
            const match = root.ddcMonitors.find(m => m.name === screen.name && !root.monitors.slice(0, root.monitors.indexOf(this)).some(mon => mon.busNum === m.busNum));
            isDdc = !!match;
            busNum = match?.busNum ?? "";
            if (!isDdc && !monitor.isInternal) {
                // The backlight is the laptop's own panel, not this screen: no control rather than one that dims the wrong screen
                monitor.settled = true;
                initializeMonitor(root.monitors.indexOf(monitor) + 1);
                return;
            }
            initProc.command = isDdc ? ["ddcutil", "-b", busNum, "getvcp", "10", "--brief"] : ["sh", "-c", `echo "a b c $(brightnessctl --class backlight g) $(brightnessctl --class backlight m)"`];
            initProc.running = true;
        }

        readonly property Process initProc: Process {
            stdout: SplitParser {
                onRead: data => {
                    const [, , , current, max] = data.split(" ");
                    const rawMax = parseInt(max);
                    const rawCurrent = parseInt(current);
                    // No backlight device leaves both empty: nothing to drive
                    if (!(rawMax > 0) || isNaN(rawCurrent))
                        return;
                    monitor.rawMaxBrightness = rawMax;
                    monitor.brightness = root.userLevel(monitor.screen.name, rawCurrent / rawMax);
                    monitor.ready = true;
                }
            }
            onExited: (exitCode, exitStatus) => {
                const wasRetry = monitor.retrying;
                monitor.retrying = false;
                if (monitor.isDdc && !monitor.ready && monitor.ddcTries < 3) {
                    monitor.ddcTries += 1;
                    retryTimer.restart();
                } else
                    monitor.settled = true;
                // A retry runs beside the others: the one-after-another read has gone on already
                if (!wasRetry)
                    initializeMonitor(root.monitors.indexOf(monitor) + 1);
            }
        }

        property var retryTimer: Timer {
            interval: 5000
            onTriggered: {
                monitor.retrying = true;
                initProc.running = true;
            }
        }

        // One per monitor: exec() ends a write still running, so a shared one lost the other screen's write
        readonly property Process setProc: Process {}

        // We need a delay for DDC monitors because they can be quite slow and might act weird with rapid changes
        property var setTimer: Timer {
            id: setTimer
            interval: monitor.isDdc ? 300 : 30
            onTriggered: {
                syncBrightness();
            }
        }

        function syncBrightness() {
            const brightnessValue = Math.max(monitor.multipliedBrightness, 0);
            if (isDdc) {
                const rawValueRounded = Math.max(Math.floor(brightnessValue * monitor.rawMaxBrightness), 1);
                setProc.exec(["ddcutil", "-b", busNum, "setvcp", "10", rawValueRounded]);
                root.rememberLevel(monitor.screen.name, monitor.brightness, rawValueRounded / monitor.rawMaxBrightness);
            } else {
                // Rounded, not floored (0.29 * 100 is 28.999...), and never below 1 %: a bare raw 1 is black on a panel with a large range
                const valuePercentNumber = Math.max(Math.round(brightnessValue * 100), 1);
                setProc.exec(["brightnessctl", "--class", "backlight", "s", `${valuePercentNumber}%`, "--quiet"])
                root.rememberLevel(monitor.screen.name, monitor.brightness, valuePercentNumber / 100);
            }
        }

        function setBrightness(value: real): void {
            if (!monitor.ready)
                return;
            // Not below 2 %, as the control panel's slider: the keys stepped down to 0 and the screen went dark
            value = Math.max(0.02, Math.min(1, value));
            monitor.brightness = value;
        }

        function setBrightnessMultiplier(value: real): void {
            monitor.brightnessMultiplier = value;
        }
    }

    Component {
        id: monitorComp

        BrightnessMonitor {}
    }

    // Anti-flashbang
    property int workspaceAnimationDelay: 500
    property int contentSwitchDelay: 30
    // a full-screen grab, so it belongs in the per-user runtime dir like the other captures
    property string screenshotDir: FileUtils.trimFileProtocol(`${Directories.runtime}/quickshell/brightness/antiflashbang`)
    function brightnessMultiplierForLightness(x: real): real {
        // I hand picked some values and fitted an exponential curve for this
        // 6.600135 + 216.360356 * e^(-0.0811129189x)
        // Division by 100 is to normalize to [0, 1]
        return (6.600135 + 216.360356 * Math.pow(Math.E, -0.0811129189 * x)) / 100.0;
    }
    Variants {
        model: Quickshell.screens
        Scope {
            id: screenScope
            required property var modelData
            property string screenName: modelData.name
            property string screenshotPath: `${root.screenshotDir}/screenshot-${screenName}.png`
            Connections {
                enabled: Config.options.light.antiFlashbang.enable && Appearance.m3colors.darkmode
                target: Hyprland
                function onRawEvent(event) {
                    if (["activewindowv2", "windowtitlev2"].includes(event.name)) {
                        screenshotTimer.interval = root.contentSwitchDelay;
                        screenshotTimer.restart();
                    } else if (["workspacev2"].includes(event.name)) {
                        screenshotTimer.interval = root.workspaceAnimationDelay;
                        screenshotTimer.restart();
                    }
                }
            }

            Timer {
                id: screenshotTimer
                interval: 700 // This is what I have for a Hyprland ws anim
                onTriggered: {
                    screenshotProc.running = false;
                    screenshotProc.running = true;
                }
            }

            Process {
                id: screenshotProc
                command: ["bash", "-c",
                    `mkdir -p '${StringUtils.shellSingleQuoteEscape(root.screenshotDir)}'`
                    + ` && grim -o '${StringUtils.shellSingleQuoteEscape(screenScope.screenName)}' -`
                    + ` | magick png:- -colorspace Gray -format "%[fx:mean*100]" info:`
                ]
                stdout: StdioCollector {
                    id: lightnessCollector
                    onStreamFinished: {
                        Quickshell.execDetached(["rm", screenScope.screenshotPath]); // Cleanup
                        // A failed grim or magick leaves no text: keep the multiplier as it was
                        const lightness = parseFloat(lightnessCollector.text);
                        if (isNaN(lightness))
                            return;
                        Brightness.getMonitorForScreen(screenScope.modelData)?.setBrightnessMultiplier(root.brightnessMultiplierForLightness(lightness));
                    }
                }
            }
        }
    }

    // External trigger points

    // The level Settings shows, left where its Display page watches it (Directories.brightnessLevelPath):
    // Settings is its own process, so the brightness keys and the control panel can reach its slider no
    // other way. Written at most every 100 ms - a drag changes the level once per pointer move - and the
    // last change always lands.
    FileView {
        id: levelFile
        path: Directories.brightnessLevelPath
        blockWrites: true
        printErrors: false
    }
    Timer {
        id: levelWriteTimer
        interval: 100
        onTriggered: root.writePanelLevel()
    }
    // The one screen not driven over DDC (the built-in panel): the level Settings' slider shows. Only a screen whose
    // level was read counts; with none, the page shows no slider.
    readonly property var panel: root.monitors.find(m => m.ready && !m.isDdc) ?? root.monitors.find(m => m.ready) ?? null
    function writePanelLevel(): void {
        if (root.panel?.ready)
            levelFile.setText(`${root.panel.brightness}\n`);
    }
    onBrightnessChanged: {
        if (levelWriteTimer.running)
            levelWriteTimer.restart();
        else
            levelWriteTimer.start();
    }

    IpcHandler {
        target: "brightness"

        function increment() {
            onPressed: root.increaseBrightness()
        }

        function decrement() {
            onPressed: root.decreaseBrightness()
        }
        // the brightness keys (keybinds.lua), with when they were pressed (ms): a key waits a second for the shell, then
        // steps with brightnessctl itself, so a press read here later than that (the shell was stuck) has been made
        function incrementAt(pressed: string): void {
            if (Date.now() - Number(pressed) < 1000)
                root.increaseBrightness();
        }
        function decrementAt(pressed: string): void {
            if (Date.now() - Number(pressed) < 1000)
                root.decreaseBrightness();
        }

        // The Settings app runs in its own process; a brightnessctl write from there would be
        // undone by the next key press, which steps from the value held here. 0..1, for the
        // built-in panel: the one screen not driven over DDC. -1 while there is no panel level
        // to give (none found, or not read yet): the page then shows no slider.
        function get(): real {
            return root.panel?.ready ? root.panel.brightness : -1;
        }
        function set(value: real): void {
            root.panel?.setBrightness(value);
        }
    }

    CompositorGlobalShortcut {
        name: "brightnessIncrease"
        description: "Increase brightness"
        onPressed: root.increaseBrightness()
    }

    CompositorGlobalShortcut {
        name: "brightnessDecrease"
        description: "Decrease brightness"
        onPressed: root.decreaseBrightness()
    }
}
