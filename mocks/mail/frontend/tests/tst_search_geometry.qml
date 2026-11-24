import QtQuick
import QtTest
import Tacit.Kit as K
import ".." as Mail
import "fixtures/mailbox.js" as Fixture

Item {
    id: fixture
    width: 1280; height: 972
    Mail.MailWorkspaceSession { id: session; reduceAction: Fixture.reduce; queryRows: Fixture.results }
    Mail.MailWorkspace { id: workspace; anchors.fill: parent; controller: session }
    TestCase {
        name: "SearchGeometry"
        when: windowShown
        function test_openAndCloseKeepToolbarAndHeaderAtSameHeight() {
            K.Kit.reducedMotion = true;
            session.data = Fixture.initial("read");
            wait(40);
            const search = findChild(workspace, "mailSearch");
            const caption = findChild(workspace, "mailboxCaption");
            const rule = findChild(workspace, "mailListHairline");
            verify(!!search); verify(!!caption); verify(!!rule);
            const top = search.mapToItem(workspace, 0, 0).y;
            const barHeight = search.parent.height;
            const captionY = caption.mapToItem(workspace, 0, 0).y;
            const ruleY = rule.mapToItem(workspace, 0, 0).y;
            search.forceActiveFocus();
            keyClick("e"); keyClick("n"); keyClick("e"); keyClick("r");
            wait(0);
            verify(session.ui.searching);
            compare(search.mapToItem(workspace, 0, 0).y, top);
            compare(search.parent.height, barHeight);
            compare(caption.mapToItem(workspace, 0, 0).y, captionY);
            compare(rule.mapToItem(workspace, 0, 0).y, ruleY);
            const close = findChild(workspace, "closeSearch");
            mouseClick(close, close.width / 2, close.height / 2);
            wait(0);
            verify(!session.ui.searching);
            compare(search.mapToItem(workspace, 0, 0).y, top);
            compare(search.parent.height, barHeight);
            compare(rule.mapToItem(workspace, 0, 0).y, ruleY);
        }
    }
}
