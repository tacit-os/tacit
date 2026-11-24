import QtQuick

MailQueryState {
    id: query

    property var client
    property string term
    property bool active: false
    property string filter: "All mail"
    readonly property string requestKey: client && active ? "search:" + term + (filter === "All mail" ? "" : "\u001f" + filter) : ""
    property var retainedTerm: null
    property string retainedFilter: "All mail"
    signal partial(var messages)
    signal completed(var messages, bool ok)

    onRequestKeyChanged: {
        delay.stop();
        invalidateRequest(requestKey, requestKey !== "" && (retainedTerm !== term || retainedFilter !== filter));
        if (loading)
            delay.restart();
    }

    function refresh() {
        if (!requestKey)
            return;
        if (!beginRequest(requestKey))
            return;
        client.search(term, revision, filter);
    }

    property Timer delay: Timer {
        interval: 50
        onTriggered: query.client.search(query.term, query.revision, query.filter)
    }

    property Connections responses: Connections {
        target: query.client
        ignoreUnknownSignals: true
        function onSearchFirstPage(revision, messages) {
            if (query.acceptsResponse(query.requestKey, revision))
                query.partial(messages);
        }
        function onSearched(revision, messages, ok) {
            if (!query.acceptsResponse(query.requestKey, revision))
                return;
            const refreshPending = query.finishRequest(ok, qsTr("Could not search your mail."));
            query.completed(messages, ok);
            if (refreshPending && !query.loading)
                query.refresh();
        }
    }
}
