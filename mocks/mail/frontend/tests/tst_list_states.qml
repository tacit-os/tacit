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
    QtObject {
        id: client
        property bool enabled: false
        property var searches: []
        property var folders: []
        signal searched(int revision, var messages, bool ok)
        signal searchFirstPage(int revision, var messages)
        signal mailboxLoaded(int revision, var messages, bool ok)
        signal mailboxFirstPage(int revision, var messages)
        signal failed()
        function search(term, revision, filter) { searches = searches.concat([{term, revision, filter}]); }
        function loadMailboxView(account, folder, filter, sort, revision, selectedId, category) {
            folders = folders.concat([{account, folder, filter, sort, revision, category}]);
        }
    }
    TestCase {
        name: "MailListStates"
        when: windowShown
        function init() {
            K.Kit.reducedMotion = true;
            fixture.width = 1280;
            client.enabled = false; client.searches = []; client.folders = [];
            session.olderImports = ({});
            let data = Fixture.initial("read");
            const rows = Fixture.results(data).map(row => Object.assign({}, row, {gmail: true, gmailLabels: ["INBOX", "CATEGORY_PERSONAL"]}));
            data.accounts = data.accounts.map(account => Object.assign({}, account, {id: account.name, categoryProvider: "gmail"}));
            data.ui.rail = true;
            session.data = Store.replaceBackendView(data, rows, Store.backendViewKey("Inbox", "All accounts", "All mail", "Newest first", "CATEGORY_PERSONAL"));
            session.searchQuery.client = client;
            session.searchQuery.loading = false; session.searchQuery.error = ""; session.searchQuery.refreshPending = false;
            session.folderQuery.client = client;
            session.folderQuery.loading = false; session.folderQuery.error = ""; session.folderQuery.refreshPending = false;
            workspace.compactReading = true;
            wait(40);
        }
        function item(name) { const result = findChild(workspace, name); verify(!!result); return result; }
        function startSearch() {
            session.act("search", {text: "palettes"});
            tryCompare(client, "searches", client.searches);
            tryVerify(() => client.searches.length === 1);
        }
        function emptyInbox() {
            const data = Store.emptyMailbox(); data.accounts = session.accounts; data.ui.rail = true;
            session.data = data;
            wait(0);
        }
        function clickRetry() {
            const button = item("mailListState").children.find(child => child.text === "Try again");
            verify(!!button); wait(30); mouseClick(button, button.width / 2, button.height / 2); wait(0);
        }
        function test_searchFailureIsNotNoResultsAndRetryKeepsContext() {
            const selected = session.ui.selected, summary = item("conversationSummary").text;
            startSearch();
            session.act("searchFilter", {value: "Unread"});
            tryVerify(() => client.searches.length === 2);
            client.searched(session.searchQuery.revision, [], false);
            const status = item("mailListState");
            tryCompare(status, "visible", true);
            verify(status.failure);
            compare(status.text, "Could not search your mail.");
            compare(status.action, "Try again");
            verify(!item("mailboxCaption").text.includes("0 results"));
            const ticket = session.searchQuery.revision;
            clickRetry();
            compare(session.searchQuery.revision, ticket + 1);
            compare(client.searches[2].term, "palettes"); compare(client.searches[2].filter, "Unread");
            compare(session.ui.selected, selected); compare(item("conversationSummary").text, summary);
            client.searched(session.searchQuery.revision, [], true);
            compare(status.failure, false); compare(status.text, "No messages match your search.");
            compare(status.action, "Clear search");
            verify(item("mailboxCaption").text.startsWith("0 results"));
        }
        function test_loadingDoesNotClaimFinalZeroAndKeepsReader() {
            const selected = session.ui.selected;
            startSearch();
            verify(session.searchQuery.loading);
            verify(!item("mailListState").visible);
            verify(item("mailboxCaption").text.startsWith("Searching…"));
            verify(!item("mailboxCaption").text.includes("0 results"));
            compare(session.ui.selected, selected);
        }
        function test_olderMailLoadingDoesNotClaimFinalZero() {
            startSearch();
            client.searched(session.searchQuery.revision, [], true);
            session.olderImports = ({Personal: {saved: 0, total: -1, interrupted: false}});
            verify(item("mailboxCaption").text.startsWith("Searching…"));
            verify(!item("mailListState").visible);
            session.olderImports = ({});
            verify(item("mailboxCaption").text.startsWith("0 results"));
            compare(item("mailListState").text, "No messages match your search.");
        }
        function test_emptyCategoryNamesCategoryNotWholeInbox() {
            const total = session.count("Inbox", "All accounts", false), selected = session.ui.selected;
            client.enabled = true;
            session.act("gmailCategory", {value: "CATEGORY_PROMOTIONS"});
            tryVerify(() => client.folders.length === 1);
            client.mailboxLoaded(session.folderQuery.revision, [], true);
            const status = item("mailListState");
            tryCompare(status, "visible", true);
            compare(status.text, "No messages in Promotions.");
            compare(status.action, ""); verify(!status.failure);
            compare(session.count("Inbox", "All accounts", false), total);
            compare(session.ui.selected, selected);
        }
        function test_confirmedEmptyInboxHasNoBackToInboxAction() {
            emptyInbox(); client.enabled = true; session.folderQuery.refresh();
            client.mailboxLoaded(session.folderQuery.revision, [], true);
            const status = item("mailListState");
            tryCompare(status, "visible", true);
            compare(status.text, "Your Inbox is empty."); compare(status.action, "");
            verify(item("mailboxCaption").text.includes("0 total"));
        }
        function test_mailboxFailureAndRetryAreInsideCompactList() {
            fixture.width = 400; workspace.compactReading = false;
            emptyInbox(); client.enabled = true; session.folderQuery.refresh();
            verify(session.folderQuery.loading);
            verify(item("mailboxCaption").text.startsWith("Opening Inbox…"));
            verify(!item("mailboxCaption").text.includes("0 total"));
            client.mailboxLoaded(session.folderQuery.revision, [], false);
            const status = item("mailListState"), pane = item("inboxPane");
            tryCompare(status, "visible", true); verify(status.failure); compare(status.action, "Try again");
            verify(!item("mailboxCaption").text.includes("0 total"));
            const at = status.mapToItem(pane, 0, 0);
            verify(at.x >= 0 && at.y >= 0 && at.y + status.height <= pane.height);
            const ticket = session.folderQuery.revision;
            clickRetry(); compare(session.folderQuery.revision, ticket + 1);
            client.mailboxLoaded(session.folderQuery.revision, [], true);
            compare(status.failure, false); compare(status.text, "Your Inbox is empty.");
        }
        function test_inactiveSearchKeepsItsFullPlaceholder() {
            workspace.compactReading = false;
            for (const width of [1280, 400]) {
                fixture.width = width; wait(30);
                const search = item("mailSearch");
                const placeholder = search.children.find(child => child.text === "Search " + search.scope);
                verify(!!placeholder); verify(!item("closeSearch").visible);
                verify(!placeholder.truncated);
            }
        }
        function test_emptyActiveSearchReservesCloseSpace_data() { return [{tag: "normal", width: 1280}, {tag: "minimum", width: 400}]; }
        function test_emptyActiveSearchReservesCloseSpace(row) {
            fixture.width = row.width; workspace.compactReading = false;
            session.act("search", {text: ""}); session.act("searchFilter", {value: "With attachments"});
            item("searchFilter").forceActiveFocus();
            wait(40);
            const search = item("mailSearch"), close = item("closeSearch");
            const placeholder = search.children.find(child => child.text === "Search " + search.scope);
            verify(!!placeholder); verify(close.visible); compare(search.openness, 1);
            const closeX = close.mapToItem(search, 0, 0).x;
            verify(placeholder.x + placeholder.width <= closeX);
            verify(search.x + search.width <= item("searchFilter").x);
        }
    }
}
