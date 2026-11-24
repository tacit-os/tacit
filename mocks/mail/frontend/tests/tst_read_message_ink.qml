import QtQuick
import QtTest
import Tacit.Kit as K
import ".." as Mail

Item {
    width: 800; height: 200
    QtObject {
        id: controller
        property var ui: ({selected: "", draftId: "", view: "read"})
        property int signedInAccountCount: 1
        property color agentInk: K.Kit.tokens.inkMeta
        function agentDraft(id) { return null; }
        function highlight(text) { return text; }
    }
    Mail.MailMessagePreview {
        id: preview
        width: parent.width
        controller: controller
        modelData: ({id: "read", from: "Sender", subject: "Subject", unread: false,
            time: "12:00", files: [], folderMessageCount: 2})
    }
    TestCase {
        name: "ReadMessageInk"
        when: windowShown
        function test_readAndUnreadColors() {
            const subject = findChild(preview, "messageListSubject");
            const metadata = findChild(preview, "messageListMetadata");
            compare(subject.ink, "faint");
            compare(metadata.ink, "quiet");
            preview.modelData = Object.assign({}, preview.modelData, {unread: true});
            compare(subject.ink, "main");
            compare(metadata.ink, "quiet");
        }
    }
}
