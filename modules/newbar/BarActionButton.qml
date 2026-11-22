import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Tacit.Kit as K

Item {
    id: root

    property bool show: true
    property string symbol: ""
    property string label: ""
    property bool active: false
    property color ink: Tacit.inkMain
    property real buttonWidth: 36
    property real buttonHeight: 36
    property bool barBottom: false
    signal activated()

    visible: show
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: buttonWidth
    implicitHeight: buttonHeight
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label
    Keys.onReturnPressed: root.activated()
    Keys.onSpacePressed: root.activated()

    HoverHandler { id: hover }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.active
            ? ColorUtils.applyAlpha(root.ink, Tacit.wash.action)
            : (hover.hovered || root.activeFocus) ? ColorUtils.applyAlpha(root.ink, Tacit.wash.hoverSmall)
            : "transparent"
    }

    K.Symbol {
        anchors.centerIn: parent
        text: root.symbol
        size: 18
        color: root.ink
        visible: root.symbol !== ""
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    PopupToolTip {
        anchorEdges: root.barBottom ? Edges.Top : Edges.Bottom
        extraVisibleCondition: hover.hovered || root.activeFocus
        text: root.label
    }
}
