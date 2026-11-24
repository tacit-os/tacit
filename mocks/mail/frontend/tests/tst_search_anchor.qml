import QtQuick
import QtTest
import Tacit.Kit as K
import ".." as Mail
import "fixtures/mailbox.js" as Fixture

Item {
    id: fixture
    width: 1720; height: 972
    Mail.MailWorkspaceSession { id: session; reduceAction: Fixture.reduce; queryRows: Fixture.results }
    Mail.MailWorkspace { id: workspace; anchors.fill: parent; controller: session }
    TestCase {
        name: "SearchAnchor"
        when: windowShown
        function test_searchKeepsItsLeftEdge_data() {
            return [{tag: "wide", width: 1720}, {tag: "normal", width: 1280}, {tag: "compact", width: 560}];
        }
        function test_searchKeepsItsLeftEdge(row) {
            K.Kit.reducedMotion = true;
            fixture.width = row.width;
            session.data = Fixture.initial("read");
            workspace.compactReading = false;
            wait(40);
            const search = findChild(workspace, "mailSearch");
            const filter = findChild(workspace, "searchFilter");
            verify(!!search); verify(!!filter);
            const left = search.mapToItem(workspace, 0, 0).x;
            const top = search.mapToItem(workspace, 0, 0).y;
            compare(search.x, 0);
            search.forceActiveFocus();
            keyClick("e"); keyClick("n"); keyClick("e"); keyClick("r");
            wait(0);
            verify(session.ui.searching);
            compare(search.mapToItem(workspace, 0, 0).x, left);
            compare(search.mapToItem(workspace, 0, 0).y, top);
            verify(search.x + search.width <= filter.x);
            session.act("searchFilter", {value: "With attachments"});
            wait(0);
            compare(search.mapToItem(workspace, 0, 0).x, left);
            verify(search.x + search.width <= filter.x);
            const close = findChild(workspace, "closeSearch");
            mouseClick(close, close.width / 2, close.height / 2);
            wait(0);
            verify(!session.ui.searching);
            compare(search.mapToItem(workspace, 0, 0).x, left);
            compare(search.mapToItem(workspace, 0, 0).y, top);
        }
    }
}
