import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.wifiNetworks
import Tacit.Kit
import QtQuick
import QtQuick.Layouts

/**
 * The network drawer's body: the control panel's Wi-Fi section — the radio switch, the
 * capped, scrolling list of access points and the password flows — unchanged. The panel
 * hugs this content; the shared drawer draws the surface.
 */
Item {
    id: root

    implicitWidth: 340
    implicitHeight: wifi.implicitHeight + Kit.tokens.space.l * 2

    DockedRect {
        anchors.fill: parent
        visible: !Config.options.bar.show
        edge: "top"
        cornerRadius: Appearance.rounding.verylarge
        fillet: 12
        color: Appearance.colors.colBarSurface
    }
    Rectangle {
        anchors.fill: parent
        visible: Config.options.bar.show
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colBarSurface
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: Kit.tokens.space.l
            rightMargin: Kit.tokens.space.l
            topMargin: Kit.tokens.space.l
            bottomMargin: Kit.tokens.space.xl
        }

        WifiSection {
            id: wifi
            shown: true
            Layout.fillWidth: true
        }
    }
}
