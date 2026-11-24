import QtQuick
import "mail-store.js" as Store

QtObject {
    id: state
    property var visibleMessageRows: []
    property MailReadingState readingState: MailReadingState {
        id: reader
        data: state.data
        client: state.mailboxClient
        visibleRows: state.visibleMessageRows
    }
    property alias messageExpansion: reader.messageExpansion
    property alias threadScrollPositions: reader.threadScrollPositions
    readonly property var quotedHistoryExpansion: reader.quotedHistoryExpansion
    property alias htmlCache: reader.htmlCache
    property alias approvedRemoteImages: reader.approvedRemoteImages
    property alias readingPreferences: reader.preferences
    property alias threadQuery: reader.threadQuery

    function setQuotedHistoryExpanded(messageId, expanded) {
        reader.setQuotedHistoryExpanded(messageId, expanded);
    }
    function allowRemoteImages(messageId) { reader.allowRemoteImages(messageId); }
    property color agentInk
    property var reduceAction: Store.reduce
    property var queryRows: Store.results
    property var data: Store.emptyMailbox()
    onMailboxClientChanged: {
        hasLoadedAccounts = false;
        if (mailboxClient) {
            requestAccounts();
            mailboxClient.imagePolicy("", "", ++globalImageRevision);
        }
    }
    property int globalImageRevision: 0
    readonly property var ui: data.ui
    readonly property var selectedRow: reader.selectedRow
    readonly property var threadMessages: reader.threadMessages
    readonly property var selected: reader.selected
    readonly property bool canReplyAll: reader.canReplyAll
    readonly property var draft: Store.draft(data)
    property var mailboxClient: null
    property bool loadingAccounts: !!mailboxClient
    property bool hasLoadedAccounts: false
    function requestAccounts() {
        loadingAccounts = true;
        mailboxClient.loadAccounts();
    }
    property int inboxSyncsPending: 0
    property var syncStatusByAccount: ({})
    property var pendingDraftSuggestion: null
    property string firstImportAccount: ""
    property bool firstImportInterrupted: false
    property int retryImportDownloaded: -1
    property string removingLocalMailAccount: ""
    property int removalCompleted: 0
    property int removalTotal: -1
    property bool waitingForRemovalAccounts: false
    function startLocalMailRemoval(account) {
        removalCompleted = 0;
        removalTotal = -1;
        waitingForRemovalAccounts = false;
        removingLocalMailAccount = account;
    }
    property bool waitingForImportedInbox: false
    property int importDownloaded: 0
    property int displayedImportDownloaded: 0
    property real importBatchStartedAt: 0
    property int importBatchWaitSeconds: 0

    property Timer countImportedMail: Timer {
        interval: 32
        repeat: true
        running: !!state.firstImportAccount && !state.firstImportInterrupted
            && state.displayedImportDownloaded < state.importDownloaded
        onTriggered: ++state.displayedImportDownloaded
    }

    property Timer measureImportBatchWait: Timer {
        interval: 1000
        repeat: true
        running: !!state.firstImportAccount && !state.firstImportInterrupted
            && state.importPreparation === 11
        onTriggered: state.importBatchWaitSeconds = Math.floor((Date.now() - state.importBatchStartedAt) / 1000)
    }
    property int importTotal: -1
    property int importPreparation: -1
    readonly property string importPreparationText: {
        switch (importPreparation) {
        case 0: return qsTr("Signing in to your mail provider…");
        case 1: return qsTr("Connecting to your mail provider…");
        case 2: return qsTr("Finding your mail folders…");
        case 3: return qsTr("Checking which messages are already saved…");
        case 4: return qsTr("Checking the Inbox for mail from the past year…");
        case 5: return qsTr("Checking the Archive for mail from the past year…");
        case 6: return qsTr("Checking Sent for mail from the past year…");
        case 7: return qsTr("Checking Spam for mail from the past year…");
        case 8: return qsTr("Checking Trash for mail from the past year…");
        case 9: return qsTr("Checking a folder for mail from the past year…");
        default: return qsTr("Preparing to sync your mail…");
        }
    }
    property var waitingForMailProvider: ({})
    readonly property bool olderImportWaitingForProvider: Object.keys(olderImports).some(account => waitingForMailProvider[account])

    function setWaitingForMailProvider(account, waiting) {
        if (!!waitingForMailProvider[account] === waiting)
            return;
        const updated = Object.assign({}, waitingForMailProvider);
        if (waiting)
            updated[account] = true;
        else
            delete updated[account];
        waitingForMailProvider = updated;
    }

    property var olderImports: ({})
    readonly property var olderImportProgress: Object.values(olderImports).reduce((sum, entry) => ({
        saved: sum.saved + entry.saved,
        total: sum.total + Math.max(0, entry.total),
        waiting: sum.waiting || entry.total < 0,
        interrupted: sum.interrupted || entry.interrupted
    }), {saved: 0, total: 0, waiting: false, interrupted: false})
    readonly property bool loadingOlderMail: Object.keys(olderImports).length > 0

    function updateOlderImport(account, saved, total, interrupted) {
        const updated = Object.assign({}, olderImports);
        updated[account] = {saved: saved, total: total, interrupted: interrupted};
        olderImports = updated;
    }

    property Timer refreshImportSearch: Timer {
        interval: 1000
        onTriggered: state.searchQuery.refresh()
    }
    property string conversationUndoToken: ""
    property bool conversationTrashBusy: false
    property var outbox: ({})
    function suggestDraft() {
        const current = draft;
        if (!mailboxClient || !current || pendingDraftSuggestion)
            return;
        if (!current.to.trim()) {
            act("notice", {text: qsTr("Add a recipient first.")});
            return;
        }
        const scope = settings.agentScope;
        if (scope !== "All accounts" && scope !== current.account + " only") {
            act("notice", {text: qsTr("This account is outside the agent’s allowed mail. Check Settings.")});
            return;
        }
        if (!current.backendAccount) {
            act("notice", {text: qsTr("Choose an account for this draft first.")});
            return;
        }
        pendingDraftSuggestion = {id: current.id, body: current.body, to: current.to, subject: current.subject,
            account: current.backendAccount};
        mailboxClient.requestDraftSuggestion(current.backendAccount, current.sourceId || current.conversation || "",
            current.body, current.subject, Store.emails(current.to), scope === "All accounts");
    }
    function showFirstImport(account) {
        if (ui.folder !== "Inbox" || ui.account !== "All accounts" || ui.searching)
            act("folder", {folder: "Inbox", account: "All accounts"});
        importDownloaded = 0;
        displayedImportDownloaded = 0;
        importBatchWaitSeconds = 0;
        importTotal = -1;
        importPreparation = -1;
        firstImportInterrupted = false;
        waitingForImportedInbox = false;
        firstImportAccount = account;
    }

    function finishFirstImport() {
        firstImportInterrupted = false;
        waitingForImportedInbox = false;
        firstImportAccount = "";
    }
    property Connections outboxResponses: Connections {
        target: state.mailboxClient
        ignoreUnknownSignals: true
        function onDraftSuggestionReady(body, error) {
            const pending = state.pendingDraftSuggestion;
            state.pendingDraftSuggestion = null;
            if (!pending)
                return;
            const current = state.draft;
            if (!current || current.id !== pending.id)
                return;
            if (!body) {
                state.act("notice", {text: error === "local_model_unavailable"
                    ? qsTr("No local model could answer. Check the local model setup.")
                    : qsTr("Could not prepare a draft suggestion.")});
                return;
            }
            if (current.body !== pending.body || current.to !== pending.to || current.subject !== pending.subject
                    || current.backendAccount !== pending.account) {
                state.act("notice", {text: qsTr("The draft changed while the agent was working. Your edits were kept.")});
                return;
            }
            state.act("draft", {agent: true, edited: false, body: body});
        }
        function onAccountSyncStatus(account, result, ok) {
            const previous = state.syncStatusByAccount[account] || {};
            const status = ok ? {
                failed: false, lastSynced: result.last_synced || Date.now(), folders: result.synced_folders || {},
                sentCopyPending: !!result.sent_copy_pending
            } : Object.assign({}, previous, {failed: true, googleSignInAgain: !!result.google_sign_in_again});
            state.syncStatusByAccount = Object.assign({}, state.syncStatusByAccount, {[account]: status});
        }
        function onMessageImagesAllowed(messageId, ok) {
            if (!ok) state.act("notice", {text: qsTr("Could not save image permission.")});
        }
        function onImagePolicyLoaded(id, revision, result, ok) {
            if (id || revision !== state.globalImageRevision)
                return;
            if (!ok) {
                state.act("notice", {text: qsTr("Could not load or save image preferences.")});
                return;
            }
            const labels = {ask_first: "Ask first", always: "Always", never: "Never"};
            state.data = Object.assign({}, state.data, {
                settings: Object.assign({}, state.data.settings, {pictures: labels[result.policy]})
            });
        }
        function onAccountsLoaded(accounts, ok) {
            state.loadingAccounts = false;
            if (!ok) {
                if (state.waitingForRemovalAccounts) {
                    state.waitingForRemovalAccounts = false;
                    state.removingLocalMailAccount = "";
                    state.act("notice", {text: qsTr("Local mail was removed, but Tacit could not refresh the account list.")});
                }
                if (state.firstImportAccount) {
                    state.firstImportInterrupted = true;
                }
                return;
            }
            const mapped = accounts.map(account => ({
                id: account.id,
                name: Store.accountLabel([], account.id) !== account.id
                    ? Store.accountLabel([], account.id) : account.name || account.email,
                email: account.email,
                provider: account.provider,
                categoryProvider: account.category_provider || "",
                importPending: !!account.import_pending,
                recentImportReady: !!account.recent_import_ready
            }));
            const statuses = {};
            for (const account of accounts) {
                const latest = state.syncStatusByAccount[account.id];
                const snapshot = account.sync_snapshot;
                if (latest)
                    statuses[account.id] = latest;
                else if (snapshot)
                    statuses[account.id] = {failed: false, lastSynced: snapshot.last_synced,
                        folders: snapshot.synced_folders || {}, sentCopyPending: !!snapshot.sent_copy_pending};
            }
            state.syncStatusByAccount = statuses;
            const labelRow = row => row.backendAccount
                ? Object.assign({}, row, {account: Store.accountLabel(mapped, row.backendAccount)}) : row;
            state.data = Object.assign({}, Store.upsertMessages(state.data, Object.values(state.data.records).map(labelRow)), {
                accounts: mapped,
                drafts: state.data.drafts.map(labelRow)
            });
            // Without a stored account, maild has no mailbox to show.
            if (!mapped.length && state.ui.view !== "setup")
                state.act("setup");
            if (state.waitingForRemovalAccounts && !mapped.some(account => account.id === state.removingLocalMailAccount)) {
                state.waitingForRemovalAccounts = false;
                state.removingLocalMailAccount = "";
            }
            const remoteAccounts = mapped.filter(account => ["imap-smtp", "managed-imap"].includes(account.provider));
            if (state.firstImportAccount && !remoteAccounts.some(account => account.id === state.firstImportAccount))
                state.finishFirstImport();
            const older = {};
            for (const account of remoteAccounts) {
                if (account.importPending && account.recentImportReady)
                    older[account.id] = state.olderImports[account.id] || {saved: 0, total: -1, interrupted: false};
            }
            state.olderImports = older;
            const waiting = {};
            for (const account of remoteAccounts)
                if (state.waitingForMailProvider[account.id])
                    waiting[account.id] = true;
            state.waitingForMailProvider = waiting;
            const pendingImport = remoteAccounts.find(account => account.importPending && !account.recentImportReady);
            if (pendingImport && !state.firstImportAccount)
                state.showFirstImport(pendingImport.id);
            for (const account of remoteAccounts)
                if (state.mailboxClient.syncInbox(account.id))
                    ++state.inboxSyncsPending;
            state.hasLoadedAccounts = true;
        }
        function onInternetAccountRemovalProgress(id, removed, total) {
            if (id !== state.removingLocalMailAccount)
                return;
            state.removalCompleted = removed;
            state.removalTotal = total;
        }
        function onInternetAccountDisconnected(id, removed, ok) {
            if (removed && id === state.removingLocalMailAccount) {
                state.waitingForRemovalAccounts = ok;
                if (!ok)
                    state.removingLocalMailAccount = "";
            }
            if (!ok)
                return;
            if (removed) {
                reader.invalidate();
            }
            state.outbox = Object.fromEntries(Object.entries(state.outbox).filter(
                entry => entry[1].message?.account_id !== id));
            if (removed && state.ui.account === id)
                state.act("folder", {folder: "Inbox", account: "All accounts"});
        }
        function onInternetAccountConnected(ok, error, account) {
            if (!ok || !account)
                return;
            if (state.ui.view === "setup")
                state.act("back");
            state.showFirstImport(account);
        }
        function onInboxImportProgress(account, downloaded, total) {
            if (downloaded === -5) {
                state.setWaitingForMailProvider(account, total > 0);
                return;
            }
            if (downloaded === -2)
                state.setWaitingForMailProvider(account, false);
            if (downloaded === -4) {
                if (!state.firstImportAccount || state.firstImportAccount === account)
                    state.showFirstImport(account);
                return;
            }
            if (downloaded === -3) {
                if (account === state.firstImportAccount && !state.firstImportInterrupted) {
                    state.importPreparation = total;
                    if (total < 10)
                        state.importTotal = -1;
                    if (total === 11) {
                        state.importBatchStartedAt = Date.now();
                        state.importBatchWaitSeconds = 0;
                    }
                }
                return;
            }
            if (downloaded === -2) {
                if (!state.olderImports[account])
                    state.updateOlderImport(account, 0, -1, false);
                state.data = Object.assign({}, state.data, {
                    accounts: state.accounts.map(entry => entry.id === account
                        ? Object.assign({}, entry, {recentImportReady: true}) : entry)
                });
                if (account === state.firstImportAccount) {
                    state.firstImportInterrupted = false;
                    state.folderQuery.refresh();
                    if (state.folderQuery.loading)
                        state.waitingForImportedInbox = true;
                    else
                        state.finishFirstImport();
                }
                return;
            }
            if (downloaded < 0)
                return;
            if (state.olderImports[account]) {
                state.updateOlderImport(account, downloaded, total, false);
                if (!state.refreshImportSearch.running && state.ui.searching)
                    state.refreshImportSearch.start();
                return;
            }
            if (account !== state.firstImportAccount)
                return;
            if (state.firstImportInterrupted) {
                const previous = state.retryImportDownloaded >= 0 ? state.retryImportDownloaded : state.importDownloaded;
                if (downloaded <= previous) {
                    state.retryImportDownloaded = downloaded;
                    return;
                }
                state.firstImportInterrupted = false;
            }
            state.importPreparation = -1;
            if (state.importTotal < 0 || downloaded < state.importDownloaded)
                state.displayedImportDownloaded = downloaded;
            state.importDownloaded = downloaded;
            state.importTotal = total;
        }
        function onNewMailArrived(unread, likelyPersonal) {
            const mode = state.settings.notifications;
            const count = mode === "All new mail" ? unread : mode === "From people only" ? likelyPersonal : 0;
            if (count > 0 && !state.ui.notice)
                state.act("notice", {text: qsTr("%n new message(s)", "", count)});
        }
        function onInboxSyncFinished(account, ok) {
            state.setWaitingForMailProvider(account, false);
            state.inboxSyncsPending = Math.max(0, state.inboxSyncsPending - 1);
            if (ok && state.accounts.some(entry => entry.id === account && entry.importPending)) {
                state.data = Object.assign({}, state.data, {
                    accounts: state.accounts.map(entry => entry.id === account
                        ? Object.assign({}, entry, {importPending: false}) : entry)
                });
            }
            const older = state.olderImports[account];
            if (older) {
                if (!ok) {
                    state.updateOlderImport(account, older.saved, older.total, true);
                } else {
                    const updated = Object.assign({}, state.olderImports);
                    delete updated[account];
                    state.olderImports = updated;
                    state.searchQuery.refresh();
                }
            }
            if (account === state.firstImportAccount) {
                if (!ok) {
                    state.retryImportDownloaded = -1;
                    state.firstImportInterrupted = true;
                    return;
                }
                const pending = state.accounts.find(entry => entry.importPending && !entry.recentImportReady);
                if (pending) {
                    state.showFirstImport(pending.id);
                } else if (state.folderQuery.loading) {
                    state.waitingForImportedInbox = true;
                } else {
                    state.finishFirstImport();
                }
            }
            if (!ok)
                state.act("notice", {text: qsTr("Could not sync the inbox with the mail provider.")});
        }
        function onConversationTrashed(token) {
            state.conversationTrashBusy = false;
            if (token) {
                state.conversationUndoToken = token;
                state.act("notice", {text: qsTr("Conversation moved to Trash.")});
                onMailboxInvalidated();
            } else {
                state.act("notice", {text: qsTr("Could not move the conversation to Trash.")});
            }
        }
        function onConversationTrashUndone(ok) {
            state.conversationTrashBusy = false;
            if (ok) {
                state.conversationUndoToken = "";
                state.act("notice", {text: qsTr("Conversation restored.")});
                onMailboxInvalidated();
            } else {
                state.act("notice", {text: qsTr("Could not restore the conversation.")});
            }
        }
        function onMessagesDeleted(ids) {
            state.data = Store.removeMessages(state.data, ids, true);
        }
        function onMessageUpdated(id, ok) {
            if (ok) {
                state.railQuery.refresh();
                state.draftQuery.refresh();
                if (state.folderQuery.key)
                    state.folderQuery.refresh();
                state.threadQuery.refresh();
                if (state.ui.searching) state.searchQuery.refresh();
            } else {
                state.act("notice", {text: qsTr("Could not update the message.")});
            }
        }
        function onMailboxInvalidated() {
            state.threadQuery.resetPrefetch(true);
            if (state.ui.searching) state.searchQuery.refresh();
            state.railQuery.refresh();
            if (state.folderQuery.key)
                state.folderQuery.refresh();
            state.threadQuery.refresh();
            state.draftQuery.refresh();
        }
        function onOutboxChanged(job) {
            const active = state.draft;
            if (active && (state.savedDraftIds[active.id] || active.backendId) === job.message_id
                    && ["queued", "sending", "sent"].includes(job.state)) {
                state.data = Object.assign({}, state.data, {
                    drafts: state.data.drafts.filter(draft => draft.id !== active.id),
                    ui: Object.assign({}, state.ui, {view: "read", draftId: ""})
                });
            }
            const next = Object.assign({}, state.outbox);
            if (["sent", "cancelled"].includes(job.state)) {
                state.railQuery.refresh();
                delete next[job.id];
                state.draftQuery.refresh();
            }
            else
                next[job.id] = job;
            state.outbox = next;
            if (job.state === "queued" && job.undo_until > Date.now())
                state.act("notice", {text: qsTr("Sending soon")});
            if (job.state === "sent" && state.ui.notice === qsTr("Sending soon") && !state.undoAvailable)
                state.act("notice", {text: qsTr("Message sent.")});
            if (job.state === "cancelled")
                state.act("notice", {text: qsTr("Sending cancelled. Draft restored.")});
            if (job.state === "failed" || job.state === "uncertain")
                state.act("notice", {text: job.last_error || qsTr("Message delivery failed.")});
        }
    }
    property MailDraftQuery draftQuery: MailDraftQuery {
        client: state.mailboxClient
        onRefreshed: messages => {
            const loaded = Store.mailboxDrafts(state.data.accounts, messages, Store.mailboxMessages(state.data));
            const working = state.data.drafts.filter(draft =>
                !draft.backendId || draft.id === state.ui.draftId && ["draft", "compose"].includes(state.ui.view));
            const represented = new Set(working.map(draft => state.savedDraftIds[draft.id] || draft.backendId));
            const updated = Object.assign({}, state.data, {
                ui: Object.assign({}, state.ui),
                drafts: working.concat(loaded.filter(draft => !represented.has(draft.id)))
            });
            Store.showReplyDraft(updated);
            if (JSON.stringify(updated.drafts) !== JSON.stringify(state.data.drafts)
                    || JSON.stringify(updated.ui) !== JSON.stringify(state.ui))
                state.data = updated;
        }
        onErrorChanged: if (error) state.act("notice", {text: error})
    }
    property MailDraftSync draftSync: MailDraftSync {
        client: state.mailboxClient
        undoSeconds: state.settings.undoSeconds
        onFailed: message => state.act("notice", {text: message})
    }
    readonly property var savedDraftIds: draftSync.savedDraftIds
    readonly property bool draftSaving: draftSync.saving
    function applySearchResults(messages, complete) {
        const hits = Store.mailboxRows(data.accounts, messages);
        const next = Store.replaceSearchRows(data, hits, data.ui.query, complete);
        next.search = Object.assign({}, next.search, {filter: data.ui.searchFilter || "All mail"});
        data = next;
    }

    property MailSearchQuery searchQuery: MailSearchQuery {
        client: state.mailboxClient
        active: state.ui.searching
        term: state.ui.query
        filter: state.ui.searchFilter || "All mail"
        retainedFilter: state.data.search?.filter || "All mail"
        retainedTerm: state.data.search?.complete === false ? null : state.data.search?.query ?? null
        onPartial: messages => state.applySearchResults(messages, false)
        onCompleted: (messages, ok) => {
            if (!ok) return;
            state.applySearchResults(messages, true);
        }
    }
    readonly property bool hasGmailCategories: data.accounts.some(account =>
        (ui.account === "All accounts" || account.id === ui.account) && account.categoryProvider === "gmail")
    function categoryFor(snapshot) {
        return snapshot.ui.folder === "Inbox" && snapshot.accounts.some(account =>
            (snapshot.ui.account === "All accounts" || account.id === snapshot.ui.account) && account.categoryProvider === "gmail")
            ? snapshot.ui.gmailCategory || "CATEGORY_PERSONAL" : "";
    }
    function projectedRows(snapshot) {
        const category = categoryFor(snapshot);
        const key = Store.backendViewKey(snapshot.ui.folder, snapshot.ui.account, snapshot.ui.filter, snapshot.ui.sort, category);
        // A selected search result is not a complete mailbox or thread representative.
        if (!snapshot.ui.searching && Store.current(snapshot)?.backendAccount && snapshot.ui.folder === "Inbox"
                && snapshot.accounts.some(account => account.categoryProvider === "gmail")
                && !snapshot.backendViews?.[key]) return [];
        return queryRows(category === (snapshot.ui.gmailCategory || "") ? snapshot
            : Object.assign({}, snapshot, {ui: Object.assign({}, snapshot.ui, {gmailCategory: category})}));
    }
    readonly property string activeGmailCategory: categoryFor(data)
    property MailboxQuery folderQuery: MailboxQuery {
        client: state.mailboxClient
        account: state.ui.account === "All accounts" ? "" : state.ui.account
        selectedId: state.selectedRow?.backendAccount ? state.ui.selected : ""
        gmailCategory: state.activeGmailCategory
        filter: state.ui.filter
        sort: state.ui.sort
        folder: ["Inbox", "Archive", "Trash", "Spam", "Sent", "Starred"].includes(state.ui.folder)
            ? state.ui.folder : ""
        onErrorChanged: if (error && state.waitingForImportedInbox) state.finishFirstImport()
        onRefreshed: messages => {
            if (!folder)
                return;
            const fresh = Store.mailboxRows(state.data.accounts, messages);
            const updated = Store.replaceBackendView(state.data, fresh, Store.backendViewKey(folder, account, filter, sort, gmailCategory));
            const gmailAccounts = new Set(fresh.filter(row => row.gmail).map(row => row.backendAccount));
            if (updated.accounts.some(entry => gmailAccounts.has(entry.id) && entry.categoryProvider !== "gmail"))
                updated.accounts = updated.accounts.map(entry => gmailAccounts.has(entry.id)
                    ? Object.assign({}, entry, {categoryProvider: "gmail"}) : entry);
            if (!updated.ui.selected && fresh.length && updated.ui.view === "read")
                updated.ui = Object.assign({}, updated.ui, {selected: fresh[0].id});
            if (updated.ui.selected && !Store.find(updated, updated.ui.selected))
                updated.ui = Object.assign({}, updated.ui, {selected: fresh[0]?.id ?? ""});
            updated.drafts = updated.drafts.map(draft => {
                if (draft.conversation || !draft.backendConversation)
                    return draft;
                const source = Store.mailboxMessages(updated).find(row => row.backendConversation === draft.backendConversation
                    && Store.accountKey(row) === Store.accountKey(draft) && row.folder !== "Sent");
                return source ? Object.assign({}, draft, {conversation: source.id, mode: "Reply"}) : draft;
            });
            updated.ui = Object.assign({}, updated.ui);
            Store.showReplyDraft(updated);
            state.data = updated;
            if (state.waitingForImportedInbox && !loading)
                state.finishFirstImport();
        }
    }
    property var rows: []
    property bool editingDraftState: false
    property var projections: ({mailbox: {}, search: {}})
    onDataChanged: {
        if (editingDraftState && ui.folder !== "Drafts" && !ui.searching)
            return;
        const searching = data.ui.searching;
        const kind = searching ? "search" : "mailbox";
        const source = searching && data.search ? Store.searchMessages(data) : Store.mailboxMessages(data);
        const scope = searching ? data.ui.query + "\u001f" + (data.ui.searchFilter || "All mail")
            : Store.backendViewKey(data.ui.folder, data.ui.account, data.ui.filter, data.ui.sort, categoryFor(data));
        const view = searching ? data.search?.query : data.backendViews?.[scope];
        const cached = projections[kind];
        let next = cached.rows;
        if (cached.source !== source || cached.drafts !== data.drafts || cached.scope !== scope || cached.view !== view) {
            next = projectedRows(data);
            projections = Object.assign({}, projections, {[kind]: {source, drafts: data.drafts, scope, view, rows: next}});
        }
        if (next.length !== rows.length || next.some((row, index) => row !== rows[index]))
            rows = next;
    }
    readonly property var settings: Object.assign({}, data.settings, {
        bodyInk: reader.bodyInk,
        htmlBackground: reader.htmlBackground
    })
    readonly property var accounts: data.accounts
    readonly property int signedInAccountCount: accounts.filter(account =>
        !["offline-imap", "stopping-imap", "removing-imap"].includes(account.provider)).length
    readonly property bool canSend: !draftSync.sendingId && Store.canSend(draft)
    readonly property bool hasPending: mailboxClient ? Object.keys(outbox).length > 0 : data.jobs.length > 0
    readonly property var undoJob: Object.values(outbox).reverse().find(job =>
        job.state === "queued" && job.undo_until > Date.now())
    readonly property bool undoAvailable: mailboxClient ? !!undoJob
        : hasPending && (data.now <= data.jobs[data.jobs.length - 1].expires || !ui.online)
    // These are requests to the future system integration, not app-owned surfaces.
    signal authorizationRequested(string provider)
    signal notificationRequested(var message)
    signal sendStatusChanged(var status)
    function completeAuthorization(email){act("providerEmail",{text:email});act("connect");}
    function notificationAction(action){
        if(action==="markRead")act("readNotification");
        else if(action==="dismiss")act("dismissNotification");
        else act("openNotification",{reply:action==="reply",agent:action==="agentReply"});
    }
    signal editorRequested()
    signal saveRequested(var file)
    property Connections attachmentResponses: Connections {
        target: state.mailboxClient
        ignoreUnknownSignals: true
        function onAttachmentFetched(messageId, attachmentId, localUrl) {
            const file = state.ui.attachment;
            if (file?.messageId !== messageId || file.id !== attachmentId)
                return;
            if (String(localUrl))
                state.act("preview", {file: Object.assign({}, file, {url: String(localUrl)})});
            else
                state.act("notice", {text: qsTr("Could not load the attachment.")});
        }
        function onAttachmentSaved(messageId, attachmentId, ok) {
            state.act("notice", {text: ok ? qsTr("Attachment saved.") : qsTr("Could not save the attachment.")});
        }
    }
    function saveAttachment(file){saveRequested(file);}
    function act(action, payload) {
        var p=payload || {};
        if (action === "sort") p = Object.assign({}, p, {value: "Newest first"});
        if (action === "filter" && p.value === "All") p = Object.assign({}, p, {value: "All mail"});
        if (mailboxClient && selected?.backendAccount) {
            const target = action === "archive" ? "Archive" : action === "trashConversation" ? "Trash"
                : action === "move" ? p.folder : "";
            const reported = syncStatusByAccount[selected.backendAccount]?.folders;
            if (["Archive", "Trash", "Spam", "Sent"].includes(target) && reported?.Inbox && !reported[target]) {
                act("notice", {text: qsTr("This folder is not assigned. Choose a server folder in Settings.")});
                return;
            }
        }
        if(action==="draft") {var d=Store.draft(data);if(d&&Object.keys(p).every(function(k){return d[k]===p[k];}))return;}
        if (action === "setting" && ["htmlBackground", "bodyInk"].includes(p.key)) {
            reader.setPreference(p.key, p.value);
            return;
        }
        if(action==="setting"&&data.settings[p.key]===p.value)return;
        if (mailboxClient && selected?.folder === "Trash" && ["restoreTrash", "deleteTrash"].includes(action)) {
            if (action === "restoreTrash")
                mailboxClient.restoreTrashedThread(selected.id);
            else {
                reader.invalidate([selected.id]);
                mailboxClient.deleteTrashedMessage(selected.id);
            }
            return;
        }
        if (mailboxClient && action === "deleteFolderThread" && ["Trash", "Spam"].includes(selected?.folder)) {
            reader.invalidate([selected.id].concat(p.ids ?? []));
            mailboxClient.deleteFolderThread(selected.id, p.ids, selected.folder === "Spam");
            return;
        }
        if (mailboxClient && action === "trashConversation") {
            if (!conversationTrashBusy && selected?.backendConversation) {
                conversationTrashBusy = true;
                mailboxClient.trashConversation(selected.backendAccount, selected.backendConversation);
            }
            return;
        }
        if (mailboxClient && action === "undo" && conversationUndoToken) {
            if (!conversationTrashBusy) {
                conversationTrashBusy = true;
                mailboxClient.undoConversationTrash(conversationUndoToken);
            }
            return;
        }
        if (mailboxClient && (action === "undoSend" || action === "undo" && undoJob)) {
            if (undoJob && undoJob.undo_until > Date.now())
                mailboxClient.undoSend(undoJob.id);
            return;
        }
        if (mailboxClient && action === "undo" && ui.undo) {
            const original = ui.undo.records[ui.undo.selected];
            const current = original && Store.find(data, original.id);
            if (original && current && original.folder !== current.folder)
                mailboxClient.updateMessage(original.id, {mailbox: original.folder});
            const removed = ui.undo.drafts.find(item => !data.drafts.some(draft => draft.id === item.id));
            const id = removed && (savedDraftIds[removed.id] || removed.backendId);
            if (id)
                mailboxClient.updateMessage(id, {mailbox: "Drafts"});
        }
        if (mailboxClient && action === "retry") {
            for (const job of Object.values(outbox)) {
                if (job.state === "failed" || job.state === "uncertain")
                    mailboxClient.retrySend(job.id);
            }
            return;
        }
        if (mailboxClient && action === "send") {
            if (!draft || draftSync.sendingId)
                return;
            const latest = Object.assign({}, draft, p);
            if (!Store.canSend(latest))
                return;
            draftSync.send(latest, latest.backendConversation || Store.find(data, latest.conversation)?.backendConversation || "");
            return;
        }
        if (mailboxClient && action === "discard" && draft)
            draftSync.discard(draft);
        if (mailboxClient && selected) {
            const current = selected;
            if (action === "archive")
                mailboxClient.updateMessage(current.id, {mailbox: "Archive"});
            else if (action === "move")
                mailboxClient.updateMessage(current.id, {mailbox: p.folder});
            else if (action === "unread")
                mailboxClient.updateMessage(current.id, {unread: !current.unread});
            else if (action === "star")
                mailboxClient.updateMessage(current.id, {flagged: !current.starred});
            else if (action === "select") {
                const row = Store.find(data, p.id);
                if (row?.unread)
                    mailboxClient.updateMessage(row.id, {unread: false});
            }
        }
        if (mailboxClient && action === "preview" && p.file?.messageId && !p.file.url)
            mailboxClient.fetchAttachment(p.file.messageId, p.file.id, p.file.name);
        if (mailboxClient && action === "setting" && p.key === "pictures") {
            const policies = {"Ask first": "ask_first", Always: "always", Never: "never"};
            mailboxClient.imagePolicy("", policies[p.value], ++globalImageRevision);
            return;
        }
        if (action === "draft") {
            const updated = Store.editDraft(data, p);
            if (updated === data)
                return;
            editingDraftState = true;
            data = updated;
            editingDraftState = false;
            if (mailboxClient) {
                const changed = Store.draft(updated);
                draftSync.enqueue(changed, changed.backendConversation
                    || Store.find(updated, changed.conversation)?.backendConversation || "", false);
            }
            return;
        }
        const navigation = ["search", "closeSearch", "select", "escape"].includes(action);
        const previousJobs = navigation || !data.jobs.length ? null : JSON.stringify(data.jobs);
        p.now=Date.now();var next=reduceAction(data,action,p,projectedRows);
        const jobsChanged = !navigation && (previousJobs === null
            ? next.jobs.length > 0 : JSON.stringify(next.jobs) !== previousJobs);
        // Sending/Undo is reported to the system, not duplicated as an app toast.
        if(jobsChanged&&["send","tick","undoSend","retry"].includes(action))next.ui.notice="";
        data=next;

        if (mailboxClient && ["new", "reply", "mode", "attach", "detach", "keepDraft"].includes(action)) {
            const changed = Store.draft(next);
            if (changed)
                draftSync.enqueue(changed, changed.backendConversation || Store.find(next, changed.conversation)?.backendConversation || "",
                    ["attach", "detach", "keepDraft"].includes(action));
        }
        if(action==="provider")authorizationRequested(ui.provider);
        if(action==="notify"&&ui.notification)notificationRequested(Store.find(data,"anna-notification"));
        if(jobsChanged)sendStatusChanged({pending:Store.copy(data.jobs),undoAvailable:undoAvailable});
    }
    property MailboxQuery railQuery: MailboxQuery {
        client: state.folderQuery.displayedKey || state.folderQuery.initialLoadFinished
            ? state.mailboxClient : null
        allFolders: true
    }
    function count(folder, account, unreadOnly = true) {
        if (!mailboxClient || folder === "Drafts" || !railQuery.displayedKey)
            return Store.folderCount(data, folder, account, unreadOnly);
        return railQuery.messages.reduce((total, entry) => total + (entry.mailbox === folder
            && (account === "All accounts" || entry.account_id === account) ? (unreadOnly ? entry.unread : entry.total) : 0), 0);
    }
    function highlight(text, ink, background){return Store.highlight(String(text),ui.searching?ui.query:"",ink,background);}
    function names(addresses){return String(addresses).split(",").map(function(a){return a.trim().split("@")[0].split(/[._]/).map(function(s){return s?s[0].toUpperCase()+s.slice(1):s;}).join(" ");}).join(", ");}
    function addressesValid(value){return Store.validRecipients(value);}
    function agentDraft(id) { return Store.agentDraft(data,id); }
    function reply(mode, agent, sourceId) {
        act("reply", {mode: mode, agent: !!agent, sourceId: sourceId});
        editorRequested();
    }
    property Timer clock: Timer { interval: 500; repeat: true; running: (!state.mailboxClient && state.hasPending) || state.ui.view === "importing"; onTriggered: state.act("tick") }
    Component.onCompleted: {
        const now = Date.now();
        data = Object.assign({}, data, {now, jobs: data.jobs.map(job =>
            Object.assign({}, job, {expires: now + data.settings.undoSeconds * 1000}))});
        rows = projectedRows(data);
    }
}
