import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * "Caps Lock is on" beside the password, for LockSurface and BootLockSurface. Hyprland does not announce
 * the lock keys, so the state is read from `hyprctl devices` (as the hyprlock this replaced did with
 * check-capslock.sh): when the lock opens, and after the Caps Lock key is pressed. Hidden when it cannot be read.
 * Beside it, the keyboard layout's name while it is not the first one (Alt + Shift on a us,ru pair): a password
 * typed in the second layout failed as a plain wrong one. Hyprland says when the layout changes.
 */
RowLayout {
    id: root
    property bool on: false
    property string layoutName: ""      // "" while the first layout is the one in use
    visible: on || layoutName !== ""
    spacing: 4

    // the compositor sets the lock a moment after the key press reaches us
    function refresh() {
        settle.restart();
    }
    Component.onCompleted: refresh()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout")
                root.refresh();
        }
    }

    Timer {
        id: settle
        interval: 80
        onTriggered: read.running = true
    }
    Process {
        id: read
        running: false
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kb = JSON.parse(text)["keyboards"].find(k => k.main === true);
                    root.on = kb.capsLock === true;
                    root.layoutName = (kb.active_layout_index ?? 0) > 0 ? (kb.active_keymap ?? "") : "";
                } catch (e) {
                    root.on = false; // hyprctl not up yet, or no main keyboard
                    root.layoutName = "";
                }
            }
        }
    }

    MaterialSymbol {
        visible: root.on
        text: "keyboard_capslock"
        iconSize: 20
        color: Appearance.colors.colSubtext
    }
    StyledText {
        visible: root.on
        text: Translation.tr("Caps Lock is on")
        font.pixelSize: 14
        color: Appearance.colors.colSubtext
    }
    MaterialSymbol {
        visible: root.layoutName !== ""
        Layout.leftMargin: root.on ? 8 : 0
        text: "keyboard"
        iconSize: 20
        color: Appearance.colors.colSubtext
    }
    StyledText {
        visible: root.layoutName !== ""
        text: root.layoutName
        font.pixelSize: 14
        color: Appearance.colors.colSubtext
    }
}
