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
        name: "MailListPolish"
        when: windowShown
        function init() {
            K.Kit.reducedMotion = true;
            let data = Fixture.initial("read");
            const rows = Fixture.results(data).map(row => Object.assign({}, row, {gmail: true, gmailLabels: ["INBOX", "CATEGORY_PERSONAL"]}));
            data.accounts = data.accounts.map(account => Object.assign({}, account, {categoryProvider: "gmail"}));
            data.ui.rail = true;
            session.data = Store.replaceBackendView(data, rows, Store.backendViewKey("Inbox", "All accounts", "All mail", "Newest first", "CATEGORY_PERSONAL"));
            wait(0);
            wait(40);
        }
        function test_countsFitAndHeaderBaselineIsPreserved() {
            const caption = findChild(workspace, "mailboxCaption");
            verify(!!caption);
            verify(caption.text.endsWith("11 total"));
            verify(!caption.truncated);
            verify(!findChild(workspace, "mailSortLabel"));
            verify(!findChild(workspace, "searchFilter").visible);
            compare(session.ui.filter, "All mail");
            compare(session.ui.sort, "Newest first");
        }
        function test_allMenuRestoresFullCategoryAndRowsRemainSelectable() {
            const originalCount = session.rows.length;
            verify(originalCount > 1);
            session.act("search", {text: "palettes"});
            session.act("searchFilter", {value: "Unread"});
            const options = findChild(workspace, "searchFilter");
            verify(!!options);
            mouseClick(options, options.width / 2, options.height / 2);
            wait(20); keyClick(Qt.Key_Down); keyClick(Qt.Key_Return);
            compare(session.ui.searchFilter, "All mail");
            session.act("closeSearch");
            compare(session.rows.length, originalCount);
            compare(session.activeGmailCategory, "CATEGORY_PERSONAL");
            const list = findChild(workspace, "messageList");
            tryCompare(list.displayedRows, "count", originalCount);
            list.view.forceLayout();
            const item = list.view.itemAtIndex(1);
            verify(!!item);
            const subject = findChild(item, "messageListSubject");
            verify(!!subject);
            const expected = session.rows[1].id;
            mouseClick(subject, subject.width / 2, subject.height / 2);
            tryCompare(session.ui, "selected", expected);
            compare(session.rows.length, originalCount);
        }
        function test_tabAndMessageTextShareAnAxisAndSelectionUsesKitWash() {
            const list = findChild(workspace, "messageList"), tabs = findChild(workspace, "gmailCategoryTabs");
            verify(!!list); verify(!!tabs);
            list.view.forceLayout();
            const row = list.view.itemAtIndex(0);
            verify(!!row);
            const subject = findChild(row, "messageListSubject");
            verify(!!subject);
            compare(tabs.mapToItem(workspace, K.Kit.tokens.space.m, 0).x, subject.mapToItem(workspace, 0, 0).x);
            const preview = subject.parent.parent.parent;
            verify(preview.chosen);
            verify(preview.selected);
            compare(subject.ink, "faint");
            compare(findChild(preview, "messageListMetadata").ink, "quiet");
            compare(session.ui.selected, "mara");
        }
    }
}
