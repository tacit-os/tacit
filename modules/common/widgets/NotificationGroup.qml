import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

/**
 * A group of notifications from the same app.
 * Similar to Android's notifications
 */
MouseArea { // Notification group area
    id: root
    property var notificationGroup
    property var notifications: notificationGroup?.notifications ?? []
    property int notificationCount: notifications.length
    property bool multipleNotifications: notificationCount > 1
    property bool expanded: false
    property bool popup: false
    property bool flat: false
    readonly property bool plain: popup || flat
    property real padding: 10
    implicitHeight: background.implicitHeight

    property real dragConfirmThreshold: 70 // Drag further to discard notification
    property real dismissOvershoot: 20 // Account for gaps and bouncy animations
    property var qmlParent: root?.parent?.parent // There's something between this and the parent ListView
    property var parentDragIndex: qmlParent?.dragIndex
    property var parentDragDistance: qmlParent?.dragDistance
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff == 0 ? parentDragDistance : 
        Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 :
        dragIndexDiff == 1 ? (parentDragDistance * 0.3) :
        dragIndexDiff == 2 ? (parentDragDistance * 0.1) : 0

    function destroyWithAnimation(left = false) {
        root.qmlParent.resetDrag()
        background.anchors.leftMargin = background.anchors.leftMargin; // Break binding
        destroyAnimation.left = left;
        destroyAnimation.running = true;
    }

    hoverEnabled: true
    // The pointer resting on a popup stops its clock, and leaving starts it again (as the reply field does). Leaving used
    // to dismiss it on the spot, so a pointer crossing a popup on its way elsewhere took it away, a critical one too,
    // which has no clock and is meant to stay until it is dealt with.
    onContainsMouseChanged: {
        if (!root.popup) return;
        if (root.containsMouse) root.notifications.forEach(notif => {
            Notifications.cancelTimeout(notif.notificationId);
        });
        else root.notifications.forEach(notif => {
            notif.timer?.restart();
        });
    }

    SequentialAnimation { // Drag finish animation
        id: destroyAnimation
        property bool left: true
        running: false

        ParallelAnimation {
            NumberAnimation {
                target: background.anchors
                property: "leftMargin"
                to: (root.width + root.dismissOvershoot) * (destroyAnimation.left ? -1 : 1)
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
            // a popup row also gives its height back while it slides, so the rows below and
            // the panel move with it instead of jumping when it is gone
            NumberAnimation {
                target: root
                property: "height"
                to: root.popup ? 0 : root.height
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }
        onFinished: () => {
            root.notifications.forEach((notif) => {
                Qt.callLater(() => {
                    Notifications.discardNotification(notif.notificationId);
                });
            });
        }
    }

    // caelestia notifications/Notification.qml:83-90: a left click invokes the notification's
    // action when it has exactly one (or a "default" one); a group of several expands instead.
    function activate() {
        if (root.multipleNotifications) {
            root.toggleExpanded();
            return;
        }
        const notif = root.notifications[0];
        if (!notif)
            return;
        const actions = notif.actions ?? [];
        const action = actions.find(a => a.identifier === "default") ?? (actions.length === 1 ? actions[0] : null);
        if (action)
            Notifications.attemptInvokeAction(notif.notificationId, action.identifier);
        else if (Notifications.open(notif))
            root.destroyWithAnimation();
        else if (root.popup)
            GlobalStates.notificationCenterOpen = true;   // nothing to invoke: open the centre
    }

    // A popup with something to do right away (its own buttons, a reply field, a file to open)
    // arrives with that visible: an action behind an expand is not a quick action.
    // It takes its full height at once (no height animation on the way in), so the panel
    // grows once, to the right size.
    property bool heightAnimated: true
    // A popup whose notifications have all timed out: slide off and collapse, then the
    // service drops it (NotificationPopupList leaves it out of the panel's height at once).
    readonly property bool leaving: root.popup && root.notifications.length > 0 && root.notifications.every(n => n.leaving)
    onLeavingChanged: if (root.leaving) leaveAnimation.start()
    ParallelAnimation {
        id: leaveAnimation
        NumberAnimation {
            target: root
            property: "x"
            to: root.width + root.dismissOvershoot
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "opacity"
            to: 0
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "height"
            to: 0
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }
    // Expanded by arrival, not by the user: folds back to the compact stack when a second
    // notification joins (five chats with five reply fields would fill the popup's cap and
    // hide every other group). A group the user opened stays open.
    property bool autoExpanded: false
    Component.onCompleted: {
        const n = root.notifications[0];
        if (root.popup && root.notifications.length === 1 && n
            && ((n.actions ?? []).length > 0 || n.hasInlineReply || Notifications.fileFor(n) !== "")) {
            root.heightAnimated = false;
            root.expanded = true;
            root.autoExpanded = true;
            settleTimer.start();
        }
    }
    onNotificationCountChanged: {
        if (root.popup && root.autoExpanded && root.expanded && root.notificationCount > 1) {
            root.autoExpanded = false;
            root.expanded = false;
        }
    }
    Timer {
        id: settleTimer
        interval: 500
        onTriggered: root.heightAnimated = true
    }

    Connections {
        target: Notifications
        function onExpandRequested(appName) {
            if (!root.expanded && (root.notificationGroup?.appName ?? "") === appName)
                root.toggleExpanded();
        }
    }

    function toggleExpanded() {
        // The group never tweens its own height: a stack unfolding is animated by the panel
        // around it, a row expanding by the row itself. Two tweens on one height raced.
        Notifications.bumpExpanding();
        root.autoExpanded = false;
        root.expanded = !root.expanded;
    }

    DragManager { // Drag manager
        id: dragManager
        anchors.fill: parent
        interactive: !expanded
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        // A drag that moved is not a click: the release must not activate the row (a popup
        // with nothing to open would open the centre under the hand that just dismissed it).
        property bool dragged: false
        onPressed: {
            dragged = false;
            if (mouse.button === Qt.RightButton) 
                root.toggleExpanded();
        }

        onClicked: (mouse) => {
            if (dragged)
                return;
            if (mouse.button === Qt.MiddleButton) {
                root.destroyWithAnimation();
                return;
            }
            if (mouse.button === Qt.LeftButton)
                root.activate();
        }

        onDraggingChanged: () => {
            if (dragging) {
                root.qmlParent.dragIndex = root.index ?? root.parent.children.indexOf(root);
            }
        }

        onDragDiffXChanged: () => {
            if (Math.abs(dragDiffX) > 8)
                dragged = true;
            root.qmlParent.dragDistance = dragDiffX;
        }

        onDragReleased: (diffX, diffY) => {
            if (Math.abs(diffX) > root.dragConfirmThreshold)
                root.destroyWithAnimation(diffX < 0);
            else 
                dragManager.resetDrag();
        }
    }

    // In the popup the group is a flat row inside the docked panel (the panel carries the
    // frost); in the sidebar it is a card. Urgency shows on the app icon only.
    Rectangle { // Background of the notification
        id: background
        anchors.left: parent.left
        width: parent.width
        color: root.plain ? "transparent" : Appearance.colors.colLayer2
        radius: root.plain ? 0 : Appearance.rounding.normal
        anchors.leftMargin: root.xOffset

        // Hairline between groups in the docked popup.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: root.padding
            anchors.rightMargin: root.padding
            height: 1
            visible: root.plain && (root.index ?? 0) > 0
            color: Appearance.colors.colLayer0Border
        }

        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMoveSmall.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
        
        clip: true
        implicitHeight: root.expanded ? 
            row.implicitHeight + padding * 2 :
            Math.min(80, row.implicitHeight + padding * 2)



        RowLayout { // Left column for icon, right column for content
            id: row
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding
            spacing: 10

            NotificationAppIcon { // Icons
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: false
                image: root?.multipleNotifications ? "" : notificationGroup?.notifications[0]?.image ?? ""
                appIcon: root.notificationGroup?.appIcon
                appName: root.notificationGroup?.appName ?? ""
                iconKind: root?.multipleNotifications ? "" : notificationGroup?.notifications[0]?.iconKind ?? ""
                glyph: Notifications.appGlyphs[root.notificationGroup?.appName ?? ""] ?? ""
                summary: root.notificationGroup?.notifications[root.notificationCount - 1]?.summary
                message: NotificationUtils.isMessage(root.notificationGroup?.notifications[root.notificationCount - 1])
                urgency: root.notifications.some(n => n.urgency === NotificationUrgency.Critical.toString()) ? 
                    NotificationUrgency.Critical : NotificationUrgency.Normal
            }

            ColumnLayout { // Content
                Layout.fillWidth: true
                // a lone notification: the name line and the text breathe (Material 3 puts
                // a few dp between a notification's title and its text, never 0)
                spacing: expanded ? (root.multipleNotifications ? 
                    (notificationGroup?.notifications[root.notificationCount - 1].image != "") ? 35 : 
                    5 : 4) : 0
                // spacing: 00

                Item { // App name (or summary when there's only 1 notif) and time
                    id: topRow
                    // spacing: 0
                    Layout.fillWidth: true
                    property real fontSize: Appearance.font.pixelSize.smaller
                    property bool showAppName: root.multipleNotifications
                    implicitHeight: Math.max(topTextRow.implicitHeight, expandButton.implicitHeight)

                    RowLayout {
                        id: topTextRow
                        anchors.left: parent.left
                        anchors.right: expandButton.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        StyledText {
                            id: appName
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            text: (topRow.showAppName ?
                                notificationGroup?.appName :
                                notificationGroup?.notifications[0]?.summary) || ""
                            font.pixelSize: topRow.showAppName ?
                                topRow.fontSize :
                                Appearance.font.pixelSize.small
                            // a person's name carries weight; an app's status line does not
                            font.weight: (!topRow.showAppName && NotificationUtils.isMessage(notificationGroup?.notifications[0])) ? Font.Medium : Font.Normal
                            // a lone critical notification: its summary in the error colour, as in the rows
                            color: topRow.showAppName ?
                                Appearance.colors.colSubtext :
                                (notificationGroup?.notifications[0]?.urgency == NotificationUrgency.Critical ?
                                    Appearance.colors.colError : Appearance.colors.colOnLayer2)
                        }
                        StyledText {
                            id: timeText
                            // Layout.fillWidth: true
                            Layout.rightMargin: 10
                            horizontalAlignment: Text.AlignLeft
                            // a lone row shows the sender's name, so the app goes here: "WhatsApp · Now"
                            text: {
                                const when = NotificationUtils.getFriendlyNotifTimeString(notificationGroup?.time);
                                const app = notificationGroup?.appName ?? "";
                                return (!topRow.showAppName && app.length > 0 && app !== notificationGroup?.notifications[0]?.summary)
                                    ? `${app} · ${when}` : when;
                            }
                            font.pixelSize: topRow.fontSize
                            color: Appearance.colors.colSubtext
                        }
                    }
                    NotificationGroupExpandButton {
                        id: expandButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        count: root.notificationCount
                        expanded: root.expanded
                        fontSize: topRow.fontSize
                        onClicked: { root.toggleExpanded() }
                        altAction: () => { root.toggleExpanded() }

                        StyledToolTip {
                            text: Translation.tr("Tip: right-clicking a group\nalso expands it")
                        }
                    }
                }

                StyledListView { // Notification body (expanded)
                    id: notificationsColumn
                    implicitHeight: contentHeight
                    Layout.fillWidth: true
                    spacing: expanded ? 5 : 3
                    // clip: true
                    interactive: false
                    model: ScriptModel {
                        values: root.expanded ? root.notifications.slice().reverse() : 
                            root.notifications.slice().reverse().slice(0, 2)
                    }
                    delegate: NotificationItem {
                        required property int index
                        required property var modelData
                        notificationObject: modelData
                        expanded: root.expanded
                        heightAnimated: root.heightAnimated
                        onlyNotification: (root.notificationCount === 1)
                        opacity: (!root.expanded && index == 1 && root.notificationCount > 2) ? 0.5 : 1
                        visible: root.expanded || (index < 2)
                        anchors.left: parent?.left
                        anchors.right: parent?.right
                    }
                }

            }
        }
    }
}
