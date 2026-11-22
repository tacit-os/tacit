import QtQuick
import qs.modules.common

// The shell's fast scroll (StyledListView's wheel handler, used when "fasterTouchpadScroll" is
// on), always on here: a conversation is long, and the stock wheel with the app's high
// deceleration moves a few pixels a notch. Same factors from Config (mouse per notch, touchpad
// per 120 units), same accumulation while the 200 ms scroll animation runs. Put it inside a
// StyledListView, whose `Behavior on contentY` does the easing, or set `ease` on a view without
// one (Files, Graphis) so its other moves - the cursor followed, a row revealed - stay immediate.
// A mostly sideways wheel is left to the view, which scrolls long lines itself, and so are a touchpad swipe's start and
// end, which move nothing: taken here, the view never began the swipe and dragged its sideways part nowhere.
MouseArea {
    id: wheel
    required property Flickable view
    property bool ease: false
    property real target: 0
    property double last: 0

    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    onWheel: e => {
        if (e.phase === Qt.ScrollBegin || e.phase === Qt.ScrollEnd || Math.abs(e.angleDelta.x) > Math.abs(e.angleDelta.y)) {
            e.accepted = false;
            return;
        }
        const threshold = Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120;
        const mouse = Math.abs(e.angleDelta.y) >= threshold;
        const factor = mouse ? (Config?.options.interactions.scrolling.mouseScrollFactor ?? 120)
                             : (Config?.options.interactions.scrolling.touchpadScrollFactor ?? 450);
        const minY = wheel.view.originY - wheel.view.topMargin;
        const maxY = Math.max(minY, wheel.view.contentHeight + wheel.view.bottomMargin - wheel.view.height + wheel.view.originY);
        const base = Date.now() - wheel.last < 220 ? wheel.target : wheel.view.contentY;
        wheel.target = Math.max(minY, Math.min(base - e.angleDelta.y / threshold * factor, maxY));
        wheel.last = Date.now();
        if (wheel.ease) {
            glide.stop();
            glide.to = wheel.target;
            glide.start();
        } else {
            wheel.view.contentY = wheel.target;
        }
        if ("atEnd" in wheel.view) wheel.view.atEnd = wheel.target >= maxY - 2;   // scrolled up: stop following the end
        e.accepted = true;
    }

    NumberAnimation {
        id: glide
        target: wheel.view
        property: "contentY"
        duration: Appearance.animation.scroll.duration
        easing.type: Appearance.animation.scroll.type
        easing.bezierCurve: Appearance.animation.scroll.bezierCurve
    }
}
