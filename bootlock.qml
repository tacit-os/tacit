import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import qs.modules.ii.lock
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * The boot lock: a second, tiny quickshell instance that only locks the session.
 *
 *   QS_BOOTLOCK=1 qs -p ~/.config/quickshell/tacit/bootlock.qml
 *
 * Hyprland launches it as its first client, so it holds the screen within about a second
 * while the full shell takes its fifteen. It draws BootLockSurface (the shell's lock surface
 * minus the services) with BootLockContext (the PAM flow minus GlobalStates, so no compositor
 * shortcut or IPC target is registered twice), touches $XDG_RUNTIME_DIR/martida-lock-ready
 * once the password is accepted, unlocks the keyring on success, and quits. If it dies the
 * compositor simply shows the desktop (allow_session_lock_restore).
 *
 * Its first frame is the boot ground WITH the mark -- the exact picture the splash daemon
 * held and the compositor's own frames carried -- laid over the lock; then the overlay
 * dissolves, so the mark melts into the clock and nothing on screen ever cuts.
 */
ShellRoot {
    id: root

    // Flipped after the first frame: the carried splash picture dissolves into the lock.
    property bool carried: false

    // Tacit's boot sky (BootSky.qml): on once tacit-boot-ground has made the person's boot pictures (sky.json beside
    // the still the splash and the compositor held). Until then the carried picture below, as before.
    readonly property string skyState: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/tacit-boot"
    readonly property bool skyOn: skyFile.loaded
    FileView {
        id: skyFile
        path: root.skyState + "/sky.json"
        blockLoading: true
        printErrors: false
    }
    Component {
        id: skyComponent
        BootSky {
            groundPath: root.skyState + "/lock-ground.png"
            palettePath: root.skyState + "/sky.json"
        }
    }

    // Not `context`: BootLockSurface has a property of that name, and `context: context`
    // would bind it to itself (null).
    BootLockContext {
        id: lockContext
        onUnlocked: targetAction => {
            if (targetAction == BootLockContext.ActionEnum.Poweroff) {
                Session.poweroff();
                return;
            }
            if (targetAction == BootLockContext.ActionEnum.Reboot) {
                Session.reboot();
                return;
            }
            lock.locked = false;
            root.xrayOff();
            unlockKeyringProc.password = lockContext.currentText;
            readyMarkerProc.running = true;
            quitGuard.start();
        }
    }

    // A Shut down or Restart the system refused gives the field and the reader back, and the field says so.
    Connections {
        target: Session
        function onActionFailed(label, code) {
            if (lockContext.unlockInProgress) {
                lockContext.reset();
                lockContext.tryFingerUnlock();
            }
            lockContext.refusedAction = label;
        }
    }

    // The marker means "a human unlocked this", not "a frame was drawn": execs.lua starts
    // hyprlock when it is missing, so a boot lock that dies before the password has to leave
    // it absent. It must also exist before this process goes away, hence the handler.
    Process {
        id: readyMarkerProc
        command: ["touch", Quickshell.env("XDG_RUNTIME_DIR") + "/martida-lock-ready"]
        onExited: {
            if (Config.options.lock.security.unlockKeyring) {
                // Quitting would kill this managed process: leave only when it has finished.
                unlockKeyringProc.running = true;
            } else {
                quitTimer.start();
            }
        }
    }

    Process {
        id: unlockKeyringProc
        property string password: ""
        stdinEnabled: true
        command: ["bash", "-c", Quickshell.shellPath("scripts/keyring/unlock.sh")]
        // The script takes the password on stdin when UNLOCK_PASSWORD is unset. Handing it
        // over that way instead leaves it out of /proc/<pid>/environ, which anything else
        // running as this user can read for as long as the script lives.
        onStarted: {
            unlockKeyringProc.write(unlockKeyringProc.password + "\n");
            unlockKeyringProc.password = "";
            unlockKeyringProc.stdinEnabled = false;
        }
        onExited: quitTimer.start()
    }

    // Let the unlock commit before the process goes away.
    Timer {
        id: quitTimer
        interval: 300
        repeat: false
        onTriggered: root.quit()
    }
    // Nothing -- the keyring script, a stalled marker -- may keep an unlocked lock alive.
    Timer {
        id: quitGuard
        interval: 5000
        repeat: false
        onTriggered: root.quit()
    }
    // The compositor shows what is under the lock (the boot still) instead of black until this lock's first frame:
    // execs.lua switches session_lock_xray on just before starting it. Off as soon as a surface covers the screen.
    function xrayOff() {
        Quickshell.execDetached(["hyprctl", "eval", "hl.config({ misc = { session_lock_xray = false } })"]);
    }

    // Qt.quit() is a no-op under quickshell: end this instance the way `qs kill` does.
    function quit() {
        Quickshell.execDetached(["kill", String(Quickshell.processId)]);
    }

    // After the first frame: start the dissolve.
    Timer {
        id: readyTimer
        interval: 120
        repeat: false
        onTriggered: {
            root.carried = true;
            // without the boot sky the surface is opaque from its first frame
            if (!root.skyOn)
                root.xrayOff();
        }
    }

    WlSessionLock {
        id: lock
        locked: true
        surface: WlSessionLockSurface {
            id: lockSurface
            color: "transparent"
            // set once this screen's sky has drawn its first frames: the carried picture below can go
            property bool skyUnderway: false
            BootLockSurface {
                id: surface
                anchors.fill: parent
                context: lockContext
                holdEntrance: root.skyOn
                groundPath: root.skyState + "/lock-ground.png"
                underlay: root.skyOn ? skyComponent : null
                // the first key or touch takes the sunrise to its end in half a second
                onActivity: if (surface.underlayItem) surface.underlayItem.finish()
            }
            Connections {
                target: surface.underlayItem
                function onArrived() { surface.enter(); }
            }
            // Each screen's surface starts its own sky after its first frame. In here: the lock's surface is a
            // component, so `surface` cannot be reached from the root (a ReferenceError there left the sky still).
            Timer {
                interval: 120
                running: true
                onTriggered: {
                    if (surface.underlayItem) {
                        surface.underlayItem.play();
                        underway.start();
                    }
                }
            }
            Timer {
                id: underway
                interval: 100
                onTriggered: {
                    lockSurface.skyUnderway = true;
                    root.xrayOff();
                }
            }
            // The carried splash picture: tacit-boot's still, the pixels the splash, the compositor and swaybg hold and
            // the sky's first frame. It covers this surface from its first frame, so nothing else can show before the sky
            // is read and drawn (the old martida picture did, for a moment), and goes once the sky is under way: unseen,
            // the pixels are the same. Without the boot pictures it dissolves into the lock as before.
            Image {
                anchors.fill: parent
                source: "file://" + root.skyState + "/still.png"
                fillMode: Image.PreserveAspectCrop
                cache: false
                asynchronous: false
                opacity: root.skyOn ? (lockSurface.skyUnderway ? 0 : 1) : (root.carried ? 0 : 1)
                visible: opacity > 0
                Behavior on opacity {
                    enabled: !root.skyOn
                    NumberAnimation { duration: 700; easing.type: Easing.InOutQuad }
                }
            }
        }
    }

    Component.onCompleted: {
        readyTimer.start();
    }
}
