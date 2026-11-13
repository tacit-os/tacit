pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * A live update of the shell's own files: Apps' "Get X and the updates", or pacman in a terminal. Quickshell 0.3.2
 * reloads at the first watched file whose content changed, at once (generation.cpp onFileChanged, rootwrapper.cpp
 * onWatchedFilesChanged: no wait, nothing a QML file can hold off), so halfway through pacman's extraction the shell
 * loaded a tree half old and half new, and could say "Tacit couldn't update". tacit-shell's pacman hooks
 * (session/pacman/tacit-shell-update) mark the transaction: "installing" before the first file, "done" after the
 * last. While it installs, the shell stops watching its files (shell.qml binds Quickshell.watchFiles to !holding), and
 * it reloads once when it is done. A transaction that fails runs no end hook: pacman's lock going away ends it then.
 */
Singleton {
    id: root

    // pacman is changing the shell's files: no reload until they are all in
    property bool holding: false

    function heard(said: string): void {
        if (said === "installing" && !root.holding)
            lockProc.running = true;    // held only while pacman runs: a mark left by a transaction that failed is not
        else if (said === "done")
            root.release();
    }
    function release(): void {
        if (!root.holding)
            return;
        root.holding = false;
        Quickshell.reload(false);
    }

    FileView {
        id: mark
        path: "/run/tacit-shell-update"
        watchChanges: true
        printErrors: false
        onFileChanged: mark.reload()
        onLoaded: root.heard(mark.text().trim())
    }
    // pacman's lock: held from the start of a transaction to its end
    Process {
        id: lockProc
        command: ["test", "-e", "/var/lib/pacman/db.lck"]
        onExited: (code, status) => {
            if (code === 0)
                root.holding = true;
            else
                root.release();
        }
    }
    Timer {
        interval: 3000
        repeat: true
        running: root.holding
        onTriggered: lockProc.running = true
    }
}
