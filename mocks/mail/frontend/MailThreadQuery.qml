import QtQuick

QtObject {
    id: query

    property var client
    property string account
    property string conversation
    readonly property string key: client && account && conversation
        ? JSON.stringify([account, conversation]) : ""
    property var prefetchRows: []
    property var recentKeys: []
    property int nextTicket: 0
    property int waitingTicket: 0
    property int activePrefetchTicket: 0
    property int cacheGeneration: 0
    property var prefetched: new Map()
    property var pending: new Map()
    property var attempted: new Set()
    property int revision: 0
    property var messages: []
    property bool loading: false
    property string sourceSnapshot: ""
    property string error: ""

    onKeyChanged: {
        if (key) recentKeys = [key].concat(recentKeys.filter(entry => entry !== key)).slice(0, 3);
        messages = [];
        sourceSnapshot = "";
        ++revision;
        error = "";
        loading = key !== "";
        waitingTicket = 0;
        activePrefetchTicket = 0;
        if (prefetched.has(key)) {
            usePrefetched(prefetched.get(key));
        } else if (loading) {
            const inFlight = Array.from(pending.entries()).find(([, entry]) =>
                entry.key === key && entry.generation === cacheGeneration);
            if (inFlight)
                waitingTicket = inFlight[0];
            else
                client.loadThread(account, conversation, revision);
        }
        schedulePrefetch();
    }

    onPrefetchRowsChanged: schedulePrefetch()
    onClientChanged: {
        pending.clear();
        resetPrefetch(false);
    }

    function resetPrefetch(preserveRecent = false) {
        ++cacheGeneration;
        for (const [candidate, cached] of prefetched) {
            if (preserveRecent && recentKeys.includes(candidate))
                prefetched.set(candidate, {messages: cached.messages, ticket: 0, revalidate: true});
            else
                prefetched.delete(candidate);
        }
        attempted.clear();
        schedulePrefetch();
    }

    function usePrefetched(cached) {
        activePrefetchTicket = cached.ticket;
        messages = cached.messages;
        sourceSnapshot = JSON.stringify(cached.messages);
        loading = false;
        if (cached.revalidate)
            client.loadThread(account, conversation, revision);
    }

    function schedulePrefetch() {
        if (client?.enabled && !prefetchTimer.running)
            prefetchTimer.start();
    }

    property Timer prefetchTimer: Timer {
        interval: 80
        onTriggered: query.prefetch()
    }

    function prefetch() {
        const candidates = new Map();
        for (const row of prefetchRows) {
            if (!row.backendAccount || !row.backendConversation)
                continue;
            const candidate = JSON.stringify([row.backendAccount, row.backendConversation]);
            candidates.set(candidate, [row.backendAccount, row.backendConversation]);
        }
        for (const candidate of prefetched.keys()) {
            if (!candidates.has(candidate) && !recentKeys.includes(candidate)) prefetched.delete(candidate);
        }
        for (const candidate of attempted) {
            if (!candidates.has(candidate) && !recentKeys.includes(candidate)) {
                attempted.delete(candidate);
                prefetched.delete(candidate);
            }
        }
        for (const [candidate, scope] of candidates) {
            if (pending.size >= 2)
                break;
            if (candidate === key || attempted.has(candidate)
                    || Array.from(pending.values()).some(entry => entry.key === candidate))
                continue;
            const ticket = ++nextTicket;
            attempted.add(candidate);
            pending.set(ticket, {key: candidate, generation: cacheGeneration});
            client.prefetchThread(scope[0], scope[1], ticket);
        }
    }

    function refresh() {
        waitingTicket = 0;
        activePrefetchTicket = 0;
        ++revision;
        error = "";
        loading = key !== "" && messages.length === 0;
        if (key)
            client.loadThread(account, conversation, revision);
    }

    function setMessages(updated) {
        if (JSON.stringify(updated) !== JSON.stringify(messages))
            messages = updated;
        if (key && updated.length)
            prefetched.set(key, {messages: updated, ticket: 0});
    }

    property Connections responses: Connections {
        target: query.client
        function onThreadPrefetched(ticket, messages, ok) {
            const entry = query.pending.get(ticket);
            if (!entry)
                return;
            if (!ok)
                query.pending.delete(ticket);
            if (entry.generation === query.cacheGeneration && query.attempted.has(entry.key) && ok)
                query.prefetched.set(entry.key, {messages, ticket});
            if (ticket === query.waitingTicket) {
                query.waitingTicket = 0;
                if (query.prefetched.has(entry.key))
                    query.usePrefetched(query.prefetched.get(entry.key));
                else
                    query.refresh();
            }
            query.schedulePrefetch();
        }
        function onThreadPrefetchImagesLoaded(ticket, messages) {
            const entry = query.pending.get(ticket);
            if (!entry)
                return;
            query.pending.delete(ticket);
            const cached = query.prefetched.get(entry.key);
            if (entry.generation === query.cacheGeneration && cached?.ticket === ticket) {
                query.prefetched.set(entry.key, {messages, ticket: 0});
            }
            if (ticket === query.activePrefetchTicket) {
                query.activePrefetchTicket = 0;
                query.setMessages(messages);
            }
            query.schedulePrefetch();
        }
        function onThreadMessageLoaded(revision, message) {
            if (revision !== query.revision)
                return;
            query.setMessages(query.messages.map(entry => entry.id === message.id ? message : entry));
        }
        function onThreadLoaded(revision, messages, ok) {
            if (revision !== query.revision)
                return;
            if (ok) {
                const snapshot = JSON.stringify(messages);
                if (snapshot !== query.sourceSnapshot) {
                    query.sourceSnapshot = snapshot;
                    const merged = messages.map(message => {
                        const previous = query.messages.find(entry => entry.id === message.id);
                        if (!previous)
                            return message;
                        const files = (message.attachments ?? []).map(file => {
                            const local = (previous.attachments ?? []).find(entry => entry.id === file.id
                                && entry.size === file.size && entry.media_type === file.media_type);
                            return local?.inlineSource ? Object.assign({}, file,
                                {inline: true, inlineSource: local.inlineSource}) : file;
                        });
                        // Retain locally resolved CID images when only flags or metadata changed.
                        let html = message.body_html ?? "";
                        return Object.assign({}, message, {body_html: html, attachments: files});
                    });
                    query.setMessages(merged);
                }
            } else
                query.error = qsTr("Could not load the conversation.");
            query.loading = false;
        }
    }
}
