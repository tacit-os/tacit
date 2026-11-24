import QtQuick

QtObject {
    id: query

    property var client
    property int revision: 0
    property bool loading: false
    property string error: ""
    signal refreshed(var messages)

    function refresh() {
        if (!client)
            return;
        loading = true;
        error = "";
        client.loadDrafts("", ++revision);
    }

    property Connections responses: Connections {
        target: query.client
        function onDraftsLoaded(revision, messages, ok) {
            if (revision !== query.revision)
                return;
            query.loading = false;
            if (ok)
                query.refreshed(messages);
            else
                query.error = qsTr("Could not load saved drafts.");
        }
    }
}
