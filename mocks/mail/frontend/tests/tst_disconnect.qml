import QtQuick
import QtTest
import ".." as Mail

Item {
    width: 600
    height: 480

    QtObject {
        id: mockClient
        property var choices: []
        signal disconnectSummaryLoaded(string id, var info, bool ok)
        signal internetAccountDisconnected(string id, bool removed, bool ok)
        function loadDisconnectSummary(id) {
            Qt.callLater(() => disconnectSummaryLoaded(id, {drafts: 1, waiting: 2, uncertain: 0}, true));
        }
        function disconnectInternetAccount(id, remove) {
            choices.push([id, remove]);
            Qt.callLater(() => internetAccountDisconnected(id, remove, false));
        }
    }

    Component {
        id: promptComponent
        Mail.MailDisconnectPrompt {
            width: 480
            client: mockClient
            account: ({id: "test-account", email: "user@example.test", provider: "managed-imap"})
        }
    }

    TestCase {
        name: "DisconnectPrompt"
        when: windowShown

        function test_submitsExplicitChoice_data() {
            return [
                {tag: "keep", button: "keepLocalMail", remove: false},
                {tag: "remove", button: "removeLocalMail", remove: true}
            ];
        }
        function test_submitsExplicitChoice(row) {
            mockClient.choices = [];
            const prompt = createTemporaryObject(promptComponent, parent);
            verify(prompt);
            const button = findChild(prompt, row.button);
            tryCompare(button, "enabled", true);
            compare(prompt.summary.waiting, 2);
            compare(mockClient.choices.length, 0);
            mouseClick(button);
            compare(mockClient.choices.length, 1);
            compare(mockClient.choices[0][0], "test-account");
            compare(mockClient.choices[0][1], row.remove);
            tryCompare(prompt, "busy", false);
            verify(prompt.failure.length > 0);
        }
    }
}
