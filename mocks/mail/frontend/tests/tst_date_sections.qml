import QtQuick
import QtTest
import Tacit.Kit as K
import ".." as Mail
import "fixtures/mailbox.js" as Fixture
import "../mail-store.js" as Store
import "fixtures/mailbox-responses.js" as Queries

Item {
    width: 1720; height: 972
    Mail.MailWorkspaceSession { id: session; reduceAction: Fixture.reduce; queryRows: Fixture.results }
    Mail.MailWorkspace { id: workspace; anchors.fill: parent; controller: session }
    TestCase {
        name: "DateSections"
        when: windowShown
        function test_noDateHeadingsWhileScrolling() {
            K.Kit.reducedMotion = true;
            const data = Fixture.initial("read");
            const rows = [];
            for (let i = 0; i < 90; ++i)
                rows.push(Store.message("date-" + i, "Sender", "Message " + i, "Body",
                    "Work", i < 30 ? "Today" : i < 60 ? "Yesterday" : "Monday", "12:00", false));
            session.data = Queries.orderedView(Queries.replaceMailboxRows(data, rows));
            const list = findChild(workspace, "messageList");
            tryCompare(list, "count", 90);
            const view = list.view;
            compare(list.section.property, "");
            for (const index of [10, 40, 70]) {
                view.positionViewAtIndex(index, ListView.Beginning);
                view.forceLayout();
                tryVerify(() => !!view.itemAtIndex(index));
                verify(!findChild(view, "mailDateLabel"));
                verify(!findChild(view, "mailDateSection"));
                const metadata = findChild(view.itemAtIndex(index), "messageListMetadata");
                verify(!!metadata);
                verify(metadata.text.includes("12:00"));
            }
        }
    }
}
