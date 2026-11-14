import QtQuick
import Tacit.Kit as K

Flow {
    id: reason

    required property var controller
    required property string conversationId
    readonly property var t: K.Kit.tokens
    readonly property var notes: controller.selected?.files?.find(file => file.name === "Header notes.md")
    readonly property string explanation: (conversationId === "mara" || conversationId === "seed-02")
        ? qsTr("To answer both of Mara's questions, from your header notes.")
        : qsTr("To acknowledge this message, for you to review.")
    readonly property real leadingInset: Math.max(0, (openNotes.height - reasonText.implicitHeight) / 2)
    spacing: t.space.m + t.space.s

    K.TacitText {
        id: reasonText
        width: Math.min(implicitWidth, reason.width)
        height: Math.max(implicitHeight, openNotes.height)
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
        size: "row"
        ink: "quiet"
        textFormat: Text.StyledText
        text: '<font color="' + reason.controller.agentInk + '">' + qsTr("Why:") + '</font> '
            + reason.explanation.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    MailAction {
        id: openNotes
        text: qsTr("Open notes")
        visible: !!reason.notes
        onActivated: reason.controller.act("preview", {file: reason.notes})
    }
}
