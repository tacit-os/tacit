import QtQuick
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string edge: "top"
    property real cornerRadius: Appearance.rounding.verylarge
    property real fillet: 12
    property color backgroundColor: Appearance.colors.colBarSurface
    property color borderColor: Appearance.colors.colLayer0Border
    // Override for surfaces that track barShown as a property (which can update on a
    // different frame than Config.options.bar.show on a bar toggle). -1 = auto.
    property int floatingOverride: -1
    property bool floating: (floatingOverride >= 0 ? (floatingOverride === 1) : (Config.options.bar.show && (!Config.options.bar.showBackground || Config.options.bar.drawerStyle !== "attached")))

    anchors.fill: parent

    DockedRect {
        anchors.fill: parent
        visible: !root.floating
        edge: root.edge
        cornerRadius: root.cornerRadius
        fillet: root.fillet
        color: root.backgroundColor
    }

    Rectangle {
        anchors.fill: parent
        visible: root.floating
        radius: root.cornerRadius
        color: root.backgroundColor
        border.width: 1
        border.color: root.borderColor
    }
}
