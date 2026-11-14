import QtQuick
import QtQuick.Layouts
import Tacit.Kit as K
import "mail-store.js" as MailStore

Column {
    id: message

    required property var controller
    required property var entry
    required property real textInset
    required property bool expanded
    required property bool hasPrevious
    required property bool hasNext
    required property bool actionsVisible
    signal toggleRequested()
    property alias replySlot: replySlot
    property Component replyEditorComponent

    readonly property var t: K.Kit.tokens
    readonly property real textWidth: Math.max(0, width - textInset)
    property real followingTickOffset: -1
    property real senderRowHeight: t.space.page + (expanded ? t.space.m : 0)

    Behavior on senderRowHeight {
        NumberAnimation {
            duration: K.Kit.ms(K.Kit.motion(message.expanded ? "arriveSmall" : "leave").ms)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: K.Kit.motion(message.expanded ? "arriveSmall" : "leave").curve
        }
    }
    property bool animateExpansion: true
    readonly property bool layoutPending: htmlBody.loading || htmlArrival.running
    readonly property real tickY: Math.round(senderRowHeight / 2)
    readonly property string senderInk: expanded ? "main" : "meta"
    readonly property string recipientText: {
        const recipients = entry.to ? controller.names(entry.to) : qsTr("you");
        const cc = entry.cc ? controller.names(entry.cc) : "";
        return qsTr("To %1").arg(cc ? qsTr("%1, %2").arg(recipients).arg(cc) : recipients);
    }

    Item {
        id: header

        x: message.textInset
        width: message.textWidth
        height: message.expanded ? Math.max(message.senderRowHeight, recipients.y + recipients.implicitHeight) : message.senderRowHeight
        objectName: (message.entry.historical ? "history-" : message.entry.context ? "contextHeader-" : "messageHeader-") + message.entry.id
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: (message.expanded ? qsTr("Collapse %1") : qsTr("Expand %1")).arg(message.entry.from)
        Accessible.onPressAction: message.toggleRequested()

        Rectangle {
            anchors.fill: parent
            radius: message.t.radius.row
            color: message.t.inkMain
            opacity: headerTap.pressed ? message.t.wash.pressed : 0
            Behavior on opacity {
                NumberAnimation { duration: K.Kit.ms(message.t.motion.hover.ms) }
            }
            Accessible.ignored: true
        }

        K.FocusRing { shown: header.activeFocus && K.Kit.focusVisible }
        Keys.onPressed: event => {
            K.Kit.focusVisible = true;
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                message.toggleRequested();
                event.accepted = true;
            }
        }

        Rectangle {
            visible: message.followingTickOffset >= 0
            x: message.t.space.l - header.x
            y: message.tickY
            width: 1
            height: Math.max(0, message.height + message.followingTickOffset - message.tickY)
            color: Qt.alpha(message.t.inkMain, message.t.wash.current + 0.04)
            Accessible.ignored: true
        }

        Rectangle {
            visible: message.hasPrevious || message.hasNext || message.followingTickOffset >= 0
            x: Math.round(message.t.space.l - (width - 1) / 2) - header.x
            y: message.tickY
            width: message.hasNext ? message.t.space.s : message.t.space.l
            height: 1
            color: message.hasNext ? message.t.inkMeta : message.t.inkMain
            Accessible.ignored: true
        }

        RowLayout {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: message.senderRowHeight
            anchors.rightMargin: message.t.space.s
            spacing: message.t.space.m

            K.TacitText {
                Layout.preferredWidth: message.expanded ? implicitWidth : Math.min(message.t.width.rail / 2 - message.t.space.l, message.textWidth / 3)
                Layout.maximumWidth: message.textWidth / 2
                Layout.minimumWidth: 0
                text: message.entry.from
                weight: message.entry.primary || message.entry.unread ? "strong" : "medium"
                ink: message.senderInk
                elide: Text.ElideRight
            }

            K.TacitText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                objectName: "collapsedPreview-" + message.entry.id
                horizontalAlignment: Text.AlignLeft
                text: message.expanded ? "" : message.controller.highlight((message.entry.body ?? "").replace(/\s+/g, " "))
                textFormat: Text.StyledText
                ink: "quiet"
                elide: Text.ElideRight
            }

            K.TacitText {
                text: {
                    switch (message.entry.status) {
                    case "queued": return message.entry.date ?? "";
                    case "sending": return qsTr("%1 · Sending").arg(message.entry.date);
                    case "sent": return qsTr("%1 · Sent").arg(message.entry.date);
                    default: {
                        if (!Number.isFinite(message.entry.timestamp))
                            return message.entry.date ?? "";
                        const date = new Date(message.entry.timestamp);
                        return MailStore.threadDay(date, new Date()) + " " + Qt.formatTime(date, "HH:mm");
                    }
                    }
                }
                size: "meta"
                ink: ["queued", "sending"].includes(message.entry.status) ? "main" : "meta"
            }

            K.Symbol {
                text: message.expanded ? "expand_less" : "expand_more"
                size: message.t.icon.rail
                color: message.t.inkMeta
                Accessible.ignored: true
            }
        }
        K.TacitText {
            id: recipients
            visible: message.expanded
            y: message.tickY + message.t.space.m
            width: message.textWidth - message.t.space.s
            text: message.recipientText
            size: "meta"
            ink: "quiet"
            wrapMode: Text.Wrap
        }

        MouseArea {
            id: headerTap
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // AppKit can restore the arrow during pointer movement over the native preview.
            onContainsMouseChanged: {
                if (typeof previewWindow !== "undefined" && previewWindow.setPointingCursor)
                    previewWindow.setPointingCursor(containsMouse);
            }
            onPositionChanged: {
                if (containsMouse && typeof previewWindow !== "undefined" && previewWindow.setPointingCursor)
                    previewWindow.setPointingCursor(true);
            }
            onClicked: {
                K.Kit.focusVisible = false;
                header.forceActiveFocus(Qt.MouseFocusReason);
                message.toggleRequested();
            }
        }
    }

    MailMessageBody {
        objectName: (message.entry.historical ? "historyBody-" : "messageBody-") + message.entry.id
        expanded: message.expanded
        animateExpansion: message.animateExpansion

        Column {
            x: message.textInset
            width: message.textWidth
            spacing: message.t.space.m

            Item {
                width: parent.width
                height: message.t.space.m
            }

            Rectangle {
                visible: message.entry.status === "queued"
                width: parent.width
                height: queueStatus.implicitHeight + 2 * message.t.space.m
                radius: message.t.radius.panel
                color: Qt.alpha(message.t.inkMain, message.t.wash.action)

                Column {
                    id: queueStatus
                    x: message.t.space.m
                    y: message.t.space.m
                    width: parent.width - 2 * x
                    spacing: message.t.space.s

                    RowLayout {
                        width: parent.width
                        spacing: message.t.space.s

                        K.Symbol {
                            text: "clock"
                            Layout.alignment: Qt.AlignTop
                        }

                        K.TacitText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            weight: "strong"
                            text: qsTr("Waiting to send")
                        }
                    }

                    K.TacitText {
                        width: parent.width
                        wrapMode: Text.Wrap
                        ink: "sec"
                        text: qsTr("Mail sends this message automatically when you are back online.")
                    }

                    Flow {
                        width: parent.width
                        spacing: message.t.space.l

                        MailAction { text: qsTr("Retry sending"); onActivated: message.controller.act("retry") }
                    }
                }
            }

            K.TacitText {
                visible: !!message.entry.excerpt
                text: qsTr("Excerpt from the original message")
                size: "meta"
                ink: "meta"
            }

            Item {
                id: htmlPresentation

                property real reveal: 0
                width: message.textWidth
                height: 0
                visible: state !== ""
                clip: true
                state: htmlBody.item?.ready ? "ready" : htmlBody.loading ? "loading" : ""

                Loader {
                    id: htmlBody
                    readonly property string html: message.entry.bodyHtml ?? message.entry.body_html ?? ""
                    readonly property bool loading: status === Loader.Loading || !!item?.loading
                    active: message.expanded && !message.entry.excerpt && html.trim() !== ""
                    width: parent.width
                    z: 0
                    // Keep the surface paintable during the covered layout phase.
                    opacity: Math.max(0.001, htmlPresentation.reveal)
                    enabled: htmlPresentation.reveal === 1

                    Component.onCompleted: setSource(Qt.resolvedUrl("MailHtmlView.qml"), {
                        html: Qt.binding(() => htmlBody.html)
                    })

                    Connections {
                        target: htmlBody.item
                        function onExternalLinkRequested(link) { Qt.openUrlExternally(link); }
                    }
                }

                Column {
                    id: htmlProgress
                    readonly property real loadValue: htmlBody.item?.progress ?? 0
                    width: parent.width
                    z: 2
                    spacing: message.t.space.s
                    opacity: htmlBody.loading && loadValue < 1 ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        enabled: htmlProgress.loadValue >= 1
                        SequentialAnimation {
                            PauseAnimation { duration: K.Kit.ms(K.Kit.motion("hover").ms) }
                            NumberAnimation {
                                duration: K.Kit.ms(K.Kit.motion("fadeFast").ms)
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: K.Kit.motion("fadeFast").curve
                            }
                        }
                    }

                    K.TacitText {
                        text: qsTr("Loading message…")
                        size: "meta"
                        ink: "sec"
                        Accessible.ignored: true
                    }

                    Item {
                        width: parent.width
                        height: progressBar.implicitHeight

                        K.Progress {
                            id: progressBar
                            objectName: "htmlLoadProgress"
                            anchors.fill: parent
                            visible: htmlProgress.loadValue < 1
                            value: htmlProgress.loadValue
                            label: qsTr("Loading message")
                        }

                        K.Progress {
                            objectName: "htmlLoadComplete"
                            anchors.fill: parent
                            visible: htmlProgress.loadValue >= 1
                            value: 1
                            label: progressBar.label
                        }
                    }
                }

                states: [
                    State {
                        name: "loading"
                        PropertyChanges { htmlPresentation.height: htmlProgress.implicitHeight }
                    },
                    State {
                        name: "ready"
                        PropertyChanges { htmlPresentation.height: htmlBody.implicitHeight }
                        PropertyChanges { htmlPresentation.reveal: 1 }
                    }
                ]

                transitions: Transition {
                    id: htmlArrival
                    enabled: message.animateExpansion
                    from: "loading"
                    to: "ready"
                    SequentialAnimation {
                        NumberAnimation {
                            target: htmlPresentation
                            property: "height"
                            duration: K.Kit.ms(K.Kit.motion("arriveSmall").ms)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: K.Kit.motion("arriveSmall").curve
                        }
                        // Let Chromium paint the newly exposed viewport before revealing it.
                        PauseAnimation { duration: 140 }
                        NumberAnimation {
                            target: htmlPresentation
                            property: "reveal"
                            duration: K.Kit.ms(K.Kit.motion("fade").ms)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: K.Kit.motion("fade").curve
                        }
                    }
                }
            }

            Repeater {
                model: htmlPresentation.visible ? [] : (message.entry.body ?? "").split("\n\n")
                delegate: K.TacitText {
                    required property string modelData
                    width: message.textWidth
                    text: message.controller.highlight(modelData, message.t.inkOnAccent, message.t.accent)
                    textFormat: message.controller.ui.searching ? Text.RichText : Text.StyledText
                    size: "body"
                    wrapMode: Text.Wrap
                    lineHeight: 1.3
                }
            }

            MailAttachmentStrip {
                width: parent.width
                files: Array.from(message.entry.files ?? []).filter(file => !file.inline)
                onPreviewRequested: file => message.controller.act("preview", {file: file})
                onSaveRequested: files => message.controller.saveAttachment(files)
                visible: !message.entry.context && files.length > 0
            }

            K.TacitText {
                visible: !!message.entry.agent
                text: message.entry.edited ? qsTr("↳ Drafted by your agent, edited by you") : qsTr("↳ Drafted by your agent")
                size: "meta"
                color: message.controller.agentInk
            }

            RowLayout {
                visible: message.expanded && message.actionsVisible
                opacity: htmlPresentation.visible ? htmlPresentation.reveal : 1
                enabled: opacity === 1
                Accessible.ignored: opacity === 0
                anchors.left: parent.left
                spacing: message.t.space.xl

                MailAction {
                    id: replyAction
                    objectName: message.entry.primary ? "reply" : "reply-" + message.entry.id
                    text: qsTr("Reply")
                    onActivated: message.controller.reply("Reply", false, message.entry.id)
                }

                MailAction {
                    id: replyAllAction
                    visible: message.controller.canReplyAll
                    objectName: message.entry.primary ? "replyAll" : "replyAll-" + message.entry.id
                    text: qsTr("Reply all")
                    onActivated: message.controller.reply("Reply all", false, message.entry.id)
                }

                MailAction {
                    id: forwardAction
                    objectName: message.entry.primary ? "forward" : "forward-" + message.entry.id
                    text: qsTr("Forward")
                    onActivated: message.controller.reply("Forward", false, message.entry.id)
                }
            }

            Item { width: 1; height: message.t.space.s }
        }
    }

    Loader {
        id: replySlot
        x: message.textInset
        width: message.textWidth
        visible: status === Loader.Ready
        sourceComponent: message.replyEditorComponent
    }

    Rectangle {
        objectName: message.entry.historical ? "historyDivider-" + message.entry.id : ""
        visible: message.hasNext
        x: message.textInset
        width: message.textWidth
        height: 1
        color: Qt.alpha(message.t.inkMain, message.t.wash.hover + 0.02)
        Accessible.ignored: true
    }
}
