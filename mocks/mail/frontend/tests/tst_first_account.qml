import QtQuick
import QtTest
import ".." as Mail
import "../mail-store.js" as Store
import "fixtures/mailbox-responses.js" as Queries

Item {
    id: fixture
    width: 1000
    height: 720

    QtObject {
        id: client
        property bool enabled: false
        property int mailboxRequests: 0
        property int threadRequests: 0
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
        function search(query, revision) {}
        function syncInbox(account) {
            lastSyncAccount = account;
            return true;
        }
    }

    Mail.MailWorkspaceSession {
        id: session
        mailboxClient: client
    }

    Component {
        id: workspaceComponent
        Mail.MailWorkspace {
            anchors.fill: parent
            controller: session
        }
    }

    TestCase {
        name: "FirstMailAccount"
        when: windowShown

        function init() {
            client.enabled = false;
            session.threadQuery.pending.clear();
            session.threadQuery.resetPrefetch();
            client.mailboxRequests = 0;
            client.threadRequests = 0;
            client.imageConsentMessage = "";
            client.lastPrefetchTicket = 0;
            client.hydratedMessages = [];
            client.lastSyncAccount = "";
            session.data = Store.emptyMailbox();
            session.hasLoadedAccounts = false;
            session.loadingAccounts = true;
            session.finishFirstImport();
            session.olderImports = ({});
            session.folderQuery.loading = false;
        }

        function test_loadImagesPersistsConsentInsteadOfAuthorizingFrontend() {
            session.allowRemoteImages("one-message");
            compare(client.imageConsentMessage, "one-message");
            verify(session.approvedRemoteImages["one-message"] !== true);
        }

        function test_mailboxCounterSurvivesPendingAndFailedCounts() {
            client.accountsLoaded([{id: "first", email: "returning@example.test", provider: "managed-imap"}], true);
            const entries = [];
            for (let i = 0; i < 6; ++i) entries.push({id: "count-" + i, account_id: "first",
                conversation_id: "count-thread-" + i, mailbox: "Inbox", from: {email: "sender@example.test"},
                subject: "Counter", body_text: "Local mail", unread: i < 3, date: "2026-11-16T12:00:00Z"});
            session.data = Queries.fromMailbox(session.data, entries);
            session.railQuery.displayedKey = "";
            const workspace = createTemporaryObject(workspaceComponent, fixture);
            verify(workspace);
            const caption = findChild(workspace, "mailboxCaption");
            verify(caption);
            verify(caption.text.includes("3 unread"));
            verify(caption.text.includes("6 total"));
            session.railQuery.error = "Local counts unavailable";
            verify(caption.text.includes("6 total"));
            session.railQuery.messages = [{account_id: "first", mailbox: "Inbox", unread: 5, total: 12}];
            session.railQuery.displayedKey = "loaded-counts";
            tryVerify(() => caption.text.includes("5 unread") && caption.text.includes("12 total"));
            session.railQuery.loading = true;
            session.railQuery.error = "Refresh failed";
            verify(caption.text.includes("12 total"));
            session.railQuery.loading = false;
            session.railQuery.messages = [];
            session.railQuery.displayedKey = "";
        }

        function test_removalWaitsForConfirmedAccountList() {
            client.accountsLoaded([{id: "first", email: "first@example.test", provider: "offline-imap"}], true);
            session.act("settings");
            session.startLocalMailRemoval("first");
            client.internetAccountRemovalProgress("other", 10, 20);
            compare(session.removalTotal, -1);
            client.internetAccountRemovalProgress("first", 50, 100);
            compare(session.removalCompleted, 50);
            compare(session.removalTotal, 100);
            compare(session.ui.view, "settings");
            client.internetAccountDisconnected("first", true, true);
            compare(session.removingLocalMailAccount, "first");
            compare(session.ui.view, "settings");
            client.accountsLoaded([], true);
            compare(session.removingLocalMailAccount, "");
            compare(session.ui.view, "setup");
        }

        function test_confirmedEmptyOpensSetupWithoutMailbox() {
            const workspace = createTemporaryObject(workspaceComponent, fixture);
            verify(workspace);
            const inbox = findChild(workspace, "inboxPane");
            const google = findChild(workspace, "provider-Google");
            verify(inbox && google);
            compare(inbox.visible, false);
            compare(google.visible, false);
            client.accountsLoaded([], true);
            compare(google.visible, true);
            compare(inbox.visible, false);
        }

        function test_failedLoadOffersRetryWithoutMailbox() {
            const workspace = createTemporaryObject(workspaceComponent, fixture);
            verify(workspace);
            const errorPage = findChild(workspace, "startupAccountError");
            const inbox = findChild(workspace, "inboxPane");
            verify(errorPage && inbox);
            client.accountsLoaded([], false);
            compare(errorPage.visible, true);
            compare(inbox.visible, false);
            errorPage.activated();
            compare(errorPage.visible, false);
            compare(inbox.visible, false);
        }

        function test_retainedAccountOpensMailbox() {
            const workspace = createTemporaryObject(workspaceComponent, fixture);
            verify(workspace);
            const inbox = findChild(workspace, "inboxPane");
            verify(inbox);
            compare(inbox.visible, false);
            client.accountsLoaded([{id: "offline", email: "offline@example.test", provider: "offline-imap"}], true);
            compare(inbox.visible, true);
        }
        function test_unfinishedImportKeepsMailboxHiddenAfterRestart() {
            const workspace = createTemporaryObject(workspaceComponent, fixture);
            verify(workspace);
            const inbox = findChild(workspace, "inboxPane");
            const progress = findChild(workspace, "firstMailImport");
            verify(inbox && progress);
            client.accountsLoaded([{id: "first", email: "resume@example.test",
                provider: "managed-imap", import_pending: true}], true);
            compare(client.lastSyncAccount, "first");
            compare(session.firstImportAccount, "first");
            compare(inbox.visible, false);
            compare(progress.visible, true);
        }

        function test_failedImportKeepsMailboxHidden() {
            const workspace = createTemporaryObject(workspaceComponent, fixture);
            verify(workspace);
            const inbox = findChild(workspace, "inboxPane");
            const progress = findChild(workspace, "firstMailImport");
            client.accountsLoaded([{id: "first", email: "new@example.test",
                provider: "managed-imap", import_pending: true}], true);
            client.inboxSyncFinished("first", false);
            compare(session.firstImportInterrupted, true);
            compare(inbox.visible, false);
            compare(progress.visible, true);
            const detail = findChild(workspace, "mailProgressDetail");
            compare(detail.text, "Mail import paused. Tacit will retry automatically.");
            client.accountSyncStatus("first", {google_sign_in_again: true}, false);
            compare(detail.text, "Sign in to Google again to continue importing mail.");
            client.inboxImportProgress("first", 25, 100);
            compare(session.firstImportInterrupted, false);
        }

        function test_retryKeepsProgressAndLayoutUntilNewMailArrives() {
            const workspace = createTemporaryObject(workspaceComponent, fixture);
            verify(workspace);
            client.accountsLoaded([{id: "first", email: "new@example.test",
                provider: "managed-imap", import_pending: true}], true);
            const progress = findChild(workspace, "firstMailImport");
            const detail = findChild(workspace, "mailProgressDetail");
            client.inboxImportProgress("first", 25, 100);
            tryCompare(detail, "text", "25 of 100 messages downloaded.");
            wait(0);
            const previousY = progress.y;
            client.inboxSyncFinished("first", false);
            client.inboxImportProgress("first", -3, 0);
            client.inboxImportProgress("first", 25, 100);
            wait(0);
            compare(progress.y, previousY);
            compare(session.displayedImportDownloaded, 25);
            compare(session.importTotal, 100);
            compare(detail.text, "Mail import paused. Tacit will retry automatically.");
            client.inboxImportProgress("first", 26, 100);
            tryCompare(detail, "text", "26 of 100 messages downloaded.");
            compare(progress.y, previousY);
        }

        function test_waitingForProviderKeepsTheConfirmedCount() {
            const workspace = createTemporaryObject(workspaceComponent, fixture);
            verify(workspace);
            client.accountsLoaded([{id: "first", email: "new@example.test",
                provider: "managed-imap", import_pending: true}], true);
            const hint = findChild(workspace, "waitingForMailProvider");
            verify(hint);
            client.inboxImportProgress("first", 25, 100);
            client.inboxImportProgress("first", -5, 1);
            verify(hint.visible);
            compare(session.displayedImportDownloaded, 25);
            compare(session.importTotal, 100);
            client.inboxImportProgress("first", 26, 100);
            verify(hint.visible);
            client.inboxImportProgress("first", -5, 0);
            verify(!hint.visible);
        }

        function test_completedAccountSyncsInBackground() {
            client.accountsLoaded([{id: "first", email: "returning@example.test",
                provider: "managed-imap"}], true);
            compare(session.firstImportAccount, "");
        }

        function test_importScreenShowsCurrentPreparationStep() {
            const workspace = createTemporaryObject(workspaceComponent, fixture);
            verify(workspace);
            client.accountsLoaded([{id: "first", email: "returning@example.test",
                provider: "managed-imap", import_pending: true}], true);
            const detail = findChild(workspace, "mailProgressDetail");
            verify(detail);
            client.inboxImportProgress("first", -3, 1);
            compare(detail.text, "Connecting to your mail provider…");
            client.inboxImportProgress("first", -3, 4);
            compare(detail.text, "Checking the Inbox for mail from the past year…");
            client.inboxImportProgress("first", 1, 50);
            compare(detail.text, "1 of 50 messages downloaded.");
            client.inboxImportProgress("first", -3, 10);
            compare(detail.text, "1 of 50 messages downloaded. Checking for mailbox changes…");
            compare(session.importTotal, 50);
            client.inboxImportProgress("first", 2, 50);
            tryCompare(detail, "text", "2 of 50 messages downloaded.");
            client.inboxImportProgress("first", -3, 11);
            tryVerify(() => session.importBatchWaitSeconds >= 1);
            verify(detail.text.indexOf("Waiting for the next batch") >= 0);
            compare(session.displayedImportDownloaded, 2);
            client.inboxImportProgress("first", 5, 50);
            compare(session.displayedImportDownloaded, 2);
            tryCompare(detail, "text", "5 of 50 messages downloaded.");
        }

        function test_cleanGmailImportStartsForegroundForAnExistingAccount() {
            client.accountsLoaded([{id: "gmail", email: "returning@example.test",
                provider: "managed-imap"}], true);
            compare(session.firstImportAccount, "");
            client.inboxImportProgress("gmail", -4, 0);
            compare(session.firstImportAccount, "gmail");
            compare(session.importTotal, -1);
        }

        function test_recentImportOpensMailboxWhileOlderMailLoads() {
            session.showFirstImport("first");
            client.inboxImportProgress("first", 25, 25);
            compare(session.firstImportAccount, "first");
            client.inboxImportProgress("first", -2, 0);
            if (session.waitingForImportedInbox)
                client.replyMailbox(session.folderQuery.revision, [], true);
            compare(session.firstImportAccount, "");
            verify(session.loadingOlderMail);
            client.inboxImportProgress("first", 50, 100);
            compare(session.olderImportProgress.saved, 50);
            compare(session.olderImportProgress.total, 100);
            client.inboxSyncFinished("first", false);
            verify(session.olderImportProgress.interrupted);
            client.inboxImportProgress("first", 75, 100);
            verify(!session.olderImportProgress.interrupted);
            client.inboxSyncFinished("first", true);
            verify(!session.loadingOlderMail);
        }

        function test_searchFooterShowsProgressAndSearchSortsNewerFirst() {
            const workspace = createTemporaryObject(workspaceComponent, fixture);
            verify(workspace);
            client.accountsLoaded([{id: "first", email: "returning@example.test",
                provider: "managed-imap", import_pending: true, recent_import_ready: true}], true);
            session.act("search", {text: "fixture"});
            client.inboxImportProgress("first", 20, 80);
            const footer = findChild(workspace, "olderMailFooter");
            verify(footer);
            verify(footer.visible);
            compare(session.rows.length, 0);
            compare(footer.progress.saved, 20);
            const hits = [{id: "old", account_id: "first", date: "2017-01-01T00:00:00Z",
                from: {email: "tester@example.test"}, mailbox: "Archive", subject: "Fixture old"},
                {id: "recent", account_id: "first", date: "2025-01-01T00:00:00Z",
                    from: {email: "tester@example.test"}, mailbox: "Inbox", subject: "Fixture recent"}];
            client.replySearch(session.searchQuery.revision, [hits[1], hits[0]], true);
            compare(session.rows.map(row => row.id), ["recent", "old"]);
            client.inboxSyncFinished("first", true);
            verify(!footer.visible);
        }

        function test_restartDuringOlderImportOpensMailbox() {
            client.accountsLoaded([{id: "first", email: "returning@example.test",
                provider: "managed-imap", import_pending: true, recent_import_ready: true}], true);
            compare(session.firstImportAccount, "");
            verify(session.loadingOlderMail);
        }

        function test_backgroundRefreshKeepsHtmlAndScrollPosition() {
            client.accountsLoaded([{id: "first", email: "returning@example.test",
                provider: "managed-imap"}], true);
            const workspace = createTemporaryObject(workspaceComponent, fixture);
            const cached = {id: "cached", account_id: "first", mailbox: "Inbox",
                conversation_id: "thread", from: {email: "sender@example.test"},
                subject: "Long HTML", body_html: "<p>Already saved content</p>".repeat(120),
                date: "2026-11-16T12:00:00Z"};
            session.data = Queries.fromMailbox(session.data, [cached]);
            client.threadLoaded(session.threadQuery.revision, [cached], true);
            tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true);
            const browser = findChild(workspace, "mailHtmlBrowser");
            const scroll = findChild(workspace, "readingScroll");
            tryVerify(() => scroll.contentHeight > scroll.height + 300);
            scroll.movementStarted();
            scroll.contentY = 240;
            wait(0);
            const position = scroll.contentY;
            const documentRevision = browser.documentRevision;
            const messages = session.threadQuery.messages;

            for (let pulse = 0; pulse < 3; ++pulse) {
                client.mailboxInvalidated();
                verify(session.selected !== null);
                verify(!session.threadQuery.loading);
                client.threadLoaded(session.threadQuery.revision, [cached], true);
                wait(0);
                verify(session.threadQuery.messages === messages);
                compare(findChild(workspace, "mailHtmlBrowser"), browser);
                compare(browser.documentRevision, documentRevision);
                compare(scroll.contentY, position);
            }
            const changed = Object.assign({}, cached, {unread: true});
            session.threadQuery.refresh();
            client.threadLoaded(session.threadQuery.revision, [changed], true);
            verify(session.selected.unread === false);
            compare(browser.documentRevision, documentRevision);
            compare(scroll.contentY, position);

            session.threadQuery.refresh();
            client.threadLoaded(session.threadQuery.revision, [], false);
            verify(session.selected !== null);
            compare(browser.documentRevision, documentRevision);
            compare(scroll.contentY, position);
        }

        function test_backgroundRefreshKeepsResolvedInlineImages() {
            client.accountsLoaded([{id: "first", email: "returning@example.test",
                provider: "managed-imap"}], true);
            const cached = {id: "cached", account_id: "first", mailbox: "Inbox",
                conversation_id: "thread", from: {email: "sender@example.test"},
                subject: "Local image", body_html: '<img src="cid:picture">',
                attachments: [{id: "picture", filename: "picture.png", media_type: "image/png", size: 4}],
                date: "2026-11-16T12:00:00Z"};
            session.data = Queries.fromMailbox(session.data, [cached]);
            client.threadLoaded(session.threadQuery.revision, [cached], true);
            const uri = "tacit-image://mail/v1/messages/cached/attachments/picture";
            const hydrated = Object.assign({}, cached, {
                attachments: [Object.assign({}, cached.attachments[0], {inline: true, inlineSource: uri})]});
            client.threadMessageLoaded(session.threadQuery.revision, hydrated);
            const messages = session.threadQuery.messages;
            session.threadQuery.refresh();
            client.threadLoaded(session.threadQuery.revision, [cached], true);
            verify(session.threadQuery.messages === messages);
            session.threadQuery.refresh();
            client.threadLoaded(session.threadQuery.revision, [Object.assign({}, cached, {flagged: true})], true);
            verify(session.threadQuery.messages[0].flagged);
            compare(session.selected.bodyHtml, hydrated.body_html);
            compare(session.selected.files[0].inlineSource, uri);
        }

        function test_cachedHtmlWaitsForCompleteThread() {
            client.accountsLoaded([{id: "first", email: "returning@example.test",
                provider: "managed-imap"}], true);
            const workspace = createTemporaryObject(workspaceComponent, fixture);
            verify(workspace);
            const cached = {id: "cached", account_id: "first", mailbox: "Inbox",
                conversation_id: "thread", from: {email: "sender@example.test"},
                subject: "Cached HTML", body_html: "<p>Already saved</p>",
                date: "2026-11-16T12:00:00Z"};
            session.data = Queries.fromMailbox(session.data, [cached]);
            session.act("select", {id: "cached"});
            verify(session.threadQuery.loading);
            compare(session.selected, null);
            const older = Object.assign({}, cached, {id: "older", body_html: "<p>History</p>"});
            client.threadLoaded(session.threadQuery.revision, [older, cached], true);
            verify(!session.threadQuery.loading);
            compare(session.selected.history[0].id, "older");
            tryVerify(() => findChild(workspace, "mailHtmlBrowser")?.loaded === true);
        }

        function test_prefetchedThreadIsAvailableOnSelection_data() {
            return [{tag: "completed", finished: true}, {tag: "in flight", finished: false}];
        }

        function test_prefetchedThreadIsAvailableOnSelection(row) {
            client.accountsLoaded([{id: "first", email: "returning@example.test",
                provider: "managed-imap"}], true);
            const current = {id: "current", account_id: "first", mailbox: "Inbox",
                conversation_id: "current-thread", from: {email: "sender@example.test"},
                subject: "Current", date: "2026-11-16T12:00:00Z"};
            const next = Object.assign({}, current, {id: "next", conversation_id: "next-thread"});
            const history = Object.assign({}, next, {id: "history"});
            session.data = Queries.fromMailbox(session.data, [current, next]);
            session.act("select", {id: "current"});
            client.enabled = true;
            session.visibleMessageRows = session.rows;
            session.threadQuery.prefetch();
            verify(client.lastPrefetchTicket > 0);
            const ticket = client.lastPrefetchTicket;
            const requests = client.threadRequests;
            const hydrated = Object.assign({}, next, {body_html: "<img src='data:image/png;base64,AQ=='>",
                attachments: [{id: "picture", filename: "picture.png", media_type: "image/png",
                    inline: true, inlineSource: "data:image/png;base64,AQ=="}]});
            if (row.finished) {
                client.threadPrefetched(ticket, [history, next], true);
                client.threadPrefetchImagesLoaded(ticket, [history, hydrated]);
            }

            session.act("select", {id: "next"});
            compare(client.threadRequests, requests);
            if (!row.finished) {
                verify(session.threadQuery.loading);
                compare(session.selected, null);
                client.threadPrefetched(ticket, [history, next], true);
                compare(session.selected.history[0].id, "history");
                client.threadPrefetchImagesLoaded(ticket, [history, hydrated]);
            }
            verify(!session.threadQuery.loading);
            compare(session.selected.history[0].id, "history");
            compare(session.selected.bodyHtml, hydrated.body_html);
            compare(client.hydratedMessages.length, 0);
        }

        function test_backgroundSyncKeepsRecentThreadImmediatelyAvailable() {
            client.accountsLoaded([{id: "first", email: "returning@example.test", provider: "managed-imap"}], true);
            const first = {id: "first-mail", account_id: "first", mailbox: "Inbox", conversation_id: "first-thread",
                from: {email: "sender@example.test"}, subject: "First", body_text: "Full local body",
                date: "2026-11-16T12:00:00Z"};
            const second = Object.assign({}, first, {id: "second-mail", conversation_id: "second-thread"});
            session.data = Queries.fromMailbox(session.data, [first, second]);
            session.act("select", {id: first.id});
            client.threadLoaded(session.threadQuery.revision, [first], true);
            session.act("select", {id: second.id});
            client.threadLoaded(session.threadQuery.revision, [second], true);
            client.mailboxInvalidated();
            const requests = client.threadRequests;
            session.act("select", {id: first.id});
            verify(!session.threadQuery.loading);
            compare(session.selected.id, first.id);
            compare(session.selected.body, first.body_text);
            compare(client.threadRequests, requests + 1); // Refresh metadata without blanking the cached thread.
        }

        function test_threadImagesArriveIndependentlyWithoutReorderingMessages() {
            client.accountsLoaded([{id: "first", email: "returning@example.test",
                provider: "managed-imap"}], true);
            const cached = {id: "current", account_id: "first", mailbox: "Inbox",
                conversation_id: "thread", from: {email: "sender@example.test"},
                subject: "Thread", body_html: "<p>Current</p>", date: "2026-11-16T12:00:00Z"};
            session.data = Queries.fromMailbox(session.data, [cached]);
            const older = Object.assign({}, cached, {id: "older", body_html: "<img src='cid:one'>"});
            const middle = Object.assign({}, cached, {id: "middle", body_html: "<img src='cid:two'>"});
            const revision = session.threadQuery.revision;
            client.threadLoaded(revision, [older, middle, cached], true);
            verify(!session.threadQuery.loading);
            compare(session.selected.history.map(entry => entry.id).join(","), "older,middle");

            const loadedMiddle = Object.assign({}, middle, {body_html: "<img src='data:image/png;base64,AQ=='>"});
            client.threadMessageLoaded(revision, loadedMiddle);
            compare(session.selected.history[0].bodyHtml, older.body_html);
            compare(session.selected.history[1].bodyHtml, loadedMiddle.body_html);

            session.threadQuery.refresh();
            client.threadMessageLoaded(revision, Object.assign({}, older, {body_html: "Stale update"}));
            compare(session.selected.history[0].bodyHtml, older.body_html);
        }

        function test_cachedInboxOpensDuringFailingOlderImport() {
            client.accountsLoaded([{id: "first", email: "returning@example.test",
                provider: "managed-imap", import_pending: true, recent_import_ready: true}], true);
            client.enabled = true;
            session.folderQuery.refresh();
            const revision = session.folderQuery.revision;

            session.folderQuery.refresh();
            session.folderQuery.refresh();
            client.accountSyncStatus("first", {}, false);
            client.inboxSyncFinished("first", false);
            compare(session.folderQuery.revision, revision);
            compare(client.mailboxRequests, 1);
            compare(session.rows.length, 0);

            const cached = {id: "cached", account_id: "first", mailbox: "Inbox",
                from: {email: "sender@example.test"}, subject: "Cached mail",
                date: "2026-11-16T12:00:00Z"};
            client.replyFirstPage(revision, [cached]);
            compare(session.rows.length, 1);
            compare(session.rows[0].id, "cached");
            verify(session.folderQuery.loading);

            const older = Object.assign({}, cached, {id: "older", date: "2026-11-15T12:00:00Z"});
            client.replyMailbox(revision, [cached, older], true);
            compare(session.rows.length, 2);
            compare(session.folderQuery.revision, revision + 1);
            compare(client.mailboxRequests, 2);
            client.replyFirstPage(revision + 1, [cached]);
            compare(session.rows.length, 2);
            client.replyMailbox(revision + 1, [], false);
            compare(session.rows.length, 2);
        }

        function test_firstImportWaitsForMatchingCompletion() {
            session.act("setup");
            client.internetAccountConnected(true, "", "first");
            compare(session.ui.view, "read");
            compare(session.firstImportAccount, "first");
            compare(session.importTotal, -1);
            client.inboxImportProgress("first", 25, 25);
            compare(session.importDownloaded, 25);
            compare(session.firstImportAccount, "first");
            client.inboxSyncFinished("other", true);
            compare(session.firstImportAccount, "first");
            session.folderQuery.loading = true;
            client.inboxSyncFinished("first", true);
            compare(session.firstImportAccount, "first");
            compare(session.waitingForImportedInbox, true);
            client.replyMailbox(session.folderQuery.revision, [], true);
            compare(session.firstImportAccount, "");
        }
    }
}
