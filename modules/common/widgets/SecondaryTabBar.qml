import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.models

TabBar {
    id: root
    property real indicatorPadding: 8
    Layout.fillWidth: true

    background: Item {
        WheelHandler {
            // A touchpad swipe sends many small deltas: a tab per event ran a single flick through every tab. A tab is
            // one wheel notch (120); a change of direction starts again.
            property real pending: 0
            onWheel: (event) => {
                if (event.angleDelta.y === 0) return;
                if (pending * event.angleDelta.y < 0) pending = 0;
                pending += event.angleDelta.y;
                if (pending <= -120) {
                    root.incrementCurrentIndex();
                    pending = 0;
                } else if (pending >= 120) {
                    root.decrementCurrentIndex();
                    pending = 0;
                }
            }
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        }

        Rectangle {
            id: activeIndicator
            z: 9999
            anchors.bottom: parent.bottom
            topLeftRadius: height
            topRightRadius: height
            bottomLeftRadius: 0
            bottomRightRadius: 0
            color: Appearance.colors.colPrimary
            // Animation
            property real baseWidth: root.width / root.count
            AnimatedTabIndexPair {
                id: idxPair
                index: root.currentIndex
            }
            height: 3
            x: Math.min(idxPair.idx1, idxPair.idx2) * baseWidth + root.indicatorPadding
            width: ((Math.max(idxPair.idx1, idxPair.idx2) + 1) * baseWidth - root.indicatorPadding) - x
        }

        Rectangle { // Tabbar bottom border
            id: tabBarBottomBorder
            z: 9998
            anchors.bottom: parent.bottom
            height: 1
            anchors {
                left: parent.left
                right: parent.right
            }
            color: Appearance.colors.colOutlineVariant
        }
    }
}
