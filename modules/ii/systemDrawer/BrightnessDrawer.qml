import qs
import qs.modules.ii.systemDrawer
import QtQuick
import Quickshell

// The brightness drawer: the bar's brightness button opens the backlight and night-light
// controls in the shared shell.
Scope {
    SystemDrawer {
        open: GlobalStates.brightnessOpen
        anchor: GlobalStates.brightnessAnchor
        ipcTarget: "brightnessDrawer"
        onOpenRequested: GlobalStates.brightnessOpen = true
        onCloseRequested: GlobalStates.brightnessOpen = false
        onToggleRequested: GlobalStates.brightnessOpen = !GlobalStates.brightnessOpen

        content: Component {
            BrightnessContent {}
        }
    }
}
