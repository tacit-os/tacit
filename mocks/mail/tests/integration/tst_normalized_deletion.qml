import QtQuick
import QtTest

Item {
    id: fixture
    property string localId: ""
    property string remoteId: ""
    property var updates: []
    property var deletions: []
    Connections {
        target: testMailbox
        function onDraftSaved(local, remote) { if (local === fixture.localId) fixture.remoteId = remote; }
        function onMessageUpdated(id, ok) {
            if (id === fixture.remoteId) fixture.updates = fixture.updates.concat([{ok}]);
        }
        function onMessagesDeleted(ids) {
            if (ids.includes(fixture.remoteId)) fixture.deletions = fixture.deletions.concat([ids]);
        }
    }
    TestCase {
        name: "NativeDeletionConfirmation"
        when: windowShown
        function test_onlySuccessfulDeletionEmitsDeletedIds() {
            fixture.localId = "normalization-deletion-" + Date.now();
            testMailbox.saveDraft(fixture.localId, "", {account_id: "work", subject: "Temporary deletion fixture",
                body_text: "Temporary fixture", to: [{email: "recipient@example.test"}]});
            tryVerify(() => fixture.remoteId.length > 0, 10000);
            testMailbox.deleteTrashedMessage(fixture.remoteId); // A draft is not eligible for permanent deletion.
            tryVerify(() => fixture.updates.length === 1, 10000);
            compare(fixture.updates[0].ok, false);
            compare(fixture.deletions.length, 0);
            testMailbox.updateMessage(fixture.remoteId, {mailbox: "Trash"});
            tryVerify(() => fixture.updates.length === 2, 10000);
            compare(fixture.updates[1].ok, true);
            compare(fixture.deletions.length, 0);
            testMailbox.deleteTrashedMessage(fixture.remoteId);
            tryVerify(() => fixture.deletions.length === 1 && fixture.updates.length === 3, 10000);
            compare(fixture.updates[2].ok, true);
            compare(fixture.deletions[0].length, 1);
            compare(fixture.deletions[0][0], fixture.remoteId);
        }
    }
}
