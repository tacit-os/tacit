import QtQuick

QtObject {
    id: request

    property int revision: 0
    property string requestedKey: ""
    property bool loading: false
    property bool refreshPending: false
    property string error: ""

    function invalidateRequest(key, shouldLoad) {
        ++revision;
        requestedKey = key;
        refreshPending = false;
        loading = shouldLoad;
        error = "";
    }

    // Coalesce repeated refresh signals into one follow-up request for this key.
    function beginRequest(key, revisionStep = 1) {
        if (loading && requestedKey === key) {
            refreshPending = true;
            return false;
        }
        requestedKey = key;
        refreshPending = false;
        error = "";
        loading = true;
        revision += revisionStep;
        return true;
    }

    function acceptsResponse(key, responseRevision, allowUnrequested = false) {
        return !!key && responseRevision === revision
            && (requestedKey === key || (allowUnrequested && !requestedKey));
    }

    function finishRequest(ok, message = "") {
        const pending = refreshPending;
        refreshPending = false;
        loading = false;
        error = ok ? "" : message;
        return pending;
    }
}
