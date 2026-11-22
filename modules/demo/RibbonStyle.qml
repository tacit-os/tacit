pragma ComponentBehavior: Bound

// 01 - flat ribbon: the three groups share the frost with nothing between them but space.
import QtQuick
import qs.modules.ii.bar
import qs.modules.demo

Item {
    DemoRowIndex { number: 1 }

    Item {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            leftMargin: 48
        }

        Workspaces {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }
        Media {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
        }
        DemoClock {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
