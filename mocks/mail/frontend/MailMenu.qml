import QtQuick
import QtQuick.Controls
import Tacit.Kit as K

K.Menu {
    id: appMenu
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: appMenu.opened
        onActivated: appMenu.close()
    }
    modal: true
    dim: false
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnReleaseOutside
}
