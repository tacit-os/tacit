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
        name: "StartupPrefetch"
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
        function test_visibleThreadsArePrefetchedAtStartupWithoutScrolling() {
            const entries = [];
            for (let i = 0; i < 120; ++i) entries.push(message("startup-" + i));
            startMailbox(entries);
            const list = findChild(workspace, "messageList");
            const initialOffset = list.view.contentY;
            tryVerify(() => session.visibleMessageRows.length > 1);
            const visibleKeys = new Set(session.visibleMessageRows.map(row => JSON.stringify([row.backendAccount, row.backendConversation])));
            verify(visibleKeys.size < entries.length);
            const query = session.threadQuery;
            const complete = entry => Object.assign({}, entry, {body_text: "Full message body",
                body_html: "<p>Full HTML message</p>", attachments: []});
            const selected = entries.find(entry => entry.id === session.ui.selected);
            verify(selected);
            client.threadLoaded(query.revision, [complete(selected)], true);
            for (let round = 0; round < visibleKeys.size + 2; ++round) {
                const missing = Array.from(visibleKeys).filter(key => !query.prefetched.has(key));
                if (!missing.length) break;
                tryVerify(() => query.pending.size > 0);
                verify(query.pending.size <= 2);
                for (const [ticket, pending] of Array.from(query.pending.entries())) {
                    verify(visibleKeys.has(pending.key), "An offscreen thread must not be prefetched");
                    const scope = JSON.parse(pending.key);
                    const entry = entries.find(entry => entry.conversation_id === scope[1]);
                    verify(entry);
                    const messages = [Object.assign({}, complete(entry), {id: entry.id + "-history"}), complete(entry)];
                    client.threadPrefetched(ticket, messages, true);
                    client.threadPrefetchImagesLoaded(ticket, messages);
                }
            }
            for (const key of visibleKeys) {
                const cached = query.prefetched.get(key);
                verify(cached, "Every visible conversation must have its full JSON cached without scrolling");
                verify(cached.messages.every(message => message.body_html === "<p>Full HTML message</p>"));
            }
            compare(list.view.contentY, initialOffset);
            compare(session.ui.selected, selected.id);
        }
    }
}
