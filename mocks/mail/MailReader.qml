import QtQuick
import QtQuick.Layouts
import Tacit.Kit as K

Item {
    id:reader
    required property var controller
    readonly property var t:K.Kit.tokens
    readonly property var message:controller.selected
    readonly property bool inTrash: message?.folder === "Trash"
    readonly property bool inSpam: message?.folder === "Spam"
    readonly property bool restrictedFolder: inTrash || inSpam
    readonly property bool composing:controller.ui.view==="compose"
    readonly property bool showConversationHeader: !!message && !composing && !controller.ui.attachment
    readonly property bool editing:controller.ui.view==="draft"||composing
    property bool compact:false
    signal backRequested()
    readonly property real pageMargin:width>t.width.list?t.space.page:t.space.l
    readonly property real columnWidth: Math.max(0, Math.floor(Math.min(
        width - 2 * Math.max(pageMargin, textInset / 2 + focusRoom),
        contentStart + 80 * bodyMetrics.averageCharacterWidth)))
    readonly property real focusRoom:t.state.focusGap+t.state.focusRing
    readonly property real textInset:width<t.width.panel+t.space.page*2?t.space.xl:t.space.page
    readonly property real textWidth:columnWidth-textInset
    readonly property bool timelineVisible: !!message && !composing && !controller.ui.attachment
        && (entries.length > 1 || agentEntry.visible)
    readonly property real contentStart: timelineVisible
        ? Math.round(t.space.l - (t.space.l - 1) / 2) : textInset
    readonly property real columnX: (width - columnWidth - contentStart) / 2
    readonly property real textX:columnX+textInset

    K.TacitText {
        id: bodyTypography
        visible: false
        size: "body"
    }
    FontMetrics {
        id: bodyMetrics
        font: bodyTypography.font
    }
    readonly property bool queued: !!message?.replies.some(reply => reply.status === "queued")
    readonly property var entries: {
        if (!message)
            return [];
        const history = (message.history ?? []).map(entry => Object.assign({historical: true}, entry));
        const context = queued && !editing;
        if (!message.outgoing && (!context || history.length > 0)) {
            const body = context && message.id === "mara"
                       ? qsTr("Could you take a look at the navigation and the message header before Thursday? The interface should stay quiet, with the content doing most of the talking.")
                       : message.body;
            history.push(Object.assign({}, message, {
                primary: true,
                context: context,
                excerpt: body !== message.body,
                body: body,
                date: [message.day, message.time].filter(Boolean).join(" ")
            }));
        }
        history.push(...(message.replies ?? []).map(entry => Object.assign({outgoing: true, from: qsTr("You")}, entry)));
        if (message.backendAccount)
            history.sort((left, right) => left.timestamp - right.timestamp);
        return history;
    }
    readonly property int replySourceIndex: !editing || composing || controller.draft?.agent ? -1
        : entries.findIndex(entry => entry.id === controller.draft?.sourceId && entry.historical)
    readonly property Item inlineReplySlot: replySourceIndex >= 0 && threadRows.revision > 0
        ? (threadRows.itemAt(replySourceIndex)?.replySlot ?? null) : null
    readonly property Item editor: inlineReplySlot?.item ?? footerEditor.item
    readonly property string replySourceName: entries.find(entry => entry.id === controller.draft?.sourceId)?.from
        ?? message?.from ?? ""
    property string shownMessage:message?.id ?? ""
    property var collapsedMessages:({})
    function isExpanded(id){return !collapsedMessages[id];}
    function toggleMessage(id){var next=Object.assign({},collapsedMessages);next[id]=!next[id];collapsedMessages=next;}
    property bool attachmentDialogOpen: false
    signal attachRequested()
    onShownMessageChanged: {
        collapsedMessages = {};
        focusEditor();
    }
    property real readingPosition: 0
    property bool editorRevealPending: false
    readonly property bool preparingReply: !composing && editorRevealPending
    readonly property bool threadLayoutPending: {
        if (composing)
            return false;
        if (controller.threadQuery?.loading)
            return true;
        const revision = threadRows.revision;
        for (let index = 0; index < threadRows.count; ++index) {
            if (threadRows.itemAt(index)?.layoutPending)
                return true;
        }
        return false;
    }
    onThreadLayoutPendingChanged: if (editorRevealPending && !threadLayoutPending) Qt.callLater(revealEditor)
    onEditorChanged: if (editorRevealPending) Qt.callLater(revealEditor)

    onEditingChanged: {
        if (editing) {
            readingPosition = paper.contentY;
            focusEditor();
        } else {
            editorRevealPending = false;
            returnToReading.stop();
        }
    }

    function discardDraft() {
        if (returnToReading.running)
            return;
        if (composing || !K.Kit.ms(K.Kit.motion("arrive").ms)) {
            controller.act("discard");
            return;
        }
        returnToReading.from = paper.contentY;
        returnToReading.to = Math.min(paper.contentY, readingPosition);
        returnToReading.start();
    }

    NumberAnimation {
        id: returnToReading
        target: paper
        property: "contentY"
        duration: K.Kit.ms(K.Kit.motion("arrive").ms)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: K.Kit.motion("arrive").curve
        onFinished: reader.controller.act("discard")
    }
    Component.onCompleted: {
        if (editing)
            focusEditor();
        else if (message)
            focusEditor();
    }

    property string revealedReplyId: ""
    function revealPendingReply() {
        Qt.callLater(function () {
            if (reader.editing || reader.controller.ui.attachment)
                return;
            let index = reader.entries.length - 1;
            while (index >= 0 && !["queued", "sending"].includes(reader.entries[index].status))
                --index;
            const entry = reader.entries[index];
            if (!entry || entry.id === reader.revealedReplyId)
                return;
            const row = threadRows.itemAt(index);
            if (!row)
                return;
            reader.revealedReplyId = entry.id;
            if (reader.message?.id && !reader.message.outgoing)
                reader.collapsedMessages = Object.assign({}, reader.collapsedMessages, {[reader.message.id]: true});
            messageBlocks.forceLayout();
            thread.forceLayout();
            const top = row.mapToItem(thread, 0, 0).y + thread.y;
            if (top >= paper.contentY && top < paper.contentY + paper.height)
                return;
            const limit = Math.max(0, paper.contentHeight - paper.height);
            paper.contentY = Math.min(limit, Math.max(0, top - reader.t.space.m));
        });
    }
    function focusEditor() {
        editorRevealPending = true;
        Qt.callLater(revealEditor);
    }

    function revealEditor() {
        if (!editorRevealPending || (editing && !editor?.visible) || threadLayoutPending)
            return;
        paper.cancelFlick();
        messageBlocks.forceLayout();
        thread.forceLayout();
        if (editing)
            editor.focusBody();
        const limit = Math.max(0, paper.contentHeight - paper.height);
        const target = editing ? editor : threadRows.itemAt(entries.length - 1);
        const top = target?.mapToItem(paper.contentItem, 0, 0).y ?? 0;
        const position = editing && target
            ? Math.min(top, top + target.height - paper.height) : top;
        paper.contentY = composing ? 0 : Math.max(0, Math.min(limit, position));
        editorRevealPending = false;
    }
    Connections {
        target: reader.controller
        function onEditorRequested() { reader.focusEditor(); }
        function onSendStatusChanged() { reader.revealPendingReply(); }
    }
    component Rule:Rectangle {height:1;color:Qt.alpha(reader.t.inkMain,reader.t.wash.hover+0.02)}

    ColumnLayout {
        id:readingLayout
        x: reader.columnX - reader.focusRoom
        y: reader.t.space.m
        width:reader.columnWidth+reader.focusRoom*2;height:Math.max(0,reader.height-y)
        spacing: reader.showConversationHeader ? 0 : (reader.composing ? reader.t.space.xs : reader.t.space.l)
        RowLayout {
            id: messageToolbar
            objectName: "messageToolbar"
            visible: (reader.compact && !reader.showConversationHeader) || (reader.editing && !reader.showConversationHeader) || !!reader.controller.ui.attachment
            Layout.fillWidth: true
            Layout.leftMargin: reader.textInset + reader.focusRoom
            Layout.rightMargin: reader.focusRoom
            spacing: reader.t.space.xxl
            MailAction {objectName:visible ? "backToInbox" : "";visible:reader.compact;text:"Inbox";onActivated:reader.backRequested()}
            MailAction {objectName:visible ? "keepDraft" : "";visible:reader.editing && !reader.showConversationHeader;text:"Close, keep the draft";onActivated:reader.controller.act("keepDraft")}
            MailAction {visible:!!reader.controller.ui.attachment;text:"Back to message";onActivated:reader.controller.act("closePreview")}
        }
        Rule {
            visible: reader.composing
            Layout.fillWidth: true
            Layout.leftMargin: reader.textInset + reader.focusRoom
            Layout.rightMargin: reader.focusRoom
        }
        ColumnLayout {
            visible: reader.showConversationHeader
            Layout.fillWidth: true
            Layout.topMargin: messageToolbar.visible ? reader.t.space.l : 0
            spacing: reader.t.space.xs
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: reader.textInset + reader.focusRoom
                Layout.rightMargin: reader.focusRoom + reader.t.space.m
                spacing: reader.t.space.xl
                K.IconButton {
                    objectName: visible ? "backToInbox" : ""
                    visible: reader.compact && reader.showConversationHeader
                    symbol: "chevron_left"
                    label: qsTr("Back to Inbox")
                    tip: label
                    onActivated: reader.backRequested()
                }
                Item { Layout.fillWidth: true }
                MailAction {id:archiveAction;objectName:"archive";visible:!reader.restrictedFolder && !!reader.message&&!reader.controller.ui.attachment;text:"Archive";onActivated:reader.controller.act("move",{folder:"Archive"})}
                MailAction {objectName:"messageMore";visible:!reader.restrictedFolder && !!reader.message&&!reader.controller.ui.attachment;text:"More";onActivated:more.openAt(this,width-more.implicitWidth,height)}
                MailAction {
                    visible: reader.inTrash
                    text: qsTr("Restore thread")
                    onActivated: reader.controller.act("restoreTrash")
                }
                MailAction {
                    visible: reader.inSpam
                    text: qsTr("Mark as no spam")
                    onActivated: reader.controller.act("move", {folder: "Inbox"})
                }
                MailAction {
                    visible: reader.restrictedFolder
                    enabled: targets.length > 0 && !reader.controller.threadQuery?.loading
                    readonly property var targets: reader.entries.filter(entry => entry.folder === reader.message?.folder).map(entry => entry.id)
                    text: reader.inSpam ? qsTr("Delete") : qsTr("Delete thread")
                    confirm: targets.length === 1 ? qsTr("Delete 1 message for good?")
                        : qsTr("Delete %1 messages for good?").arg(targets.length)
                    risk: true
                    onActivated: reader.controller.act("deleteFolderThread", {ids: targets})
                }
            }
            Rule {
                Layout.fillWidth: true
                Layout.leftMargin: reader.textInset + reader.focusRoom
                Layout.rightMargin: reader.focusRoom
            }
        }
    Item {
        Layout.fillWidth:true;Layout.fillHeight:true;Layout.minimumHeight:0
        Layout.topMargin: reader.composing ? reader.t.space.l - reader.t.space.xs : 0
    Flickable {
        id:paper;objectName:"readingScroll"
        opacity: reader.preparingReply ? 0 : 1
        anchors.fill:parent
        contentWidth: width
        contentHeight: {
            const naturalHeight = thread.y + thread.height + reader.t.space.l;
            if (!reader.editing) {
                const latest = reader.entries[reader.entries.length - 1];
                const row = latest && ["queued", "sending"].includes(latest.status)
                    ? threadRows.itemAt(reader.entries.length - 1) : null;
                return row ? Math.max(naturalHeight, row.mapToItem(thread, 0, 0).y + thread.y + height)
                    : naturalHeight;
            }
            if (reader.composing || !footerEditor.visible)
                return naturalHeight;
            if (reader.controller.draft?.agent)
                return Math.max(naturalHeight, thread.y + footerEditor.y + height);
            const headingEnd = thread.y + conversationHeading.height;
            if (!reader.compact && naturalHeight - height > thread.y && naturalHeight - height < headingEnd)
                return headingEnd + height;
            return naturalHeight;
        }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id:thread
            x: reader.focusRoom
            y: reader.showConversationHeader ? reader.t.space.l : reader.t.space.xs
            width: reader.columnWidth
            spacing: 0
            Column {
                id: conversationHeading
                x: reader.textInset
                width: reader.textWidth
                spacing: reader.t.space.l
                ColumnLayout {
                    width: parent.width
                    spacing: reader.t.space.xs
                    MailHeadline {
                        objectName: "messageSubject"
                        Layout.fillWidth: true
                        text:reader.controller.ui.attachment?reader.controller.ui.attachment.name:reader.composing?"New message":reader.message?.subject ?? "Choose a message"
                    }
                    K.TacitText {
                        visible: reader.showConversationHeader
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        readonly property int count: (reader.message?.history?.length ?? 0) + (reader.message?.outgoing ? 0 : 1) + (reader.message?.replies?.length ?? 0)
                        text: reader.controller.ui.searching && reader.controller.ui.query.trim()
                            ? qsTr("%1 · Search for “%2”").arg(reader.message?.account ?? "").arg(reader.controller.ui.query.trim())
                            : count + " message" + (count === 1 ? "" : "s") + "  ·  " + (reader.message?.account ?? "")
                        size: "meta"
                        ink: "quiet"
                    }

                }
                Rule {
                    visible: reader.showConversationHeader
                    width: parent.width
                }
            }
            Loader {
                x: reader.textInset
                width: reader.textWidth
                active: !!reader.controller.ui.attachment
                visible: active
                sourceComponent: MailAttachmentPreview {
                    controller: reader.controller
                }
            }
            Item {
                visible:!!reader.message&&!reader.composing&&!reader.controller.ui.attachment
                width:parent.width;height:messageBlocks.height
                Column {
                    id: messageBlocks
                    width: parent.width
                    spacing: 0

                    Repeater {
                        id: threadRows
                        property int revision: 0
                        onItemAdded: revision++
                        onItemRemoved: revision++
                        model: reader.entries.length
                        delegate: MailThreadMessage {
                            required property int index
                            readonly property var modelData: reader.entries[index]

                            width: messageBlocks.width
                            controller: reader.controller
                            entry: modelData
                            textInset: reader.textInset
                            expanded: reader.editing && !reader.composing
                                ? (index === (reader.replySourceIndex >= 0 ? reader.replySourceIndex : reader.entries.length - 1))
                                    !== !!reader.collapsedMessages[modelData.id]
                                : modelData.backendAccount
                                    ? (index === reader.entries.length - 1) !== !!reader.collapsedMessages[modelData.id]
                                : modelData.historical ? !!modelData.expanded
                                : (modelData.historical ? !!reader.collapsedMessages[modelData.id] : reader.isExpanded(modelData.id))
                                    && !(modelData.context && reader.queued)
                            animateExpansion: !reader.preparingReply
                            hasPrevious: index > 0
                            hasNext: index + 1 < reader.entries.length
                            followingTickOffset: {
                                if (hasNext) {
                                    const next = threadRows.revision > 0 ? threadRows.itemAt(index + 1) : null;
                                    return next?.tickY ?? -1;
                                }
                                return agentEntry.visible ? agentEntry.tickOffset : draftTimeline.visible ? footerEditor.item.fromCenter : -1;
                            }
                            replyEditorComponent: index === reader.replySourceIndex && !reader.controller.ui.attachment ? editorComponent : null
                            actionsVisible: !reader.restrictedFolder && !modelData.context && !reader.editing && modelData.status !== "queued"
                            onToggleRequested: {
                                if (!reader.editing && entry.historical && !entry.backendAccount)
                                    reader.controller.act("expand", {id: entry.id});
                                else
                                    reader.toggleMessage(entry.id);
                            }
                        }
                    }
                    Item {
                        id: agentEntry
                        readonly property real tickOffset: Math.round(agentLayout.y + agentTitle.y + agentTitle.height / 2)
                        visible:!!reader.controller.agentDraft(reader.message?.id ?? "")&&!reader.editing
                        width:parent.width;height:agentLayout.implicitHeight+reader.t.space.l
                        Rectangle {
                            x: Math.round(reader.t.space.l - (width - 1) / 2)
                            y: agentEntry.tickOffset
                            width: reader.t.space.l
                            height: 1
                            color: reader.controller.agentInk
                            Accessible.ignored: true
                        }
                        ColumnLayout {
                            id:agentLayout
                            x:reader.textInset;width:reader.textWidth;spacing:reader.t.space.s
                            Rule {Layout.fillWidth:true}
                            K.TacitText {
                                id: agentTitle
                                Layout.fillWidth: true
                                Layout.topMargin: reader.t.space.s
                                wrapMode: Text.Wrap
                                text: qsTr("Your agent drafted a reply")
                                weight: "strong"
                                color: reader.controller.agentInk
                            }
                            MailAgentReason {
                                Layout.fillWidth: true
                                Layout.topMargin: reader.t.space.xs - agentLayout.spacing - leadingInset
                                controller: reader.controller
                                conversationId: reader.message?.id ?? ""
                            }
                            K.Slab {
                                tone: "default"
                                objectName: "reviewReply"
                                text: qsTr("Review reply")
                                onActivated: reader.controller.reply("Reply all", true)
                            }
                        }
                    }
                }
            }
            Rectangle {
                id: draftTimeline
                parent: paper.contentItem
                objectName: "draftTimeline"
                visible: reader.timelineVisible && footerEditor.visible && !!footerEditor.item
                x: thread.x + reader.t.space.l
                y: thread.y + footerEditor.y + Math.round(footerEditor.item?.fromCenter ?? 0)
                width: 1
                height: Math.max(0, (footerEditor.item?.writingBottom ?? 0) - Math.round(footerEditor.item?.fromCenter ?? 0))
                color: reader.t.accent
                Accessible.ignored: true

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: reader.t.space.l
                    height: draftTimeline.width
                    color: draftTimeline.color
                    Accessible.ignored: true
                }
            }
            Loader {
                id: footerEditor
                x: reader.textInset
                width: reader.textWidth
                active: reader.editing && reader.replySourceIndex < 0 && !reader.controller.ui.attachment
                visible: active
                sourceComponent: editorComponent
            }
        }
    }
    K.Glide {view:paper}
    K.ScrollBar {
        view: paper
        anchors.fill: paper
        anchors.rightMargin: -reader.t.space.m
    }
    }

    }

    Component {
        id: editorFooterComponent
        ColumnLayout {
            id: editorFooter
            objectName:"editorFooter"
            readonly property real availableWidth: Math.max(0, (reader.editor?.width ?? reader.textWidth)
                - 2 * (reader.editor?.panelPadding ?? 0))
            readonly property bool shortLabels: availableWidth < reader.t.width.panel + reader.t.space.page * 3
            readonly property real actionSpacing: shortLabels ? reader.t.space.m : reader.t.space.xxl
            spacing:reader.t.space.s
            GridLayout {
                Layout.fillWidth:true;Layout.minimumWidth:0
                columns: editorFooter.availableWidth >= attachActions.Layout.leftMargin + attachFileAction.implicitWidth + (agentDraftAction.visible ? agentDraftAction.implicitWidth + attachActions.spacing : 0) + sendActions.implicitWidth + columnSpacing * 2 ? 3 : 1
                columnSpacing:editorFooter.actionSpacing;rowSpacing:reader.t.space.s
                RowLayout {id: attachActions; Layout.leftMargin: reader.t.space.m; spacing:editorFooter.actionSpacing + reader.t.space.xs
                MailAction {id: attachFileAction; objectName:"attachFile";text:editorFooter.shortLabels ? qsTr("Attach file") : qsTr("Attach a file");onActivated:reader.attachRequested()}
                MailAction {id: agentDraftAction; visible:!reader.controller.draft?.agent;text:qsTr("Draft with agent");onActivated:{if(!reader.controller.draft.to.trim()){reader.controller.act("notice",{text:"Add a recipient first."});return;}reader.controller.act("draft",{agent:true,edited:false,body:"Hello,\n\nThank you for your time. I would like to follow up with you.\n\n"+(reader.controller.draft.account==="Work"?reader.controller.settings.workSignature:reader.controller.settings.personalSignature)});}}
                }
                Item {visible:parent.columns===3;Layout.fillWidth:true}
                RowLayout {id: sendActions; Layout.alignment:Qt.AlignRight;spacing:editorFooter.actionSpacing
                MailAction {objectName:"discardDraft";text:editorFooter.shortLabels ? qsTr("Move to trash") : qsTr("Move draft to Trash");onActivated:reader.discardDraft()}
                K.Slab {tone:"default";objectName:"sendDraft";text:"Send";waiting:!reader.controller.canSend;opacity:waiting ? 0.62 : 1;onActivated: reader.editor?.sendDraft()}
                }
            }
        }
    }

    Component {
        id: editorComponent
        MailEditor {
            id: draftEditor
            objectName: "mailEditor"
            controller: reader.controller
            newMessage: reader.composing
            animationsPaused: reader.attachmentDialogOpen
            replySourceName: reader.replySourceName
            footerComponent: editorFooterComponent
            availableHeight: newMessage ? Math.max(0, paper.height - thread.y - footerEditor.y - reader.t.space.l) : 0
            maximumImageHeight: Math.max(1, paper.height * 0.45)
            maximumWritingHeight: Math.max(120, availableHeight - 160)
            height: Math.max(implicitHeight, availableHeight)
            onInsertionFinished: input => Qt.callLater(() => {
                if (reader.editor !== draftEditor || reader.composing)
                    return;
                messageBlocks.forceLayout();
                thread.forceLayout();
                const caret = input.cursorRectangle;
                const top = input.mapToItem(paper.contentItem, 0, caret.y).y;
                const bottom = top + caret.height + reader.t.space.m;
                if (top < paper.contentY || bottom > paper.contentY + paper.height) {
                            const target = top < paper.contentY ? top : bottom - paper.height;
                    paper.contentY = Math.max(0, Math.min(target, paper.contentHeight - paper.height));
                }
            })
            onAttachRequested: reader.attachRequested()
        }
    }
    K.Menu {
        id: more
        items: [
            {label: reader.message?.unread ? qsTr("Mark read") : qsTr("Mark unread"), action: "unread"},
            {label: reader.message?.starred ? qsTr("Remove star") : qsTr("Star"), action: "star"},
            {label: qsTr("Move to Inbox"), action: "move", folder: "Inbox", available: reader.message?.folder !== "Inbox"},
            {label: qsTr("Move to Spam"), action: "move", folder: "Spam"},
            {rule: true, available: !reader.controller.threadQuery?.loading},
            {label: qsTr("Move to Trash"), action: "move", folder: "Trash", risk: true,
                available: reader.entries.length === 1 && !reader.controller.threadQuery?.loading},
            {label: qsTr("Move conversation to Trash"), action: "trashConversation", risk: true,
                available: reader.entries.length > 1 && !!reader.message?.backendConversation && !reader.controller.threadQuery?.loading}
        ].filter(item => item.available !== false)
        onPicked: index => {
            const item = items[index];
            reader.controller.act(item.action, {folder: item.folder});
        }
    }
}
