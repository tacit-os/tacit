import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    fancyBorders: false // Crosshair should be see-through
    showCenterButton: true
    opacity: 1 // The crosshair itself already has transparency if configured
    showClickabilityButton: false
    clickthrough: true
    resizable: false

    // Persistent's spot for it, 827,441, is the middle of a 1920x1080 screen only. Until it is moved the crosshair stays
    // in the middle of the screen it is on, the mark at the centre with the overlay's header shown or not (the header
    // goes when the overlay closes); Recenter puts it back there.
    readonly property point middleSpot: Qt.point(827, 441)
    readonly property bool inMiddle: root.persistentStateEntry.x === root.middleSpot.x && root.persistentStateEntry.y === root.middleSpot.y
        && (root.parent?.width ?? 0) > 0
    function shownX() {
        return Math.round(root.inMiddle ? (root.parent.width - root.width) / 2
            : root.onScreen(root.persistentStateEntry.x, root.width, root.parent?.width ?? 0));
    }
    function shownY() {
        return Math.round(root.inMiddle ? (root.parent.height - root.height - root.headerHeight) / 2
            : root.onScreenY(root.persistentStateEntry.y));
    }
    x: root.shownX()
    y: root.shownY()
    function center() {
        root.savePosition(root.middleSpot.x, root.middleSpot.y);
        root.x = Qt.binding(() => root.shownX());
        root.y = Qt.binding(() => root.shownY());
    }

    contentItem: CrosshairContent {
        anchors.centerIn: parent
    }
}
