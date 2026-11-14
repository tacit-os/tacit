import QtQuick
import "mail-store.js" as Store

QtObject {
    id: sync

    property int undoSeconds: 10
    property var client
    property var savedDraftIds: ({})
    property var pending: ({})
    property string activeId: ""
    property string sendingId: ""
    property string submittingId: ""
    property bool discardActive: false
    readonly property bool saving: activeId !== "" || Object.keys(pending).length > 0
    signal failed(string message)

    function enqueue(draft, conversation, immediate) {
        if (!client)
            return;
        pending = Object.assign({}, pending, {
            [draft.id]: {draft, conversation, readyAt: Date.now() + (immediate ? 0 : 400)}
        });
        flush();
    }

    function send(draft, conversation) {
        if (!client || sendingId || !Store.canSend(draft))
            return;
        sendingId = draft.id;
        enqueue(draft, conversation, true);
    }

    function discard(draft) {
        if (!client || submittingId && sendingId === draft.id)
            return;
        removePending(draft.id);
        if (sendingId === draft.id)
            sendingId = "";
        if (activeId === draft.id) {
            discardActive = true;
        } else {
            const remoteId = savedDraftIds[draft.id] || draft.backendId;
            if (remoteId)
                client.updateMessage(remoteId, {mailbox: "Trash"});
        }
        flush();
    }

    function removePending(id) {
        const updated = Object.assign({}, pending);
        delete updated[id];
        pending = updated;
    }

    function flush() {
        delay.stop();
        if (activeId || !client)
            return;
        const ids = Object.keys(pending).sort((a, b) => pending[a].readyAt - pending[b].readyAt);
        if (!ids.length)
            return;
        const id = ids[0];
        const item = pending[id];
        const remaining = item.readyAt - Date.now();
        if (remaining > 0) {
            delay.interval = remaining;
            delay.start();
            return;
        }

        activeId = id;
        removePending(id);
        const draft = item.draft;
        const addresses = value => String(value || "").split(/[,;]/)
            .map(email => email.trim()).filter(email => Store.validRecipients(email))
            .map(email => ({email}));
        let html = draft.bodyHtml || "";
        const files = draft.files.filter(file => !file.inline
            || (file.inlineSource && html.includes(file.inlineSource))
            || html.includes('href="tacit-attachment:' + file.id + '"'));
        for (const file of files) {
            if (file.backendId && file.inlineSource)
                html = html.split(file.inlineSource).join("cid:" + file.backendId);
        }
        client.saveDraft(id, savedDraftIds[id] || draft.backendId || "", {
            account_id: draft.account === "Work" ? "work" : "personal",
            conversation_id: item.conversation,
            reply_source_id: draft.mode === "Forward" ? "" : draft.sourceId || draft.conversation || "",
            to: addresses(draft.to),
            cc: addresses(draft.cc),
            bcc: addresses(draft.bcc),
            subject: draft.subject,
            body_text: draft.body,
            body_html: html,
            local_files: files.filter(file => !file.backendId && file.url),
            attachments: files.filter(file => file.backendId).map(file => ({id: file.backendId}))
        });
    }

    property Timer delay: Timer {
        onTriggered: sync.flush()
    }

    property Connections responses: Connections {
        target: sync.client

        function onDraftSaved(localId, remoteId) {
            if (localId !== sync.activeId)
                return;
            const discard = sync.discardActive;
            sync.discardActive = false;
            sync.activeId = "";
            if (remoteId)
                sync.savedDraftIds = Object.assign({}, sync.savedDraftIds, {[localId]: remoteId});
            if (discard) {
                if (remoteId)
                    sync.client.updateMessage(remoteId, {mailbox: "Trash"});
            } else if (!remoteId) {
                sync.failed(qsTr("Could not save the local draft."));
            }
            if (sync.sendingId === localId && !sync.pending[localId]) {
                if (remoteId) {
                    sync.submittingId = remoteId;
                    sync.client.sendDraft(remoteId, sync.undoSeconds);
                } else {
                    sync.sendingId = "";
                }
            }
            sync.flush();
        }

        function onOutboxChanged(job) {
            if (!sync.submittingId || job.message_id !== sync.submittingId)
                return;
            sync.submittingId = "";
            sync.sendingId = "";
        }

        function onSendRejected(draftId) {
            if (draftId !== sync.submittingId)
                return;
            sync.submittingId = "";
            sync.sendingId = "";
            sync.failed(qsTr("Could not queue the draft for sending."));
        }
    }
}
