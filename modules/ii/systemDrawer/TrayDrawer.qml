import qs
import qs.modules.ii.systemDrawer
import QtQuick
import Quickshell

// The system-tray drawer: the bar's tray button opens the bar's tray items in the shared shell.
Scope {
    SystemDrawer {
        id: trayDrawer
        open: GlobalStates.trayOpen
        anchor: GlobalStates.trayAnchor
        ipcTarget: "trayDrawer"
        onOpenRequested: GlobalStates.trayOpen = true
        onCloseRequested: GlobalStates.trayOpen = false
        onToggleRequested: GlobalStates.trayOpen = !GlobalStates.trayOpen

        content: Component {
            TrayContent {
                drawer: trayDrawer
            }
        }
    }
}
