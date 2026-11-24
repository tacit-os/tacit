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
    readonly property bool quotedHistoryExpanded: controller.quotedHistoryExpansion?.[entry.id] === true
    readonly property var bodyParts: entry.excerpt ? null : (entry.bodyParts ?? entry.body_parts ?? null)
    readonly property string preparedHTML: MailStore.quotedBodyHTML(bodyParts?.html,
        entry.bodyHtml ?? entry.body_html ?? "")
    readonly property string preparedText: MailStore.quotedBodyText(bodyParts?.text,
        entry.body ?? "", false)
    readonly property bool hasQuotedHistory: (htmlBody.active && !htmlBody.failed
        ? bodyParts?.html : bodyParts?.text)?.some(part => part.kind === "quotedHistory") ?? false
    readonly property bool layoutPending: htmlBody.loading || htmlArrival.running
    readonly property real tickY: Math.round(senderRowHeight / 2)
    readonly property string senderInk: expanded ? "main" : "meta"
    readonly property string recipientAddresses: {
        const mailbox = controller.accounts.find(account =>
            (account.id || account.name) === MailStore.accountKey(entry));
        const to = entry.to || (!entry.outgoing ? mailbox?.email : "");
        return [to, entry.cc].filter(Boolean).join(", ");
    }
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
            x: Math.round(message.t.space.l - (width - 1) / 2) - header.x
            y: message.tickY
            width: message.hasNext ? message.t.space.s : message.t.space.l
            height: 1
            color: message.hasNext ? message.t.inkMeta : message.t.inkMain
            Accessible.ignored: true
        }

        RowLayout {
            z: 1
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: message.senderRowHeight
            anchors.rightMargin: message.t.space.s
            spacing: message.t.space.m

            Item {
                id: senderName
                objectName: "senderName-" + message.entry.id
                readonly property alias addressTooltip: senderTooltip
                Layout.preferredWidth: message.expanded ? implicitWidth : Math.min(message.t.width.rail / 2 - message.t.space.l, message.textWidth / 3)
                Layout.maximumWidth: message.textWidth / 2
                Layout.minimumWidth: 0
                implicitWidth: senderText.implicitWidth
                implicitHeight: senderText.implicitHeight

                K.TacitText {
                    id: senderText
                    anchors.fill: parent
                    text: message.entry.from
                    weight: message.entry.primary || message.entry.unread ? "strong" : "medium"
                    ink: message.senderInk
                    elide: Text.ElideRight
                }
                HoverHandler { id: senderHover }

                K.Tooltip {
                    id: senderTooltip
                    parent: senderName
                    text: message.entry.address ?? ""
                    shown: text.length > 0 && senderHover.hovered
                }
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
        Item {
            id: recipients
            objectName: "recipients-" + message.entry.id
            readonly property alias addressTooltip: recipientTooltip
            z: 1
            visible: message.expanded
            y: message.tickY + message.t.space.m
            width: Math.min(recipientLabel.implicitWidth, message.textWidth - message.t.space.s)
            implicitHeight: recipientLabel.implicitHeight
            height: implicitHeight

            K.TacitText {
                id: recipientLabel
                width: parent.width
                text: message.recipientText
                size: "meta"
                ink: "quiet"
                wrapMode: Text.Wrap
            }
            HoverHandler { id: recipientHover }
            K.Tooltip {
                id: recipientTooltip
                parent: recipients
                text: message.recipientAddresses
                shown: recipientHover.hovered && text.length > 0
            }
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
            id: bodyContents
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

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: imageActions.implicitWidth + 2 * message.t.space.l
                height: imageActions.implicitHeight + 2 * message.t.space.l
                radius: message.t.radius.slab
                color: Qt.alpha(message.t.inkMain, message.t.wash.hover)
                visible: message.expanded && htmlPresentation.policy === "ask_first"
                    && !!htmlBody.item?.imagePromptReady && !!htmlBody.item?.hasExternalImages
                    && (!!htmlPresentation.client || !htmlPresentation.imagesAllowed)

                Column {
                    id: imageActions
                    anchors.centerIn: parent
                    spacing: message.t.space.s

                    K.TacitText {
                        text: qsTr("External images")
                        size: "row"
                        ink: "meta"
                    }
                    Row {
                        leftPadding: message.t.space.m
                        rightPadding: message.t.space.m
                        spacing: 2 * message.t.space.m + message.t.space.s
                        MailAction {
                            objectName: "loadImages-" + message.entry.id
                            text: qsTr("Load images")
                            onActivated: message.controller.allowRemoteImages(message.entry.id)
                        }
                        MailAction {
                            text: qsTr("Always")
                            onActivated: htmlPresentation.requestPolicy("always")
                        }
                        MailAction {
                            text: qsTr("Never")
                            onActivated: htmlPresentation.requestPolicy("never")
                        }
                    }
                }
            }

            Item {
                id: htmlPresentation
                objectName: "htmlPresentation-" + message.entry.id

                readonly property var client: message.controller.mailboxClient
                // maild decides permission. These values only serve the standalone demo.
                readonly property string policy: client ? "ask_first"
                    : ({"Always": "always", "Never": "never"})[message.controller.settings.pictures] || "ask_first"
                readonly property bool imagesAllowed: !client && (policy === "always"
                    || (policy === "ask_first" && message.controller.approvedRemoteImages[message.entry.id] === true))

                function requestPolicy(value) {
                    if (client) client.imagePolicy(message.entry.id, value, 0);
                }

                Connections {
                    target: htmlPresentation.client
                    function onImagePolicyLoaded(id, revision, result, ok) {
                        if (id === message.entry.id && !ok)
                            message.controller.act("notice", {text: qsTr("Could not save image preferences.")});
                    }
                }
                property real reveal: 0
                readonly property bool cachedReady: !!htmlBody.item?.ready && !htmlBody.loading
                width: message.textWidth
                height: 0
                visible: state !== ""
                clip: true
                state: htmlBody.item?.displayReady ? "ready" : htmlBody.loading ? "loading" : ""

                Item {
                    id: htmlBody
                    objectName: "htmlSurface-" + message.entry.id
                    property var lease: null
                    readonly property var item: lease?.item ?? null
                    readonly property string html: message.preparedHTML
                    readonly property bool loading: !!lease && (lease.status === Loader.Loading || !!item?.loading)
                    readonly property bool failed: !!lease && (lease.status === Loader.Error
                        || (lease.status === Loader.Ready && !!item && !item.loading && !item.ready))
                    readonly property bool active: message.expanded && !message.entry.excerpt && html.trim() !== ""
                    readonly property var documentData: ({html, messageId: message.entry.id,
                        searchTerm: message.controller.ui.searching ? message.controller.ui.query : "",
                        background: message.controller.settings.htmlBackground ?? "none",
                        attachments: message.entry.files ?? [], client: message.controller.mailboxClient,
                        sources: message.entry.remoteImages ?? [], allowed: htmlPresentation.imagesAllowed,
                        historyExpanded: message.quotedHistoryExpanded})
                    property var cache: message.controller.htmlCache
                    property bool initialized: false
                    implicitHeight: lease?.implicitHeight ?? 0
                    width: parent.width
                    // Keep the mail's own background below the remote progress surface.
                    opacity: item?.displayReady ? 1 : 0
                    enabled: htmlPresentation.reveal === 1

                    function syncDocument() {
                        if (!initialized || !cache) return;
                        if (lease && (!active || lease.discard || lease.messageKey !== message.entry.id)) {
                            cache.release(lease, htmlBody);
                            lease = null;
                        }
                        if (active) lease = cache.acquire(message.entry.id, documentData, htmlBody);
                    }
                    onDocumentDataChanged: syncDocument()
                    onActiveChanged: syncDocument()
                    onCacheChanged: syncDocument()
                    Component.onCompleted: { initialized = true; syncDocument(); }
                    Component.onDestruction: if (cache && lease) cache.release(lease, htmlBody)
                }

                Column {
                    id: htmlProgress
                    readonly property real loadValue: htmlBody.item?.progress ?? 0
                    readonly property int imageCount: htmlBody.item?.imageCount ?? -1
                    readonly property int finishedImages: htmlBody.item?.finishedImages ?? 0
                    readonly property bool countingImages: imageCount > 0 && finishedImages < imageCount
                    width: parent.width
                    z: 2
                    spacing: message.t.space.s
                    visible: htmlBody.loading && countingImages

                    K.TacitText {
                        text: qsTr("Loading images… %1 of %2 finished").arg(htmlProgress.finishedImages).arg(htmlProgress.imageCount)
                        size: "meta"
                        ink: "sec"
                        Accessible.ignored: true
                    }

                    K.Progress {
                        objectName: "htmlLoadProgress"
                        width: parent.width
                        value: htmlProgress.loadValue
                        label: qsTr("Loading images")
                    }
                }

                states: [
                    State {
                        name: "loading"
                        PropertyChanges { htmlPresentation.height: htmlProgress.visible ? htmlProgress.implicitHeight : 0 }
                    },
                    State {
                        name: "ready"
                        PropertyChanges { htmlPresentation.height: htmlBody.implicitHeight }
                        PropertyChanges { htmlPresentation.reveal: 1 }
                    }
                ]

                transitions: Transition {
                    id: htmlArrival
                    from: "loading"
                    to: "ready"
                    SequentialAnimation {
                        NumberAnimation {
                            target: htmlPresentation
                            property: "height"
                            duration: message.animateExpansion ? K.Kit.ms(K.Kit.motion("arriveSmall").ms) : 0
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: K.Kit.motion("arriveSmall").curve
                        }
                        // Let Chromium paint the newly exposed viewport before revealing it.
                        PauseAnimation { duration: K.Kit.reducedMotion ? 0 : 140 }
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
                model: htmlBody.active && !htmlBody.failed
                    ? [] : message.preparedText.split("\n\n")
                delegate: K.TacitText {
                    required property string modelData
                    objectName: "plainMailParagraph"
                    width: message.textWidth
                    text: message.controller.highlight(modelData, message.t.inkOnAccent, message.t.accent)
                    textFormat: message.controller.ui.searching ? Text.RichText : Text.StyledText
                    size: "body"
                    cut: "main"
                    ink: message.controller.settings.bodyInk ?? "meta"
                    weight: "regular"
                    wrapMode: Text.Wrap
                    lineHeight: 1.3
                }
            }

            K.IconButton {
                id: quotedHistoryAction
                objectName: "quotedHistory-" + message.entry.id
                parent: htmlBody.active && !htmlBody.failed ? htmlBody : bodyContents
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: htmlBody.active && !htmlBody.failed ? parent.top : undefined
                anchors.topMargin: htmlBody.item?.quotedHistoryToggleY ?? 0
                z: 1
                visible: message.hasQuotedHistory
                symbol: message.quotedHistoryExpanded ? "expand_less" : "expand_more"
                label: message.quotedHistoryExpanded ? qsTr("Hide expanded content") : qsTr("Show clipped content")
                tip: label
                onActivated: message.controller.setQuotedHistoryExpanded(message.entry.id, !message.quotedHistoryExpanded)

            }

            MailMessageBody {
                id: quotedTextBody
                objectName: "quotedHistoryBlock-" + message.entry.id
                width: parent.width
                expanded: message.quotedHistoryExpanded && quotedTextBody.expandedHeight > 0
            visible: message.quotedHistoryExpanded || height > 0

                Item {
                    width: parent.width
                    height: plainQuoteContent.height

                    Rectangle {
                        objectName: "quotedHistoryHairline-" + message.entry.id
                        width: 1
                        height: parent.height
                        color: Qt.alpha(message.t.inkMain, message.t.wash.hover + 0.02)
                        Accessible.ignored: true
                    }

                    Column {
                        id: plainQuoteContent
                        x: message.t.space.m
                        width: parent.width - x
                        spacing: message.t.space.m
                        Repeater {
                            id: quoteParagraphs
                            model: (!htmlBody.active || htmlBody.failed)
                                && (message.quotedHistoryExpanded || quotedTextBody.height > 0)
                                ? (message.bodyParts?.text ?? []).filter(part => part.kind === "quotedHistory")
                                    .map(part => part.content).join("").split("\n\n") : []
                            delegate: K.TacitText {
                                required property string modelData
                                objectName: "plainMailParagraph"
                                width: plainQuoteContent.width
                                text: message.controller.highlight(modelData, message.t.inkOnAccent, message.t.accent)
                                textFormat: message.controller.ui.searching ? Text.RichText : Text.StyledText
                                size: "body"
                                cut: "main"
                                ink: message.controller.settings.bodyInk ?? "meta"
                                weight: "regular"
                                wrapMode: Text.Wrap
                                lineHeight: 1.3
                            }
                        }
                    }
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
