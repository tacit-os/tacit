import QtQuick
import "mail-store.js" as Store

QtObject {
    id: state
    property color agentInk
    property var reduceAction: Store.reduce
    property var data: Store.emptyMailbox()
    onMailboxClientChanged: if (mailboxClient) mailboxClient.loadAccounts()
    readonly property var ui: data.ui
    readonly property var selectedRow: Store.current(data)
    property MailThreadQuery threadQuery: MailThreadQuery {
        client: state.mailboxClient
        account: state.selectedRow?.backendAccount ?? ""
        conversation: state.selectedRow?.backendConversation ?? ""
    }
    readonly property var threadMessages: Store.fromMailbox(data, threadQuery.messages).messages

    readonly property var selected: {
        if (!selectedRow || !threadMessages.length)
            return selectedRow;
        const current = threadMessages.find(message => message.id === selectedRow.id);
        if (!current)
            return selectedRow;
        return Object.assign({}, selectedRow, {
            bodyHtml: current.bodyHtml,
            files: current.files,
            history: threadMessages.filter(message => message.id !== current.id).map(message =>
                Object.assign({}, message, {date: [message.day, message.time].join(" "), expanded: false}))
        });
    }
    readonly property bool canReplyAll: Store.canReplyAll(selected, accounts)
    readonly property var draft: Store.draft(data)
    property var mailboxClient: null
    property string conversationUndoToken: ""
    property bool conversationTrashBusy: false
    property var outbox: ({})
    property Connections outboxResponses: Connections {
        target: state.mailboxClient
        ignoreUnknownSignals: true
        function onAccountsLoaded(accounts, ok) {
            if (!ok)
                return;
            state.data = Object.assign({}, state.data, {
                accounts: accounts.map(account => ({
                    id: account.id,
                    name: account.id === "work" ? "Work" : account.id === "personal" ? "Personal" : account.name,
                    email: account.email,
                    provider: account.provider
                }))
            });
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
        function onMessageUpdated(id, ok) {
            if (ok) {
                state.railQuery.refresh();
                state.draftQuery.refresh();
                if (state.folderQuery.key)
                    state.folderQuery.refresh();
                state.threadQuery.refresh();
            } else {
                state.act("notice", {text: qsTr("Could not update the message.")});
            }
        }
        function onMailboxInvalidated() {
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
            const loaded = Store.fromMailbox(state.data, messages, state.data.messages).drafts;
            const working = state.data.drafts.filter(draft =>
                !draft.backendId || draft.id === state.ui.draftId && ["draft", "compose"].includes(state.ui.view));
            const represented = new Set(working.map(draft => state.savedDraftIds[draft.id] || draft.backendId));
            const updated = Object.assign({}, state.data, {
                ui: Object.assign({}, state.ui),
                drafts: working.concat(loaded.filter(draft => !represented.has(draft.id)))
            });
            Store.showReplyDraft(updated);
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
    property MailSearchQuery searchQuery: MailSearchQuery {
        client: state.mailboxClient
        active: state.ui.searching && folder !== "Drafts"
        account: state.ui.account === "Work" ? "work" : state.ui.account === "Personal" ? "personal" : ""
        folder: state.ui.folder
        term: state.ui.query
        onCompleted: (messages, ok) => {
            if (!ok) {
                state.act("notice", {text: qsTr("Could not search the local mailbox.")});
                return;
            }
            const updated = Object.assign({}, state.data);
            const hits = Store.fromMailbox(updated, messages).messages;
            const hitIds = new Set(hits.map(message => message.id));
            updated.messages = updated.messages.filter(message => !hitIds.has(message.id)).concat(hits);
            updated.searchIds = hits.map(message => message.id);
            state.data = updated;
        }
    }
    property MailboxQuery folderQuery: MailboxQuery {
        client: state.mailboxClient
        account: state.ui.account === "Work" ? "work" : state.ui.account === "Personal" ? "personal" : ""
        folder: ["Inbox", "Archive", "Trash", "Spam", "Sent"].includes(state.ui.folder)
            && !state.ui.searching ? state.ui.folder : ""
        onRefreshed: messages => {
            if (!folder)
                return;
            const updated = Object.assign({}, state.data);
            const fresh = Store.fromMailbox(updated, messages).messages;
            updated.messages = updated.messages.filter(row => row.folder !== folder
                || account && row.backendAccount !== account).concat(fresh);
            if (!updated.ui.selected && fresh.length && updated.ui.view === "read")
                updated.ui = Object.assign({}, updated.ui, {selected: fresh[0].id});
            if (updated.ui.selected && !updated.messages.some(row => row.id === updated.ui.selected))
                updated.ui = Object.assign({}, updated.ui, {selected: fresh[0]?.id ?? ""});
            updated.drafts = updated.drafts.map(draft => {
                if (draft.conversation || !draft.backendConversation)
                    return draft;
                const source = updated.messages.find(row => row.backendConversation === draft.backendConversation
                    && row.account === draft.account && row.folder !== "Sent");
                return source ? Object.assign({}, draft, {conversation: source.id, mode: "Reply"}) : draft;
            });
            updated.ui = Object.assign({}, updated.ui);
            Store.showReplyDraft(updated);
            state.data = updated;
        }
    }
    property var rows: []
    onDataChanged: {var next=Store.results(data);if(JSON.stringify(next)!==JSON.stringify(rows))rows=next;}
    readonly property var settings: data.settings
    readonly property var accounts: data.accounts
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
        if(action==="draft") {var d=Store.draft(data);if(d&&Object.keys(p).every(function(k){return d[k]===p[k];}))return;}
        if(action==="setting"&&data.settings[p.key]===p.value)return;
        if (mailboxClient && selected?.folder === "Trash" && ["restoreTrash", "deleteTrash"].includes(action)) {
            if (action === "restoreTrash")
                mailboxClient.restoreTrashedThread(selected.id);
            else
                mailboxClient.deleteTrashedMessage(selected.id);
            return;
        }
        if (mailboxClient && action === "deleteFolderThread" && ["Trash", "Spam"].includes(selected?.folder)) {
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
            const original = ui.undo.messages.find(row => row.id === ui.undo.selected);
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
        const previousJobs=JSON.stringify(data.jobs);
        p.now=Date.now();var next=reduceAction(data,action,p);
        const jobsChanged=JSON.stringify(next.jobs)!==previousJobs;
        // Sending/Undo is reported to the system, not duplicated as an app toast.
        if(jobsChanged&&["send","tick","undoSend","retry"].includes(action))next.ui.notice="";
        if (mailboxClient && (next.ui.searching !== ui.searching || next.ui.query !== ui.query))
            next.searchIds = [];
        data=next;
        if (mailboxClient && ["new", "reply", "mode", "draft", "attach", "detach", "keepDraft"].includes(action)) {
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
        client: state.mailboxClient
        allFolders: true
    }
    readonly property var railMessages: Store.fromMailbox(data, railQuery.messages).messages
    function count(folder, account) {
        const snapshot = mailboxClient && folder !== "Drafts"
            ? {messages: railMessages, drafts: data.drafts, ui: data.ui} : data;
        return Store.folderCount(snapshot, folder, account);
    }
    function resultSnippet(message) {
        const body = message.body.replace(/\s+/g, " ");
        const query = ui.searching ? ui.query.trim().toLowerCase() : "";
        if (!query)
            return body;
        const match = body.toLowerCase().indexOf(query);
        if (match >= 0)
            return (match ? "… " : "") + body.slice(match);
        return message.files.find(file => file.name.toLowerCase().includes(query))?.name
            ?? (message.address?.toLowerCase().includes(query) ? message.address : body);
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
        var next=Store.copy(data);next.now=Date.now();next.jobs.forEach(function(j){j.expires=next.now+next.settings.undoSeconds*1000;});data=next;rows=Store.results(data);
    }
}
