pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.tacit.card
import qs.modules.tacit.overlay

/*
 * To make an overlay widget:
 * 1. Create a modules/overlay/<yourWidget>/<YourWidget>.qml, using this as the base class and declare your widget content as contentItem
 * 2. Add an entry to OverlayContext.availableWidgets with identifier=<yourWidgetIdentifier>
 * 3. Add an entry in Persistent.states.overlay.<yourWidgetIdentifier> with x, y, width, height, pinned, clickthrough properties set to reasonable defaults
 * 4. Add a Repeater for it in OverlayContent, with a ScriptModel over entry("<yourWidgetIdentifier>")
 * Use existing entries as reference.
 */
AbstractOverlayWidget {
    id: root

    // To be defined by subclasses
    required property Item contentItem
    property bool fancyBorders: true
    property bool showCenterButton: false
    property bool showClickabilityButton: true
    // Keep the ground while pinned with the overlay closed.
    property bool pinnedGround: true

    // Defaults n stuff
    required property var modelData
    readonly property string identifier: modelData.identifier
    readonly property string materialSymbol: modelData.materialSymbol ?? "widgets"
    property string title: modelData.label ?? identifier
    property var persistentStateEntry: Persistent.states.overlay[identifier]
    property real radius: 24
    property real minimumWidth: contentItem.implicitWidth
    property real minimumHeight: contentItem.implicitHeight
    property real resizeMargin: 8
    property real padding: 12
    // 34 px strip and its hairline; closed, a pinned widget has no header.
    readonly property real openHeaderHeight: 35
    property real headerHeight: GlobalStates.overlayOpen ? openHeaderHeight : 0
    Behavior on headerHeight {
        NumberAnimation {
            id: headerFold
            duration: GlobalStates.overlayOpen ? Appearance.animationCurves.expressiveDefaultSpatialDuration : 450
            easing.type: Easing.BezierSpline
            easing.bezierCurve: GlobalStates.overlayOpen ? Appearance.animationCurves.expressiveDefaultSpatial : Appearance.animationCurves.emphasizedDecel
        }
    }
    property real contentRadius: radius - padding

    // Resizing
    function getXResizeDirection(x) {
        return (x < root.resizeMargin) ? -1 : (x > root.width - root.resizeMargin) ? 1 : 0
    }
    function getYResizeDirection(y) {
        return (y < root.resizeMargin) ? -1 : (y > root.height - root.resizeMargin) ? 1 : 0
    }
    hoverEnabled: true
    property bool resizable: true
    property bool resizing: false
    property int resizeXDirection: getXResizeDirection(mouseX)
    property int resizeYDirection: getYResizeDirection(mouseY)
    draggable: GlobalStates.overlayOpen
    drag.target: undefined
    animateXPos: !dragHandler.active
    // the fold moves the widget a frame at a time to keep its body still: a glide on top would swing it
    animateYPos: !dragHandler.active && !headerFold.running
    z: dragHandler.active ? 2 : 1
    cursorShape: {
        if (dragHandler.active) return root.resizing ? cursorShape : Qt.ArrowCursor;
        if (resizeMargin < mouseX && mouseX < width - resizeMargin &&
            resizeMargin < mouseY && mouseY < height - resizeMargin) {
            return Qt.ArrowCursor;
        } else {
            if (!root.resizable) return Qt.ArrowCursor;
            const dragIsLeft = mouseX < width / 2
            const dragIsTop = mouseY < height / 2
            if ((dragIsLeft && dragIsTop) || (!dragIsLeft && !dragIsTop)) {
                return Qt.SizeFDiagCursor
            } else {
                return Qt.SizeBDiagCursor
            }
        }
    }

    // Positioning & sizing
    // The saved spot may be for a bigger screen (the defaults are picked on 1920x1080): shown inside
    // this one, whole and so within reach of its title bar. The saved value is left as it is, so a
    // larger screen gets the widget back where it was put. Not before the screen's size is known.
    function onScreen(pos, size, limit) {
        return limit > 0 ? Math.max(0, Math.min(pos, limit - size)) : pos;
    }
    // The saved y is the top with the header shown. The header folds away when the overlay closes, and the widget
    // moves down by as much as has folded, so a pinned widget's body stays where it was put (a crosshair's mark on
    // the aim point); kept on the screen at its open height.
    function onScreenY(pos) {
        const folded = root.openHeaderHeight - root.headerHeight;
        return onScreen(pos, root.height + folded, root.parent?.height ?? 0) + folded;
    }
    x: Math.round(onScreen(persistentStateEntry.x, root.width, root.parent?.width ?? 0)) // Round or it'll be blurry
    y: Math.round(onScreenY(persistentStateEntry.y)) // Round or it'll be blurry
    pinned: persistentStateEntry.pinned
    clickthrough: persistentStateEntry.clickthrough
    drag {
        minimumX: 0
        minimumY: 0
        maximumX: root.parent?.width - root.width
        maximumY: root.parent?.height - root.height
    }
    opacity: (GlobalStates.overlayOpen || !clickthrough) ? 1.0 : Config.options.overlay.clickthroughOpacity

    // Guarded states & registration funcs
    property bool open: Persistent.states.overlay.open.includes(root.identifier)
    property bool actuallyPinned: pinned && open
    property bool actuallyClickable: !clickthrough && actuallyPinned && open
    onActuallyPinnedChanged: reportPinnedState();
    onActuallyClickableChanged: reportClickableState();
    function reportPinnedState() {
        OverlayContext.pin(identifier, actuallyPinned);
    }
    function reportClickableState() {
        OverlayContext.registerClickableWidget(contentItem, actuallyClickable);
    }

    // Self-registeration with OverlayContext
    Component.onCompleted: {
        reportPinnedState();
        reportClickableState();
    }

    // Without this the overlay layer surface stays mapped for the rest of the session, masking
    // input against an item that no longer exists.
    Component.onDestruction: {
        OverlayContext.pin(root.identifier, false);
        OverlayContext.registerClickableWidget(root.contentItem, false);
    }

    Connections {
        target: OverlayContext
        function onRequestCenter(identifier) {
            if (identifier === root.identifier) {
                root.center()
            }
        }
    }

    // Hooks
    onPressed: (event) => {
        // We're only interested in handling resize here
        // Early returns
        if (!root.resizable) return;
        if (root.resizeMargin < event.x && event.x < root.width - root.resizeMargin &&
            root.resizeMargin < event.y && event.y < root.height - root.resizeMargin) {
            return;
        }
        // Resizing setup
        root.resizing = true;
        root.resizeXDirection = getXResizeDirection(event.x);
        root.resizeYDirection = getYResizeDirection(event.y);
        if (root.resizeYDirection !== 0 && root.resizeXDirection === 0) {
            root.resizeXDirection = event.x < root.width / 2 ? -1 : 1;
        } else if (root.resizeXDirection !== 0 && root.resizeYDirection === 0) {
            root.resizeYDirection = event.y < root.height / 2 ? -1 : 1;
        }
    }
    // a press on the border with no drag never starts the DragHandler, whose end is the other place this is cleared:
    // left set, the next drag by the title resized the widget instead of moving it
    onReleased: root.resizing = false
    onPositionChanged: (event) => {
        if (!resizing) return;
        contentContainer.implicitWidth = Math.max(root.persistentStateEntry.width + dragHandler.xAxis.activeValue * root.resizeXDirection, root.minimumWidth);
        contentContainer.implicitHeight = Math.max(root.persistentStateEntry.height + dragHandler.yAxis.activeValue * root.resizeYDirection, root.minimumHeight);
        const negativeXDrag = root.resizeXDirection === -1;
        const negativeYDrag = root.resizeYDirection === -1;
        const wantedX = root.persistentStateEntry.x + (negativeXDrag ? dragHandler.xAxis.activeValue : 0)
        const wantedY = root.persistentStateEntry.y + (negativeYDrag ? dragHandler.yAxis.activeValue : 0)
        const negativeXDragLimit = root.persistentStateEntry.x + root.persistentStateEntry.width - contentContainer.implicitWidth;
        const negativeYDragLimit = root.persistentStateEntry.y + root.persistentStateEntry.height - contentContainer.implicitHeight;
        root.x = negativeXDrag ? Math.min(wantedX, negativeXDragLimit) : wantedX;
        root.y = negativeYDrag ? Math.min(wantedY, negativeYDragLimit) : wantedY;
    }
    DragHandler {
        id: dragHandler
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        target: (root.draggable && !root.resizing) ? root : null
        onActiveChanged: { // Handle drag release
            if (!active) {
                root.resizing = false;
                root.savePosition();
            }
        }
        xAxis.minimum: 0
        xAxis.maximum: root.parent?.width - root.width
        yAxis.minimum: 0
        yAxis.maximum: root.parent?.height - root.height
    }

    function close() {
        Persistent.states.overlay.open = Persistent.states.overlay.open.filter(type => type !== root.identifier);
    }

    function togglePinned() {
        persistentStateEntry.pinned = !persistentStateEntry.pinned;
    }

    function toggleClickthrough() {
        persistentStateEntry.clickthrough = !persistentStateEntry.clickthrough;
    }

    function savePosition(xPos = root.x, yPos = root.y, width = contentContainer.implicitWidth, height = contentContainer.implicitHeight) {
        persistentStateEntry.x = Math.round(xPos);
        persistentStateEntry.y = Math.round(yPos);
        persistentStateEntry.width = Math.round(width);
        persistentStateEntry.height = Math.round(height);
    }

    function center() {
        const targetX = (root.parent.width - border.column.width) / 2 - root.resizeMargin
        const targetY = (root.parent.height - contentContainer.height) / 2 - border.titleBar.implicitHeight - root.resizeMargin
        root.x = targetX
        root.y = targetY
        root.savePosition(targetX, targetY)
    }

    visible: GlobalStates.overlayOpen || actuallyPinned
    implicitWidth: border.column.implicitWidth + resizeMargin * 2
    implicitHeight: border.column.implicitHeight + resizeMargin * 2

    TacitCard {
        id: border
        anchors {
            fill: parent
            margins: root.resizeMargin
        }
        glyph: root.materialSymbol
        title: root.title
        fancy: root.fancyBorders
        // Near-opaque ground, as the palette's: the window sits over whatever is on the desktop.
        // A pinned widget keeps it with the overlay closed, unless it draws its own picture.
        grounded: GlobalStates.overlayOpen || root.pinnedGround
        masked: GlobalStates.overlayOpen || root.pinnedGround
        radius: root.radius
        // Closed, a pinned widget keeps only its body.
        headerHeight: root.headerHeight
        headerShown: GlobalStates.overlayOpen

        headerData: [
            OverlayRoundButton {
                visible: root.showCenterButton
                glyph: "recenter"
                onClicked: root.center()
            },
            OverlayRoundButton {
                visible: (root.pinned && root.showClickabilityButton)
                glyph: "mouse"
                on: !root.clickthrough
                onClicked: root.toggleClickthrough()
            },
            OverlayRoundButton {
                glyph: "keep"
                on: root.pinned
                onClicked: root.togglePinned()
            },
            OverlayRoundButton {
                glyph: "close"
                onClicked: root.close()
            }
        ]

        // Content
        Item {
            id: contentContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: root.fancyBorders ? root.padding : 0
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            implicitWidth: Math.max(root.persistentStateEntry.width, root.minimumWidth)
            implicitHeight: Math.max(root.persistentStateEntry.height, root.minimumHeight)
            children: [root.contentItem]
        }
    }
}
