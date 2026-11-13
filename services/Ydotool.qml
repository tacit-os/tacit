pragma Singleton

import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property int shiftMode: 0 // 0: off, 1: on, 2: lock
    property list<int> shiftKeys: [42, 54] // Keycodes for Shift keys (left and right)
    property list<int> altKeys: [56, 100] // Keycodes for Alt keys (left and right) 
    property list<int> ctrlKeys: [29, 97] // Keycodes for Ctrl keys (left and right)

    // Why the keys cannot type, "" when they can; checked as the keyboard opens (OnScreenKeyboard.qml). ydotool is an
    // optional package and nothing starts its daemon, so on a new install the keys light up and type nothing. The
    // daemon's socket is looked for where ydotool 1.0 looks: $YDOTOOL_SOCKET, else $XDG_RUNTIME_DIR, else /tmp.
    property string problem: ""
    function check() {
        if (!checkProc.running)
            checkProc.running = true;
    }
    Process {
        id: checkProc
        command: ["bash", "-c", 'command -v ydotool >/dev/null || { echo missing; exit; }; '
            + 's=${YDOTOOL_SOCKET:-${XDG_RUNTIME_DIR:-/tmp}/.ydotool_socket}; [ -S "$s" ] || { echo stopped; exit; }; [ -w "$s" ] || echo denied']
        stdout: StdioCollector {
            onStreamFinished: {
                const why = text.trim();
                root.problem = why === "missing" ? Translation.tr("Can't type · ydotool is not installed")
                    : why === "stopped" ? Translation.tr("Can't type · ydotoold is not running")
                    : why === "denied" ? Translation.tr("Can't type · no access to ydotoold")
                    : "";
            }
        }
    }

    function releaseAllKeys() {
        // From 1: keycode 0 is KEY_RESERVED, and the whole list goes to ydotool as one call, so a
        // single argument it refuses would lose all 248 releases and leave a modifier latched.
        const keycodes = Array.from({ length: 248 }, (_, i) => i + 1);
        Quickshell.execDetached([
            "ydotool",
            "key", "--key-delay", "0",
            ...keycodes.map(keycode => `${keycode}:0`)
        ])
        root.shiftMode = 0; // Reset shift mode
    }

    function releaseShiftKeys() {
        Quickshell.execDetached([
            "ydotool",
            "key", "--key-delay", "0",
            ...root.shiftKeys.map(keycode => `${keycode}:0`)
        ])
        root.shiftMode = 0; // Reset shift mode
    }

    function press(keycode) {
        Quickshell.execDetached([
            "ydotool",
            "key", "--key-delay", "0",
            `${keycode}:1`
        ]);
    }

    function release(keycode) {
        Quickshell.execDetached([
            "ydotool",
            "key", "--key-delay", "0",
            `${keycode}:0`
        ]);
    }
}
