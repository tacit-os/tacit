import QtQuick
import QtQuick.Layouts
import Tacit.Kit as K

K.ListRow {
    id: preview
    required property var modelData
    required property var controller
    readonly property var t: K.Kit.tokens
    signal messageRequested(string messageId)
    signal contextRequestedForMessage(string messageId, point position)
    signal rowClicked(int modifiers)
    readonly property bool chosen: modelData.id === preview.controller.ui.selected || modelData.id === preview.controller.ui.draftId && preview.controller.ui.view !== "read"
    readonly property bool hasAgent: !!preview.controller.agentDraft(modelData.id)
    readonly property bool showPreview: !hasAgent || preview.controller.ui.searching
    implicitHeight: previewContent.implicitHeight + preview.t.space.m * 2
    height: implicitHeight
    name: ""
    glyph: ""
    facts: []
    focusable: false
    Accessible.selected: chosen
    Accessible.name: qsTr("%1, %2, %3").arg(modelData.from).arg(modelData.subject).arg(modelData.unread ? qsTr("unread") : qsTr("read"))
    onClicked: modifiers => {
        const messageId = preview.modelData.id;
        preview.rowClicked(modifiers);
        preview.messageRequested(messageId);
    }
    onActivated: preview.messageRequested(preview.modelData.id)
    onContextRequested: position => preview.contextRequestedForMessage(preview.modelData.id, position)
    Rectangle {
        visible: preview.chosen
        x: preview.t.space.xs / 2
        y: preview.t.space.m + preview.t.space.xs / 2
        width: preview.t.state.focusRing
        height: preview.height - 2 * y
        color: preview.t.inkMain
        Accessible.ignored: true
    }

    ColumnLayout {
        id: previewContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: preview.t.space.l + preview.t.space.xs
        anchors.rightMargin: preview.t.space.l + preview.t.space.xs
        anchors.topMargin: preview.t.space.m
        spacing: preview.t.space.xs
        RowLayout {
            Layout.fillWidth: true
            spacing: preview.t.space.s
            K.TacitText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: preview.controller.highlight(preview.modelData.from)
                textFormat: Text.StyledText
                weight: preview.modelData.unread ? "strong" : "medium"
                ink: preview.chosen ? "sec" : (preview.modelData.unread ? "main" : "faint")
                elide: Text.ElideRight
            }
            K.TacitText {
                text: (preview.modelData.starred ? "Starred  ·  " : "") + preview.modelData.account + "  ·  " + preview.modelData.time
                size: "meta"
                ink: preview.chosen ? "sec" : (preview.modelData.unread ? "meta" : "quiet")
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: preview.t.space.s
            K.TacitText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: preview.controller.highlight(preview.modelData.subject)
                textFormat: Text.StyledText
                ink: preview.chosen ? "sec" : (preview.modelData.unread ? "main" : "faint")
                elide: Text.ElideRight
            }
            K.TacitText {
                readonly property int messageCount: preview.modelData.folderMessageCount
                    ?? ((preview.modelData.history?.length ?? 0) + (preview.modelData.replies?.length ?? 0) + 1)
                visible: messageCount > 1
                text: qsTr("%1 messages").arg(messageCount)
                size: "meta"
                ink: preview.chosen ? "sec" : (preview.modelData.unread ? "meta" : "quiet")
            }
            K.TacitText {
                visible: preview.modelData.files.length > 0
                text: preview.modelData.files.length === 1 ? qsTr("1 attachment") : qsTr("%1 attachments").arg(preview.modelData.files.length)
                size: "meta"
                ink: preview.chosen ? "sec" : (preview.modelData.unread ? "meta" : "quiet")
            }
        }
        K.TacitText {
            visible: preview.showPreview
            Layout.fillWidth: true
            text: preview.controller.highlight(preview.controller.resultSnippet(preview.modelData))
            textFormat: Text.StyledText
            size: "meta"
            ink: preview.chosen ? "sec" : (preview.modelData.unread ? "meta" : "faint")
            elide: Text.ElideRight
        }
        RowLayout {
            visible: preview.hasAgent
            Layout.fillWidth: true
            spacing: preview.t.space.s
            Item {
                implicitWidth: preview.t.space.s
                implicitHeight: preview.t.icon.rail
                Rectangle {
                    width: 1
                    height: parent.height
                    color: preview.controller.agentInk
                }
                Rectangle {
                    y: parent.height / 2
                    width: parent.width
                    height: 1
                    color: preview.controller.agentInk
                }
            }
            K.TacitText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: qsTr("Reply drafted: answers both of Mara's questions")
                size: "meta"
                color: preview.controller.agentInk
                elide: Text.ElideRight
            }
        }
    }
}
