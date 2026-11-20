import qs
import qs.modules.ii.systemDrawer
import QtQuick
import Quickshell

// The network drawer: the bar's network button opens the Wi-Fi section in the shared shell.
Scope {
    SystemDrawer {
        open: GlobalStates.networkOpen
        anchor: GlobalStates.networkAnchor
        ipcTarget: "networkDrawer"
        onOpenRequested: GlobalStates.networkOpen = true
        onCloseRequested: GlobalStates.networkOpen = false
        onToggleRequested: GlobalStates.networkOpen = !GlobalStates.networkOpen

        content: Component {
            NetworkContent {}
        }
    }
}
