import QtQuick
import QtQuick.Layouts
import Tacit.Kit as K

Item {
    id:editor
    required property var controller
    readonly property var draft:controller.draft
    readonly property var t:K.Kit.tokens
    property alias animationsPaused: body.animationsPaused
    property bool newMessage:false
    property string replySourceName
    readonly property real fromCenter: content.y + fields.y + fromRow.y + fromRow.height / 2
    readonly property real writingBottom: content.y + body.y + body.height
    property Component footerComponent
    property real availableHeight:0
    property alias maximumImageHeight: body.maximumImageHeight
    property real maximumWritingHeight: 480
    readonly property real labelWidth: t.space.page + t.space.s
    readonly property real labelGap: t.space.s
    signal insertionFinished(Item input)
    signal attachRequested()
    readonly property real panelPadding: newMessage ? 0 : t.space.l
    implicitHeight: content.implicitHeight + 2 * panelPadding + t.space.l

    Rectangle {
        visible: !editor.newMessage
        width: editor.width
        height: editor.height - editor.t.space.l
        color: Qt.alpha(editor.t.inkMain, editor.t.wash.action)
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: editor.t.radius.panel
        bottomRightRadius: editor.t.radius.panel
        Accessible.ignored: true
    }
    Rectangle {
        visible: !editor.newMessage
        width: editor.width
        height: 1
        color: editor.t.hairline
        Accessible.ignored: true
    }

    function sendDraft() {
        controller.act("send", body.snapshot());
    }

    function focusBody(){if(newMessage&&!draft.to.includes("@"))recipients.focusIn();else body.focusIn();}
    component Label: K.TacitText {
        Layout.preferredWidth: editor.labelWidth
        size: "meta"
        ink: "faint"
    }
    component FieldRule: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Qt.alpha(editor.t.inkMain, editor.t.wash.current)
        Accessible.ignored: true
    }

    ColumnLayout {
        id: content
        x: editor.panelPadding
        y: editor.panelPadding
        width: Math.max(0, editor.width - 2 * editor.panelPadding)
        height: Math.max(implicitHeight, editor.availableHeight - 2 * editor.panelPadding - editor.t.space.l)
        spacing: editor.t.space.s

        ColumnLayout {
            id:fields
            Layout.fillWidth:true;spacing:0
            RowLayout {
                Layout.fillWidth:true;spacing:editor.labelGap
                id: fromRow
                Label {text:qsTr("From")}
                K.MenuButton {
                    objectName: "draftFrom"
                    Layout.leftMargin: -editor.t.space.m
                    text: {
                        const account = editor.controller.accounts.find(entry => entry.name === editor.draft?.account);
                        if (!account)
                            return "";
                        return editor.width < editor.t.width.panel + editor.t.space.page
                            ? account.name : qsTr("%1, %2").arg(account.name).arg(account.email);
                    }
                    items: editor.controller.accounts.map(account => ({
                        label: qsTr("%1, %2").arg(account.name).arg(account.email),
                        checked: account.name === editor.draft?.account
                    }))
                    onPicked: index => editor.controller.act("draft", {account: editor.controller.accounts[index].name})
                }
                Item { Layout.fillWidth: true }
                K.MenuButton {
                    visible: !editor.newMessage
                    text: items.find(item => item.mode === editor.draft?.mode)?.label ?? qsTr("Reply")
                    items: [{label: qsTr("Reply"), mode: "Reply"}]
                        .concat(editor.controller.canReplyAll ? [{label: qsTr("Reply all"), mode: "Reply all"}] : [])
                        .concat([{label: qsTr("Forward"), mode: "Forward"}])
                    onPicked: index => editor.controller.act("mode", {value: items[index].mode})
                }
            }
            FieldRule {}
            RowLayout {
                Layout.fillWidth:true;spacing:editor.labelGap
                Label {text:qsTr("To")}
                MailEditorField {
                    id:recipients;objectName:"draftTo"
                    Layout.fillWidth:true;Layout.minimumWidth:0
                    label:qsTr("To recipients");hint:qsTr("Name or email address");text:editor.draft?.to ?? ""
                    error:!input.activeFocus&&text!==""&&!editor.controller.addressesValid(text)
                    onEdited:editor.controller.act("draft",{to:text})
                }
                RowLayout {
                    Layout.leftMargin: editor.t.space.s
                    Layout.rightMargin: editor.t.space.m
                    spacing: editor.t.space.xxl

                    MailAction {
                        text: editor.draft?.showCc ? qsTr("Hide Cc") : qsTr("Cc")
                        onActivated: editor.controller.act("draft", {showCc: !editor.draft.showCc})
                    }
                    MailAction {
                        text: editor.draft?.showBcc ? qsTr("Hide Bcc") : qsTr("Bcc")
                        onActivated: editor.controller.act("draft", {showBcc: !editor.draft.showBcc})
                    }
                }
            }
            FieldRule {}
            K.MenuSurface {
                id: recipientSuggestions
                visible: recipients.input.activeFocus
                         && recipients.text.toLowerCase().includes("anna")
                         && !recipients.text.includes("@")
                Layout.leftMargin: editor.labelWidth + editor.labelGap
                cursor: 0
                onVisibleChanged: if (visible) cursor = 0
                items: [
                    {label: qsTr("Anna Richter · Personal"), detail: "anna.richter@example.net"},
                    {label: qsTr("Anna Richter · Work"), detail: "a.richter@moss.example"}
                ]
                onPicked: index => {
                    editor.controller.act("draft", {to: items[index].detail});
                    body.focusIn();
                }

                Shortcut {
                    sequence: "Down"
                    enabled: recipientSuggestions.visible
                    onActivated: recipientSuggestions.cursor = (recipientSuggestions.cursor + 1) % recipientSuggestions.items.length
                }
                Shortcut {
                    sequence: "Up"
                    enabled: recipientSuggestions.visible
                    onActivated: recipientSuggestions.cursor = (recipientSuggestions.cursor + recipientSuggestions.items.length - 1) % recipientSuggestions.items.length
                }
                Shortcut {
                    sequences: ["Return", "Enter"]
                    enabled: recipientSuggestions.visible
                    onActivated: recipientSuggestions.pick(recipientSuggestions.cursor)
                }
            }
            FieldRule { visible: recipientSuggestions.visible }
            RowLayout {
                visible: editor.draft?.showCc ?? false
                Layout.fillWidth: true
                spacing: editor.labelGap

                Label { text: qsTr("Cc") }
                MailEditorField {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    label: qsTr("Cc recipients")
                    text: editor.draft?.cc ?? ""
                    error: !input.activeFocus && text !== "" && !editor.controller.addressesValid(text)
                    onEdited: editor.controller.act("draft", {cc: text})
                }
            }
            FieldRule { visible: editor.draft?.showCc ?? false }
            RowLayout {
                visible: editor.draft?.showBcc ?? false
                Layout.fillWidth: true
                spacing: editor.labelGap

                Label { text: qsTr("Bcc") }
                MailEditorField {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    label: qsTr("Bcc recipients")
                    text: editor.draft?.bcc ?? ""
                    error: !input.activeFocus && text !== "" && !editor.controller.addressesValid(text)
                    onEdited: editor.controller.act("draft", {bcc: text})
                }
            }
            FieldRule { visible: editor.draft?.showBcc ?? false }
            RowLayout {
                Layout.fillWidth:true;spacing:editor.labelGap
                Label {text:qsTr("Subject")}
                MailEditorField {objectName:"draftSubject";Layout.fillWidth:true;Layout.minimumWidth:0;label:qsTr("Message subject");hint:qsTr("Add a subject");text:editor.draft?.subject ?? "";onEdited:editor.controller.act("draft",{subject:text})}
            }
            FieldRule {}
        }
        MailEditorBody {
            id:body;objectName:"draftBody"
            Layout.fillWidth: true
            Layout.fillHeight: editor.newMessage
            Layout.minimumHeight: implicitHeight
            growWithContent: !editor.newMessage
            maximumWritingHeight: editor.maximumWritingHeight
            onDropFinished: editor.insertionFinished(body.input)
            onFileDropped: (file, position) => {
                const path = String(file);
                editor.controller.act("attach", {
                    url: path,
                    inline: true,
                    name: decodeURIComponent(path.split("/").pop())
                });
                body.insertAttachment(file, editor.draft.files[editor.draft.files.length - 1], position);
            }
            draftId: editor.draft?.id ?? ""
            draftText: editor.draft?.body ?? ""
            draftHtml: editor.draft?.bodyHtml ?? ""
            onEdited: {
                const id = draftId;
                const c = editor.controller;
                const value = body.snapshot();
                Qt.callLater(function() {
                    if (id && c.draft?.id === id)
                        c.act("draft", value);
                });
            }
            onSubmitted: editor.sendDraft()
            onDismissed:editor.controller.act("keepDraft")
        }
        Flow {
            Layout.fillWidth: true
            spacing: editor.t.space.s
            Repeater {
                model: Array.from(editor.draft?.files ?? []).filter(file => !file.inline)
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    width: Math.min(parent.width, chipRow.implicitWidth + editor.t.space.m)
                    height: chipRow.implicitHeight
                    radius: height / 2
                    color: Qt.alpha(editor.t.inkMain, editor.t.wash.current)

                    RowLayout {
                        id: chipRow
                        anchors.fill: parent
                        anchors.leftMargin: editor.t.space.m
                        spacing: editor.t.space.xs

                        MailAction {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: chip.modelData.name
                            enabled: !!chip.modelData.url
                            clip: true
                            onActivated: Qt.openUrlExternally(chip.modelData.url)
                        }
                        K.IconButton {
                            symbol: "close"
                            label: qsTr("Remove %1").arg(chip.modelData.name)
                            onActivated: {
                                const id = chip.modelData.id;
                                editor.controller.act("detach", {id: id});
                            }
                        }
                    }
                }
            }
        }
        Loader {
            Layout.fillWidth: true
            visible: status === Loader.Ready
            sourceComponent: editor.footerComponent
        }
    }
}
