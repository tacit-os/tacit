pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property alias states: persistentStatesJsonAdapter
    // a plain path: Directories.state is a file:// URL, and mkdir made ~/file:/home/... of it
    property string fileDir: Directories.state.replace(/^file:\/\//, "")
    property string fileName: "states.json"
    property string filePath: `${root.fileDir}/${root.fileName}`

    property bool ready: false
    // Nothing writes states.json until it has been read back and parsed once: a truncated file
    // loads as the defaults, and the next change would write them over what was left.
    property bool loadedCleanly: false
    property string previousHyprlandInstanceSignature: ""
    property bool isNewHyprlandInstance: previousHyprlandInstanceSignature !== states.hyprlandInstanceSignature

    onReadyChanged: {
        root.previousHyprlandInstanceSignature = root.states.hyprlandInstanceSignature
        root.states.hyprlandInstanceSignature = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
        // A recording cut off by a crash or power loss leaves enable true; with no wf-recorder running
        // (a shell reload keeps a live one), record.sh --stop --stale clears it.
        if (root.ready && root.states.record.enable)
            Quickshell.execDetached(["bash", "-c", 'pgrep -x wf-recorder > /dev/null || exec "$0" --stop --stale', Directories.recordScriptPath]);
    }

    Timer {
        id: fileReloadTimer
        interval: 100
        repeat: false
        onTriggered: {
            persistentStatesFileView.reload()
        }
    }

    Timer {
        id: fileWriteTimer
        interval: 100
        repeat: false
        onTriggered: {
            persistentStatesFileView.writeAdapter()
        }
    }

    // A fresh user has no state directory at all, and Directories creates it with a detached
    // mkdir that cannot be relied on to have finished by the time the load below fails. `ready`
    // also has to flip on this path: the lock's launchOnStartup, the keyring fetch and every
    // persisted control wait on it, and on a first run they waited forever.
    Process {
        id: stateDirProc
        command: ["mkdir", "-p", root.fileDir]
        onExited: {
            persistentStatesFileView.writeAdapter();
            root.loadedCleanly = true;
            root.ready = true;
        }
    }

    // The file holds the hotspot password in plain text, and every save writes a new file with the
    // default umask: keep the folder to its owner (so a fresh file is never readable in it) and
    // the file too (so a copy of it keeps the mode).
    function keepPrivate() {
        Quickshell.execDetached(["sh", "-c", 'chmod 700 "$0"; chmod 600 "$1"', root.fileDir, root.filePath]);
    }

    FileView {
        id: persistentStatesFileView
        path: root.filePath

        watchChanges: true
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: if (root.loadedCleanly) fileWriteTimer.restart()
        onSaved: root.keepPrivate()
        onLoaded: {
            root.keepPrivate();
            // A JSON syntax error is not a load failure: this fires and the adapter keeps the
            // defaults. An empty file has nothing to lose.
            let clean = false;
            try {
                if (persistentStatesFileView.text().trim() !== "") JSON.parse(persistentStatesFileView.text());
                clean = true;
            } catch (e) {
                console.log("Persistent states file is not valid JSON, leaving it alone:", e);
            }
            root.loadedCleanly = clean;
            root.ready = true;
        }
        onLoadFailed: error => {
            console.log("Failed to load persistent states file:", error);
            if (error == FileViewError.FileNotFound) {
                stateDirProc.running = true;
                return;
            }
            // Unreadable (permissions, a folder in its place): features waiting on ready come up on
            // the defaults, and the file is left alone.
            root.ready = true;
        }

        adapter: JsonAdapter {
            id: persistentStatesJsonAdapter

            property string hyprlandInstanceSignature: ""

            property JsonObject notifications: JsonObject {
                // apps whose notifications go to the centre only, never a popup
                property list<string> mutedApps: []
                // Do not disturb: kept over a restart of the shell, as the idle inhibitor is
                property bool silent: false
            }
            property JsonObject network: JsonObject {
                property list<string> trusted: []   // networks marked home/work: no VPN needed there
                property string autoVpn: ""         // the VPN that comes up on an untrusted network
                property string hotspotName: ""
                property string hotspotPassword: ""
            }
            property JsonObject sidebar: JsonObject {
                property JsonObject bottomGroup: JsonObject {
                    property bool collapsed: false
                    property int tab: 0
                }
            }

            property JsonObject idle: JsonObject {
                property bool inhibit: false
            }
            // Bluetooth switched off: kept over a restart, which BlueZ starts with every adapter on (BluetoothStatus)
            property JsonObject bluetooth: JsonObject {
                property bool off: false
            }

            // scripts/videos/record.sh writes enable, file, started, stopped (ms) and thumb; the notch's sheet keeps the choices
            property JsonObject record: JsonObject {
                property bool enable: false
                property string file: ""
                property real started: 0
                property real stopped: 0
                property string thumb: ""
                property string last: "area"     // screen, area, window: what Enter repeats
                property string sound: "none"    // none, system, mic
            }

            property JsonObject overlay: JsonObject {
                property list<string> open: ["recorder", "volumeMixer", "resources"]
                property JsonObject crosshair: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 827
                    property real y: 441
                    property real width: 250
                    property real height: 100
                }
                property JsonObject floatingImage: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 1650
                    property real y: 390
                    property real width: 0
                    property real height: 0
                }
                property JsonObject fpsLimiter: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 1570
                    property real y: 615
                    property real width: 280
                    property real height: 80
                }
                property JsonObject recorder: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 80
                    property real y: 80
                    property real width: 350
                    property real height: 130
                }
                property JsonObject resources: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 1500
                    property real y: 770
                    property real width: 350
                    property real height: 200
                    property int tabIndex: 0
                }
                property JsonObject volumeMixer: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 80
                    property real y: 280
                    property real width: 350
                    property real height: 600
                    property int tabIndex: 0
                }
                property JsonObject notes: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 1400
                    property real y: 42
                    property real width: 460
                    property real height: 330
                }
            }

            property JsonObject timer: JsonObject {
                property JsonObject pomodoro: JsonObject {
                    property bool running: false
                    property int start: 0
                    property bool isBreak: false
                    property int cycle: 0
                    property int left: 0        // seconds left while paused; 0 = full lap
                }
                property JsonObject stopwatch: JsonObject {
                    property bool running: false
                    property int start: 0
                    property int elapsed: 0     // 10 ms units, kept while paused
                    property list<var> laps: []
                }
                property JsonObject countdown: JsonObject {
                    property bool running: false
                    property int duration: 0
                    property int start: 0
                    property int left: 0        // seconds left while paused; 0 = full duration
                }
            }
        }
    }
}
