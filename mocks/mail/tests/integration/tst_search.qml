import QtQuick
import QtTest
import "../../frontend" as Mail

Item {
    width: 1720; height: 972
    Mail.MailWorkspaceSession { id: session; mailboxClient: testMailbox }
    Mail.MailWorkspace { id: workspace; anchors.fill: parent; controller: session }
    TestCase {
        name: "NativeSearch"
        when: windowShown
        function test_typedQueryReachesLocalSearch() {
            tryVerify(() => session.rows.length > 0, 10000);
            const field = findChild(workspace, "mailSearch");
            field.forceActiveFocus();
            keyClick(Qt.Key_M); keyClick(Qt.Key_O); keyClick(Qt.Key_S); keyClick(Qt.Key_S);
            tryVerify(() => session.data.search?.query === "moss"
                && session.rows.some(row => row.from.includes("Moss")), 10000);
            compare(session.data.search.query, "moss");
            verify(session.ui.searching);
            session.act("closeSearch");
        }
    }
}
