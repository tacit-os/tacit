import QtQuick

MailQueryState {
    id: query

    property var client
    property string account
    property string folder
    property bool allFolders: false
    property string selectedId: ""
    property string filter: "All mail"
    property string gmailCategory: ""
    property string sort: "Newest first"
    property string displayedKey: ""
    readonly property string key: client && (folder || allFolders) ? JSON.stringify([account, folder, filter, sort, gmailCategory]) : ""
    onKeyChanged: if (key) refresh()
    property var messages: []
    property bool initialLoadFinished: false

    signal refreshed(var messages)

    function refresh() {
        if (!client?.enabled || (!folder && !allFolders))
            return;
        if (!beginRequest(key, allFolders ? -1 : 1))
            return;
        if (allFolders)
            client.loadMailboxCounts(revision);
        else
            client.loadMailboxView(account, folder, filter, sort, revision, selectedId, gmailCategory);
    }

    property Connections responses: Connections {
        target: query.client
        function onMailboxFirstPage(revision, messages) {
            if (query.allFolders || !query.acceptsResponse(query.key, revision) || query.displayedKey === query.key || !messages.length)
                return;
            query.displayedKey = query.key;
            query.messages = messages;
            query.refreshed(messages);
        }
        function onMailboxLoaded(revision, messages, ok) {
            if (!query.acceptsResponse(query.key, revision, true))
                return;
            const refreshPending = query.finishRequest(ok, qsTr("Could not load the local mailbox."));
            if (ok) {
                query.displayedKey = query.key;
                query.messages = messages;
                query.refreshed(messages);
            }
            query.initialLoadFinished = true;
            if (refreshPending && !query.loading)
                query.refresh();
        }
        function onFailed() {
            if (!query.loading) return;
            query.loading = false;
            query.error = qsTr("Could not load the local mailbox.");
        }
    }
}
