pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Whether pam_faillock has locked this account after too many wrong passwords (scripts/lock/faillock.py), read again
 * after each password that failed. While it is locked the right password fails too, so the lock, the boot lock and an
 * app's password request say so, with faillock's own numbers, instead of "Incorrect password".
 */
Singleton {
    id: root
    property bool locked: false
    property bool reading: false
    property int deny: 3
    property int minutes: 10
    // short enough for the lock's password pill
    readonly property string words: root.minutes === 0 ? Translation.tr("Locked after %1 tries").arg(root.deny)
        : root.minutes === 1 ? Translation.tr("Locked for 1 minute after %1 tries").arg(root.deny)
        : Translation.tr("Locked for %1 minutes after %2 tries").arg(root.minutes).arg(root.deny)
    // what a field says after a password failed: nothing while the tally is read, so the wrong words never flash up
    readonly property string failure: root.reading ? "" : root.locked ? root.words : Translation.tr("Incorrect password")

    function read() {
        if (proc.running) {
            proc.again = true;
            return;
        }
        root.reading = true;
        proc.running = true;
    }

    Process {
        id: proc
        property bool again: false
        command: ["python3", FileUtils.trimFileProtocol(`${Directories.scriptPath}/lock/faillock.py`)]
        stdout: StdioCollector {
            id: out
            onStreamFinished: {
                let r = null;
                try { r = JSON.parse(out.text); } catch (e) {}
                root.locked = r?.locked === true;
                if (r) {
                    root.deny = r.deny;
                    root.minutes = r.minutes;
                }
            }
        }
        onRunningChanged: {
            if (running) return;
            if (again) {
                again = false;
                running = true;
            } else {
                root.reading = false;
            }
        }
    }
}
