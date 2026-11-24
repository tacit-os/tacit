import QtQuick
import Tacit.Kit as K

Column {
    id: panel
    required property var client
    required property string accountId
    signal closed()
    property var available: []
    property var assigned: ({})
    property var manual: ({})
    property bool loaded: false
    property bool busy: false
    property string error: ""
    spacing: K.Kit.tokens.space.s

    function requestFolders() {
        busy = true;
        error = "";
        client.loadAccountFolders(accountId);
    }

    Component.onCompleted: requestFolders()

    Connections {
        target: panel.client
        function onAccountFoldersLoaded(id, settings, ok) {
            if (id !== panel.accountId)
                return;
            panel.busy = false;
            if (ok) {
                panel.available = settings.available || [];
                panel.assigned = settings.assigned || {};
                panel.manual = settings.manual || {};
                panel.loaded = true;
            } else {
                panel.error = qsTr("Could not check folders at your mail provider.");
            }
        }
        function onAccountFoldersSaved(id, settings, ok) {
            if (id !== panel.accountId)
                return;
            panel.busy = false;
            if (ok)
                panel.closed();
            else
                panel.error = qsTr("Could not save folder choices. Each folder can only be used once.");
        }
    }

    K.TacitText {
        width: panel.width
        text: panel.error || (panel.busy ? qsTr("Contacting your mail provider…")
            : qsTr("Choose where Tacit should find these folders. Changes take effect on the next sync."))
        wrapMode: Text.Wrap
        ink: panel.error ? "risk" : "sec"
    }
    Repeater {
        model: panel.loaded ? [
            { key: "Archive", title: qsTr("Archive") },
            { key: "Spam", title: qsTr("Spam") },
            { key: "Sent", title: qsTr("Sent") },
            { key: "Trash", title: qsTr("Trash") }
        ] : []
        delegate: K.WordAction {
            id: role
            required property var modelData
            width: panel.width
            enabled: !panel.busy
            text: qsTr("%1 · %2").arg(modelData.title).arg(panel.assigned[modelData.key] ||
                (panel.manual[modelData.key] ? qsTr("Folder unavailable") : qsTr("Choose a folder")))
            onActivated: menu.openAt(role, 0, role.height)
            MailMenu {
                id: menu
                items: [{label: qsTr("Automatic")}].concat(panel.available.map(name => ({label: name})))
                onPicked: index => {
                    const changed = Object.assign({}, panel.manual);
                    if (index === 0)
                        delete changed[role.modelData.key];
                    else
                        changed[role.modelData.key] = panel.available[index - 1];
                    panel.manual = changed;
                    panel.assigned = Object.assign({}, panel.assigned,
                        {[role.modelData.key]: changed[role.modelData.key] || ""});
                }
            }
        }
    }
    MailAction {
        visible: panel.loaded
        enabled: !panel.busy
        text: qsTr("Save folder choices")
        onActivated: {
            panel.busy = true;
            panel.error = "";
            panel.client.saveAccountFolders(panel.accountId, panel.manual);
        }
    }
    MailAction {
        visible: !panel.loaded && !!panel.error
        enabled: !panel.busy
        text: qsTr("Try again")
        onActivated: panel.requestFolders()
    }
    MailAction {
        enabled: !panel.busy
        text: qsTr("Close")
        onActivated: panel.closed()
    }
}
