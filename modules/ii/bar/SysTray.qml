import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The old bar's tray: a single row of every active tray item. There is no pinned/overflow split;
 * the bar's tray button opens all items in the system-tray drawer.
 */
Item {
    id: root
    property bool vertical: false
    property var activeMenu: null

    visible: SystemTray.items.values.length > 0
    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : gridLayout.implicitWidth
    implicitHeight: vertical ? gridLayout.implicitHeight + 6 : Appearance.sizes.barHeight

    function setExtraWindowAndGrabFocus(window) {
        if (root.activeMenu && root.activeMenu !== window) {
            if (typeof root.activeMenu.close === "function")
                root.activeMenu.close()
        }
        root.activeMenu = window
    }
    function releaseFocus() { root.activeMenu = null }
    function closeMenus() {
        if (root.activeMenu) {
            root.activeMenu.close()
            root.activeMenu = null
        }
    }

    HyprlandFocusGrab {
        id: focusGrab
        // A binding, not imperative writes: a tray app that quits with its menu open takes the
        // menu down without closing it, and an armed grab would then swallow the next click.
        active: root.activeMenu !== null
        windows: [root.activeMenu]
        onCleared: root.closeMenus()
    }

    // The menus hang off the bar: an auto-hide bar stays shown while one is open
    BarHold {
        holding: root.activeMenu !== null
        screenName: root.QsWindow.window?.screen?.name ?? ""
    }

    // Esc, the compositor's, closes what a click elsewhere closes
    Connections {
        target: IslandController
        enabled: focusGrab.active
        function onCollapseExpansion() { root.closeMenus() }
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors.centerIn: parent
        rowSpacing: 4
        columnSpacing: 6

        Repeater {
            model: ScriptModel { values: TrayService.items }
            delegate: SysTrayItem {
                required property SystemTrayItem modelData
                item: modelData
                Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
                Layout.fillHeight: !root.vertical
                Layout.fillWidth: root.vertical
                onMenuClosed: root.releaseFocus()
                onMenuOpened: (qsWindow) => root.setExtraWindowAndGrabFocus(qsWindow)
            }
        }
    }
}
