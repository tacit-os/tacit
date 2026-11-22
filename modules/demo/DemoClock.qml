pragma ComponentBehavior: Bound

// A compact clock for the demo bar, adapted from modules/ii/bar/ClockWidget.qml.
// It reads the same DateTime service but ranks its text with Tacit's inks, so it sits at home
// on a frost shell surface instead of a bar layer.
import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    property bool large: false
    property bool showDate: true

    implicitWidth: row.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.large ? 10 : 8

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            font.family: root.large ? Appearance.font.family.expressive : Appearance.font.family.numbers
            font.pixelSize: root.large ? Appearance.font.pixelSize.hugeass : Appearance.font.pixelSize.large
            font.features: { "tnum": 1 }
            font.letterSpacing: root.large ? -0.7 : -0.3
            color: Tacit.inkMain
            text: DateTime.time
        }

        StyledText {
            visible: root.showDate
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: root.large ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.smaller
            color: Tacit.inkMeta
            text: DateTime.shortDate
        }
    }
}
