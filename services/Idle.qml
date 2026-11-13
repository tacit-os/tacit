pragma Singleton
import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * What keeps the screen from going idle, and so from being locked, darkened and suspended.
 *
 * The manual toggle is the notch's coffee and the Quick toggle. A film keeps the screen awake on
 * its own as well: a player asks the compositor for that and most do, but the browser does not
 * (Chromium requests no idle inhibitor), so the lock, the dark screen and the suspend used to
 * arrive in the middle of a video, fullscreen too.
 */
Singleton {
    id: root

    // The manual toggle, until it is turned off or the session ends.
    property bool inhibit: false
    // and as the night's update sees it (tacit-update night, as root): Caffeine on is someone at the computer, so no
    // restart; it could not see the shell's Wayland inhibitor
    onInhibitChanged: Quickshell.execDetached(["bash", "-c", root.inhibit ? ': > "$XDG_RUNTIME_DIR/tacit-caffeine"' : 'rm -f "$XDG_RUNTIME_DIR/tacit-caffeine"'])

    // The window holding the keyboard, as the compositor's window list knows it.
    readonly property var focusedWindow: {
        const toplevel = ToplevelManager.activeToplevel;
        return toplevel?.activated ? HyprlandData.clientForToplevel(toplevel) : null;
    }

    // Something playing in the window in front of you: a fullscreen one, or the one holding the
    // keyboard when it plays a video, which its player reports with no album (a song names one).
    // Music, in front or left playing behind other work, is not watching a film, and must not
    // keep the machine up all night. Not while locked either: the lock, the dark and the suspend
    // are then what the person asked for, and a video still playing behind the lock is no reason
    // to hold them off.
    readonly property bool watching: {
        if (GlobalStates.screenLocked)
            return false;
        const focused = root.focusedWindow;
        const windows = HyprlandData.windowList;
        return MprisController.players.some(player => player.isPlaying && windows.some(win =>
            ((win.fullscreen & 2) !== 0 || (focused !== null && win.address === focused.address && !player.trackAlbum))
            && MprisController.playsIn(win, player)));
    }

    // Whether readyChanged is still to come depends on which of the two was built first: this
    // is a lazy singleton, and a Persistent that loaded before it would never signal again.
    Component.onCompleted: {
        if (Persistent.ready) {
            root.restore();
        }
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            root.restore();
        }
    }
    // Caffeine lasts the session: it comes back after a restart of the shell, not at the next sign-in (a new
    // Hyprland), so one forgotten on Friday does not hold off every lock, sleep and night's update after it.
    function restore() {
        if (Persistent.isNewHyprlandInstance)
            Persistent.states.idle.inhibit = false;
        root.inhibit = Persistent.states.idle.inhibit;
    }

    // qs -c tacit ipc call idle toggle
    IpcHandler {
        target: "idle"

        function toggle(): void {
            root.toggleInhibit();
        }
    }

    // Stay awake until the next start; not written to Persistent.
    function inhibitForSession() {
        root.inhibit = true;
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    IdleInhibitor {
        id: idleInhibitor
        // Either one holds it: turning Caffeine off does not cut a video short.
        enabled: root.inhibit || root.watching
        window: PanelWindow {
            // Inhibitor requires a "visible" surface
            // Actually not lol
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            // Just in case...
            anchors {
                right: true
                bottom: true
            }
            // Make it not interactable
            mask: Region {
                item: null
            }
        }
    }
}