import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import Tacit.Kit
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray

/**
 * The system-tray drawer's body: every active tray item in one grid. Each item is the same
 * SysTrayItem the older bar uses, so clicking an icon activates its app and right-clicking opens
 * its menu with the same focus grab. The panel hugs this content; the shared drawer draws it.
 */
Item {
    id: root

    // Set by TrayDrawer so the menu can tell the drawer not to close beneath it.
    property var drawer: null

    readonly property bool hasItems: TrayService.items.length > 0
    readonly property int itemCount: TrayService.items.length
    // Fit items into a compact grid: one row for a handful, wrapping as the tray fills. The
    // drawer follows this width so a single icon does not sit in a mostly empty panel.
    readonly property int gridCols: Math.max(1, Math.min(itemCount, 8))

    property var activeMenu: null

    function setExtraWindowAndGrabFocus(window) {
        if (root.activeMenu && root.activeMenu !== window && typeof root.activeMenu.close === "function")
            root.activeMenu.close();
        root.activeMenu = window;
    }
    function releaseFocus() { root.activeMenu = null }
    function closeMenus() {
        if (root.activeMenu && typeof root.activeMenu.close === "function")
            root.activeMenu.close();
        root.activeMenu = null;
    }

    // The menu takes its own grab: tell the drawer to ignore the dismissal that grab causes, so
    // a right-click opens the menu without closing the drawer underneath it.
    onActiveMenuChanged: {
        if (!drawer) return;
        const open = root.activeMenu !== null;
        drawer.holdDismissal = open;
        if (!open && GlobalStates.trayOpen)
            drawer.regrab();
    }
    // A tray app that quits with its menu up takes the menu down; close it so the grab does not
    // stay armed and swallow the next click.
    HyprlandFocusGrab {
        active: root.activeMenu !== null
        windows: [root.activeMenu]
        onCleared: root.closeMenus()
    }
    Connections {
        target: IslandController
        enabled: root.activeMenu !== null
        function onCollapseExpansion() { root.closeMenus() }
    }
    // The drawer itself dismisses on click-away; make sure an open app menu goes with it.
    Connections {
        target: GlobalStates
        function onTrayOpenChanged() { if (!GlobalStates.trayOpen) root.closeMenus() }
    }

    implicitWidth: {
        const gridW = root.gridCols * 20 + Math.max(0, root.gridCols - 1) * Kit.tokens.space.s;
        const chrome = Kit.tokens.space.l + Kit.tokens.space.l; // column margins
        const maxW = 340;
        // No apps: just the empty-state label. One app: just that icon, no extra empty panel.
        if (root.itemCount === 0) return 112;
        if (root.itemCount === 1) return Math.max(52, Math.min(maxW, gridW + chrome));
        return Math.max(160, Math.min(maxW, gridW + chrome));
    }
    implicitHeight: content.implicitHeight + (root.itemCount === 0 ? Kit.tokens.space.s + Kit.tokens.space.s : Kit.tokens.space.l + Kit.tokens.space.xl)

    DockedRect {
        anchors.fill: parent
        edge: "top"
        cornerRadius: Appearance.rounding.verylarge
        fillet: 12
        color: Config.options.bar.showBackground ? Appearance.colors.colBarSurface : "transparent"
    }

    ColumnLayout {
        id: content
        anchors {
            fill: parent
            leftMargin: Kit.tokens.space.l
            rightMargin: Kit.tokens.space.l
            topMargin: root.itemCount === 0 ? Kit.tokens.space.s : Kit.tokens.space.l
            bottomMargin: root.itemCount === 0 ? Kit.tokens.space.s : Kit.tokens.space.xl
        }
        spacing: root.itemCount === 0 ? 0 : Kit.tokens.space.m

        StyledText {
            Layout.fillWidth: true
            visible: root.itemCount > 1
            text: Translation.tr("System tray")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        // Every active item in one grid; no pinned/overflow split.
        GridLayout {
            Layout.fillWidth: true
            visible: root.hasItems
            columns: root.gridCols
            rowSpacing: Kit.tokens.space.s
            columnSpacing: Kit.tokens.space.s
            Repeater {
                model: ScriptModel { values: TrayService.items }
                delegate: SysTrayItem {
                    required property SystemTrayItem modelData
                    item: modelData
                    onMenuClosed: root.releaseFocus()
                    onMenuOpened: (window) => root.setExtraWindowAndGrabFocus(window)
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !root.hasItems
            text: Translation.tr("No tray items")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
