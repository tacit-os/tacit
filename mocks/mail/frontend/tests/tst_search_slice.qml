import QtQuick
import QtTest
import ".." as Mail
import "../mail-store.js" as Store
import "fixtures/mailbox-responses.js" as Queries
Item {
    id: fixture
    width: 1720; height: 972
    QtObject {
        id: client
        property bool enabled: false
        property int mailboxRequests: 0
        property int threadRequests: 0
        property int searchRequests: 0
        property string imageConsentMessage: ""
        property int lastPrefetchTicket: 0
        property var hydratedMessages: []
        property string lastSyncAccount: ""
        property string deletedMessage: ""
        signal messageUpdated(string id, bool ok)
        signal messagesDeleted(var ids)
        signal accountsLoaded(var accounts, bool ok)
        signal internetAccountRemovalProgress(string account, int removed, int total)
        signal internetAccountDisconnected(string account, bool removed, bool ok)
        signal internetAccountConnected(bool ok, string error, string account)
        signal inboxImportProgress(string account, int downloaded, int total)
        signal inboxSyncFinished(string account, bool ok)
        signal accountSyncStatus(string account, var result, bool ok)
        signal messageImagesAllowed(string messageId, bool ok)
        signal imagePolicyLoaded(string messageId, int revision, var result, bool ok)
        signal imagePoliciesChanged()
        signal threadPrefetched(int ticket, var messages, bool ok)
        signal threadPrefetchImagesLoaded(int ticket, var messages)
        signal threadMessageLoaded(int revision, var message)
        signal threadLoaded(int revision, var messages, bool ok)
        signal mailboxInvalidated()
        signal mailboxFirstPage(int revision, var messages)
        signal mailboxLoaded(int revision, var messages, bool ok)
        signal draftsLoaded(int revision, var messages, bool ok)
        signal searched(int revision, var messages, bool ok)
        signal draftSaved(string localId, string remoteId)
        signal outboxChanged(var job)
        signal sendRejected(string draftId)
        signal failed()
        function loadAccounts() {}
        function deleteTrashedMessage(id) { deletedMessage = id; }
        function allowMessageImages(id) { imageConsentMessage = id; }
        function imagePolicy(id, policy, revision) {}
        function replyMailbox(revision, messages, ok) {
            mailboxLoaded(revision, revision < 0 ? messages : messages, ok);
        }
        function replyFirstPage(revision, messages) { mailboxFirstPage(revision, messages); }
        function replySearch(revision, messages, ok) { searched(revision, messages, ok); }
        function loadMailboxCounts(revision) {}
        function loadMailboxView(account, folder, filter, sort, revision) {
            if (folder)
                ++mailboxRequests;
        }
        function loadDrafts(account, revision) {}
        function loadThread(account, conversation, revision) { ++threadRequests; }
        function prefetchThread(account, conversation, ticket) { lastPrefetchTicket = ticket; }
        function loadThreadImages(messages, revision) { hydratedMessages = messages; }
        function search(query, revision) { ++searchRequests; }
        function syncInbox(account) {
            lastSyncAccount = account;
            return true;
        }
    }

    Mail.MailWorkspaceSession { id: session; mailboxClient: client }
    Mail.MailWorkspace { id: workspace; anchors.fill: parent; controller: session }
    TestCase {
        name: "SearchSlice"
        when: windowShown
        function init() {
            client.enabled = false;
            client.mailboxRequests = 0; client.searchRequests = 0;
            session.threadQuery.pending.clear(); session.threadQuery.resetPrefetch();
            session.data = Store.emptyMailbox(); session.messageExpansion = {};
            session.hasLoadedAccounts = false;
            session.folderQuery.loading = false; session.folderQuery.refreshPending = false;
            session.htmlCache.invalidate();
            client.accountsLoaded([{id: "first", email: "user@example.test", provider: "managed-imap"}], true);
            wait(10);
        }
        function message(id, folder = "Inbox") {
            return {id, account_id: "first", conversation_id: "thread-" + id, mailbox: folder,
                from: {email: "sender@example.test"}, subject: "Message " + id, body_text: "A local message",
                date: "2026-11-16T12:00:00Z", unread: false};
        }
        function startMailbox(entries) {
            session.data = Queries.fromMailbox(session.data, entries);
            client.enabled = true;
            session.folderQuery.refresh();
            client.replyMailbox(session.folderQuery.revision, entries, true);
            wait(30);
        }
        function search(entries) {
            const before = client.searchRequests;
            session.act("search", {text: "needle"});
            tryCompare(client, "searchRequests", before + 1);
            client.replySearch(session.searchQuery.revision, entries, true);
        }
        function test_confirmedDeletionRemovesSharedRecordAndSearchMembership() {
            const entry = message("deleted", "Trash");
            startMailbox([]);
            session.act("folder", {folder: "Trash"});
            client.replyMailbox(session.folderQuery.revision, [entry], true);
            client.threadLoaded(session.threadQuery.revision, [entry], true);
            search([entry]);
            compare(session.data.search.selectedId, entry.id);
            session.act("deleteTrash");
            compare(client.deletedMessage, entry.id);
            verify(Store.find(session.data, entry.id) !== null);
            client.messageUpdated(entry.id, false);
            verify(Store.find(session.data, entry.id) !== null);
            verify(session.data.search.ids.includes(entry.id));
            session.act("deleteTrash");
            client.messageUpdated(entry.id, true); // A flag update is not a deletion confirmation.
            verify(Store.find(session.data, entry.id) !== null);
            client.messagesDeleted([entry.id]);
            client.messageUpdated(entry.id, true);
            compare(Store.find(session.data, entry.id), null);
            verify(!session.data.mailboxIds.includes(entry.id));
            verify(!session.data.search.ids.includes(entry.id));
            compare(session.data.search.selectedId, "");
        }

        function test_closePreservesSelectedHtmlAndFolderModel() {
            const entries = [];
            for (let i = 0; i < 500; ++i) entries.push(message("mail-" + i));
            startMailbox(entries);
            const normal = session.data.mailboxIds;
            const list = findChild(workspace, "messageList");
            const model = list.displayedRows;
            let countChanges = 0;
            const countChanged = () => { ++countChanges; };
            model.countChanged.connect(countChanged);
            const hit = Object.assign({}, entries[350], {body_html: "<p>Retained HTML</p>"});
            search([hit]);
            compare(session.data.mailboxIds, normal);
            session.act("select", {id: hit.id});
            client.threadLoaded(session.threadQuery.revision, [hit], true);
            tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true);
            const browser = findChild(workspace, "mailHtmlBrowser");
            const revision = browser.documentRevision;
            const results = session.data.search;
            const requests = client.mailboxRequests;
            session.act("closeSearch");
            compare(session.ui.selected, hit.id);
            compare(session.data.mailboxIds, normal);
            compare(session.data.search, results);
            compare(client.mailboxRequests, requests);
            tryCompare(list, "displayedRows", model);
            tryVerify(() => {
                const index = session.rows.findIndex(row => row.id === hit.id);
                const row = list.view.itemAtIndex(index);
                if (!row || row.messageId !== hit.id) return false;
                const y = row.mapToItem(list.view, 0, 0).y;
                return y >= 0 && y + row.height <= list.view.height + 1;
            });
            compare(session.ui.selected, hit.id);
            compare(findChild(workspace, "mailHtmlBrowser"), browser);
            compare(browser.documentRevision, revision);
            compare(countChanges, 0);
            model.countChanged.disconnect(countChanged);
            const searches = client.searchRequests;
            session.act("search", {text: "needle"});
            wait(100);
            compare(client.searchRequests, searches);
            compare(session.rows.length, 1);
        }
        function test_newSearchResultsDoNotCloseSelectedMessage() {
            startMailbox([message("inbox")]);
            const hit = Object.assign({}, message("outside", "Archive"), {body_html: "<p>Keep this document</p>"});
            search([hit]);
            session.act("select", {id: hit.id});
            client.threadLoaded(session.threadQuery.revision, [hit], true);
            tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true);
            const browser = findChild(workspace, "mailHtmlBrowser");
            session.act("search", {text: "different"});
            client.replySearch(session.searchQuery.revision, [], true);
            compare(session.selected.id, hit.id);
            session.act("closeSearch");
            compare(session.selected.id, hit.id);
            wait(50);
            compare(findChild(workspace, "mailHtmlBrowser"), browser);
        }

        function test_closeMovesToSelectedSearchResultFolderWithoutReplacingSelection() {
            startMailbox([message("inbox")]);
            const archive = Object.assign({}, message("archived", "Archive"), {body_html: "<p>Archive mail</p>"});
            search([archive]);
            session.act("select", {id: archive.id});
            client.threadLoaded(session.threadQuery.revision, [archive], true);
            tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true);
            const browser = findChild(workspace, "mailHtmlBrowser");
            session.act("closeSearch");
            compare(session.ui.folder, "Archive");
            compare(session.ui.selected, archive.id);
            tryVerify(() => session.rows.some(row => row.id === archive.id));
            wait(50);
            compare(session.ui.selected, archive.id);
            compare(findChild(workspace, "mailHtmlBrowser"), browser);
            const loaded = [archive];
            for (let i = 0; i < 200; ++i) loaded.push(Object.assign({}, message("archive-" + i, "Archive"),
                {date: "2026-11-17T12:00:00Z"}));
            client.replyMailbox(session.folderQuery.revision, loaded, true);
            const list = findChild(workspace, "messageList");
            tryVerify(() => {
                const index = session.rows.findIndex(row => row.id === archive.id);
                const item = list.view.itemAtIndex(index);
                if (!item || item.messageId !== archive.id) return false;
                const y = item.mapToItem(list.view, 0, 0).y;
                return y >= 0 && y + item.height <= list.view.height + 1;
            });
            compare(session.ui.selected, archive.id);
            compare(findChild(workspace, "mailHtmlBrowser"), browser);
        }
    }
}
