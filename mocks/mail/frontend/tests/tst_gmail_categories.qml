import QtQuick
import QtTest
import Tacit.Kit as K
import ".." as Mail
import "../mail-store.js" as Store

Item {
    id: fixture
    width: 1720; height: 972
    Mail.MailWorkspaceSession { id: session }
    Mail.MailWorkspace { id: workspace; anchors.fill: parent; controller: session }
    QtObject {
        id: client
        property bool enabled: false
        property var calls: []
        signal mailboxFirstPage(int revision, var messages)
        signal mailboxLoaded(int revision, var messages, bool ok)
        signal failed()
        function loadMailboxView(account, folder, filter, sort, revision, selected, category) {
            calls = calls.concat([{revision, category}]);
        }
    }
    Component { id: queryFactory; Mail.MailboxQuery {} }
    TestCase {
        name: "GmailCategories"
        when: windowShown
        function init() {
            fixture.width = 1720;
            K.Kit.reducedMotion = true;
            const data = Store.emptyMailbox();
            data.accounts = [{id: "gmail", name: "Gmail", email: "user@gmail.test", categoryProvider: "gmail"}, {id: "plain", name: "Plain", email: "user@plain.test"}];
            session.data = data;
            client.enabled = false; client.calls = [];
            wait(0);
        }
        function control(name) { const item = findChild(workspace, name); verify(!!item); return item; }
        function test_visibilityAndPlacement() {
            const bar = control("gmailCategoryBar");
            verify(bar.visible);
            compare(control("gmailCategoryTabs").current, 0);
            const rule = control("mailListHairline");
            compare(bar.mapToItem(workspace, 0, 0).y, rule.mapToItem(workspace, 0, rule.height).y);
            const caption = control("mailboxCaption");
            verify(!caption.truncated);
            verify(!control("searchFilter").visible);
            verify(!findChild(workspace, "mailSortLabel"));
            session.act("folder", {folder: "Inbox", account: "plain"});
            verify(!bar.visible);
            session.act("folder", {folder: "Inbox", account: "gmail"});
            verify(bar.visible);
            session.act("folder", {folder: "Archive", account: "gmail"});
            verify(!bar.visible);
            session.act("folder", {folder: "Inbox", account: "gmail"});
            session.act("search", {text: "term"});
            verify(!bar.visible);
        }
        function test_keyboardChoosesFourCategories() {
            const tabs = control("gmailCategoryTabs");
            compare(tabs.labels.join(","), "Primary,Promotions,Social,Updates");
            compare(session.activeGmailCategory, "CATEGORY_PERSONAL");
            verify(!findChild(workspace, "gmailCategoryMore"));
            tabs.forceActiveFocus(); keyClick(Qt.Key_Right);
            compare(session.ui.gmailCategory, "CATEGORY_PROMOTIONS");
            compare(tabs.current, 1);
            keyClick(Qt.Key_Right);
            compare(session.ui.gmailCategory, "CATEGORY_SOCIAL");
            keyClick(Qt.Key_Right);
            compare(session.ui.gmailCategory, "CATEGORY_UPDATES");
            compare(tabs.current, 3);
            session.act("folder", {folder: "Sent"});
            compare(session.ui.gmailCategory, "");
        }
        function test_narrowKeyboardKeepsSelectedTabVisible() {
            fixture.width = 400;
            wait(0);
            const tabs = control("gmailCategoryTabs"), viewport = control("gmailCategoryViewport");
            tabs.forceActiveFocus(); keyClick(Qt.Key_End);
            compare(session.ui.gmailCategory, "CATEGORY_UPDATES");
            const tab = tabs.children.find(child => child.index === 3);
            verify(!!tab);
            tryVerify(() => tab.mapToItem(viewport, 0, 0).x >= -1
                && tab.mapToItem(viewport, tab.width, 0).x <= viewport.width + 1);
        }
        function test_categoryChangeKeepsSelectionAndSearchCanRevealOtherCategory() {
            const data = session.data;
            const row = Store.mailboxRows([], [{id: "promotion", account_id: "gmail", remote_id: "gmail:promotion", conversation_id: "thread", mailbox: "Inbox", from: {email: "sender@example.test"}, subject: "Promotion", date: "2026-01-01T00:00:00Z", gmail_labels: ["INBOX", "CATEGORY_PROMOTIONS"]}])[0];
            data.ui.selected = row.id;
            session.data = Store.replaceBackendView(data, [row], Store.backendViewKey("Inbox", "All accounts", "All mail", "Newest first"));
            const selected = Store.current(session.data);
            session.act("gmailCategory", {value: "CATEGORY_PROMOTIONS"});
            compare(Store.current(session.data), selected);
            compare(session.ui.selected, row.id);
            session.act("gmailCategory", {value: "CATEGORY_PERSONAL"});
            session.act("search", {text: "Promotion"});
            session.act("closeSearch");
            compare(session.ui.gmailCategory, "CATEGORY_PROMOTIONS");
            compare(session.ui.selected, row.id);
        }
        function test_eachTabRequestsItsOwnBackendCategory() {
            const query = createTemporaryObject(queryFactory, fixture, {client, folder: "Inbox",
                gmailCategory: Qt.binding(() => session.activeGmailCategory)});
            verify(!!query);
            client.enabled = true; query.refresh();
            const tabs = control("gmailCategoryTabs");
            for (let index = 0; index < 4; ++index) {
                if (index > 0) {
                    const tab = tabs.children.find(child => child.index === index);
                    verify(!!tab);
                    mouseClick(tab, tab.width / 2, tab.height / 2);
                }
                compare(client.calls.length, index + 1);
                compare(client.calls[index].category, ["CATEGORY_PERSONAL", "CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL", "CATEGORY_UPDATES"][index]);
                client.mailboxLoaded(query.revision, [], true);
            }
        }
        function test_categoryRepliesUseDistinctKeysAndRejectStalePages() {
            const query = createTemporaryObject(queryFactory, fixture, {client, folder: "Inbox"});
            verify(!!query);
            client.enabled = true; query.refresh();
            const oldRevision = query.revision, oldKey = query.key;
            query.gmailCategory = "CATEGORY_PROMOTIONS";
            verify(query.key !== oldKey);
            compare(client.calls.length, 2);
            compare(client.calls[1].category, "CATEGORY_PROMOTIONS");
            client.mailboxLoaded(oldRevision, [{id: "stale"}], true);
            compare(query.messages.length, 0);
            client.mailboxLoaded(query.revision, [{id: "fresh"}], true);
            compare(query.messages[0].id, "fresh");
        }
    }
}
