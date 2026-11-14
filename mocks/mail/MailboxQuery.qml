import QtQuick

QtObject {
    id: query

    property var client
    property string account
    property string folder
    property bool allFolders: false
    property int revision: 0
    readonly property string key: client && (folder || allFolders) ? JSON.stringify([account, folder]) : ""
    onKeyChanged: if (key) refresh()
    property var messages: []
    property bool initialLoadFinished: false
    property bool loading: false
    property string error: ""

    signal refreshed(var messages)

    function refresh() {
        if (!client?.enabled || (!folder && !allFolders))
            return;
        error = "";
        loading = true;
        revision += allFolders ? -1 : 1;
        client.loadMailbox(account, folder, revision);
    }

    property Connections responses: Connections {
        target: query.client
        function onMailboxLoaded(revision, messages, ok) {
            if (!query.key || revision !== query.revision)
                return;
            query.loading = false;
            query.error = ok ? "" : qsTr("Could not load the local mailbox.");
            if (ok) {
                query.messages = messages;
                query.refreshed(messages);
            }
            query.initialLoadFinished = true;
        }
        function onFailed() {
            query.loading = false;
            query.error = qsTr("Could not load the local mailbox.");
        }
    }
}
