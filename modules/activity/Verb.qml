import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// An action: outlined; `primary` (the recommended one) filled in sand; `later` not available yet.
// Hover lifts the outline and the words to full ink; only the sand one changes its fill.
Item {
    id: v
    property string text
    property int px: 17
    property bool primary: false
    property bool later: false
    property int padH: 36
    property int padV: 18
    signal clicked()
    width: vt.width + padH
    height: vt.height + padV
    activeFocusOnTab: !later
    scale: press.pressed && !later ? 0.96 : 1
    Behavior on scale { Anim { type: Anim.FastEffects } }
    Keys.onReturnPressed: if (!v.later) v.clicked()
    Keys.onEnterPressed: if (!v.later) v.clicked()
    Keys.onSpacePressed: if (!v.later) v.clicked()
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: v.primary ? (press.containsMouse || v.activeFocus ? Qt.lighter(Ink.sand, 1.08) : Ink.sand) : "transparent"
        border.width: v.primary ? 0 : v.activeFocus ? 2 : 1.5
        border.color: v.later ? Qt.rgba(1, 1, 1, 0.16) : press.containsMouse || v.activeFocus ? Ink.main : Ink.sec
        Behavior on color { Ease {} }
        Behavior on border.color { Ease {} }
    }
    T {
        id: vt
        anchors.centerIn: parent
        text: v.text
        font.pixelSize: v.px
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
        color: v.primary ? Ink.onSand : v.later ? Ink.faint : Ink.main
    }
    MouseArea {
        id: press
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: v.later ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: if (!v.later) v.clicked()
    }
}
