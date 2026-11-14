import QtQuick

QtObject {
    id: query

    property var client
    property string account
    property string conversation
    readonly property string key: client && account && conversation
        ? JSON.stringify([account, conversation]) : ""
    property int revision: 0
    property var messages: []
    property bool loading: false
    property string error: ""

    onKeyChanged: {
        messages = [];
        refresh();
    }

    function refresh() {
        ++revision;
        error = "";
        loading = key !== "";
        if (loading)
            client.loadThread(account, conversation, revision);
    }

    property Connections responses: Connections {
        target: query.client
        function onThreadLoaded(revision, messages, ok) {
            if (revision !== query.revision)
                return;
            query.loading = false;
            if (ok)
                query.messages = messages;
            else
                query.error = qsTr("Could not load the conversation.");
        }
    }
}
