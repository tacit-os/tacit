import qs
import qs.modules.ii.systemDrawer
import QtQuick
import Quickshell

// The battery drawer: the bar's battery button opens the charge and health detail in the
// shared shell.
Scope {
    SystemDrawer {
        open: GlobalStates.batteryOpen
        anchor: GlobalStates.batteryAnchor
        ipcTarget: "batteryDrawer"
        onOpenRequested: GlobalStates.batteryOpen = true
        onCloseRequested: GlobalStates.batteryOpen = false
        onToggleRequested: GlobalStates.batteryOpen = !GlobalStates.batteryOpen

        content: Component {
            BatteryContent {}
        }
    }
}
