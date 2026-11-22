import QtQuick

MouseArea { // Right side | scroll to change volume
    id: root

    signal scrollUp(delta: int)
    signal scrollDown(delta: int)
    signal movedAway()

    property bool hovered: false
    property real lastScrollX: 0
    property real lastScrollY: 0
    property bool trackingScroll: false
    property real moveThreshold: 20

    acceptedButtons: Qt.LeftButton
    hoverEnabled: true

    onEntered: {
        root.hovered = true;
    }

    onExited: {
        root.hovered = false;
        root.trackingScroll = false;
        root.wheelDelta = 0;
    }

    // A wheel notch is 120; a touchpad sends many small deltas, so add them up and
    // signal once per notch's worth.
    property real wheelDelta: 0

    onWheel: event => {
        root.wheelDelta += event.angleDelta.y;
        while (root.wheelDelta <= -120) {
            root.scrollDown(-120);
            root.wheelDelta += 120;
        }
        while (root.wheelDelta >= 120) {
            root.scrollUp(120);
            root.wheelDelta -= 120;
        }
        // Store the mouse position and start tracking
        root.lastScrollX = event.x;
        root.lastScrollY = event.y;
        root.trackingScroll = true;
    }

    onPositionChanged: mouse => {
        if (root.trackingScroll) {
            const dx = mouse.x - root.lastScrollX;
            const dy = mouse.y - root.lastScrollY;
            if (Math.sqrt(dx * dx + dy * dy) > root.moveThreshold) {
                root.movedAway();
                root.trackingScroll = false;
            }
        }
    }

    onContainsMouseChanged: {
        if (!root.containsMouse && root.trackingScroll) {
            root.movedAway();
            root.trackingScroll = false;
        }
    }
}
