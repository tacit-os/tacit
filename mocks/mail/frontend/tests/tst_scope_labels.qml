import QtQuick
import QtTest
import Tacit.Kit as K
import ".." as Mail
import "fixtures/mailbox.js" as Fixture
import "../mail-store.js" as Store

Item {
    id: fixture
    width: 1280; height: 972
    Mail.MailWorkspaceSession { id: session; agentInk: K.Kit.tokens.accent }
    Mail.MailWorkspace { id: workspace; anchors.fill: parent; controller: session }
    TestCase {
        name: "MailScopeLabels"
        when: windowShown
        function init() {
            K.Kit.reducedMotion = true;
            let data = Fixture.initial("read");
            const rows = Fixture.results(data).map(row => Object.assign({}, row, {gmail: true, gmailLabels: ["INBOX", "CATEGORY_PERSONAL"]}));
            data.accounts = data.accounts.map(account => Object.assign({}, account, {categoryProvider: "gmail"}));
            data.ui.rail = true;
            session.data = Store.replaceBackendView(data, rows, Store.backendViewKey("Inbox", "All accounts", "All mail", "Newest first", "CATEGORY_PERSONAL"));
            wait(40);
        }
        function test_categoryCountsExplicitlyDescribeEntireInbox() {
            const caption = findChild(workspace, "mailboxCaption");
            verify(!!caption);
            const total = session.count("Inbox", "All accounts", false);
            compare(caption.text, qsTr("%L1 unread · %L2 total").arg(session.count("Inbox", "All accounts")).arg(total));
            verify(caption.text.endsWith(total + " total"));
            verify(!caption.truncated);
            session.act("gmailCategory", {value: "CATEGORY_PROMOTIONS"});
            compare(caption.text, qsTr("%L1 unread · %L2 total").arg(session.count("Inbox", "All accounts")).arg(total));
            verify(caption.text.endsWith(total + " total"));
            compare(session.count("Inbox", "All accounts", false), total);
        }
        function test_searchScopeAndThreadCountStayVisibleWithoutChangingSelection() {
            const summary = findChild(workspace, "conversationSummary");
            verify(!!summary);
            const before = summary.text, selected = session.ui.selected;
            verify(before.startsWith("3 messages"));
            session.act("search", {text: "palettes"});
            session.data = Store.replaceSearchRows(session.data, [Store.current(session.data)], "palettes", true);
            const caption = findChild(workspace, "mailboxCaption");
            compare(caption.text, "1 result · All accounts, all folders");
            verify(!caption.truncated);
            compare(summary.text, before);
            verify(summary.visible);
            compare(session.ui.selected, selected);
            session.act("closeSearch");
            compare(summary.text, before);
            compare(session.ui.selected, selected);
        }
    }
}
