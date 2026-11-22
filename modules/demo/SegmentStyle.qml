pragma ComponentBehavior: Bound

// 02 - segments: the same groups, each in a quiet wash of the ink rather than a bordered card.
import QtQuick
import qs.modules.common
import qs.modules.ii.bar
import qs.modules.demo

Item {
    DemoRowIndex { number: 2 }

    Row {
        anchors {
            horizontalCenter: parent.horizontalCenter
            verticalCenter: parent.verticalCenter
        }
        spacing: 10

        Rectangle {
            width: 176
            height: 48
            radius: Appearance.rounding.chip
            color: Tacit.quiet
            Workspaces { anchors.centerIn: parent }
        }
        Rectangle {
            width: 348
            height: 48
            radius: Appearance.rounding.chip
            color: Tacit.quiet
            Media { anchors.centerIn: parent }
        }
        Rectangle {
            width: 168
            height: 48
            radius: Appearance.rounding.chip
            color: Tacit.quiet
            DemoClock { anchors.centerIn: parent }
        }
    }
}
