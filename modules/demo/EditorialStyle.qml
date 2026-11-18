pragma ComponentBehavior: Bound

// 03 - type-led: no tiles, the clock is the loudest thing and the other groups recede.
import QtQuick
import qs.modules.ii.bar
import qs.modules.demo

Item {
    DemoRowIndex { number: 3 }

    Item {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            leftMargin: 48
        }

        DemoClock {
            large: true
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
        }
        Media {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
        }
        Workspaces {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
