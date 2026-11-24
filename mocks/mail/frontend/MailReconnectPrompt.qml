import QtQuick
import Tacit.Kit as K

Column {
    id: panel
    required property var client
    required property var account
    signal closed()
    property bool waiting: false
    property string error: ""
    spacing: K.Kit.tokens.space.s

    function reconnect() {
        if (waiting || !password.text)
            return;
        waiting = true;
        error = "";
        client.reconnectInternetAccount(account.id, password.text);
        password.text = "";
    }

    Connections {
        target: panel.client
        function onInternetAccountReconnected(account, ok, error) {
            if (account !== panel.account.id)
                return;
            panel.waiting = false;
            if (ok) {
                panel.closed();
                return;
            }
            panel.error = error === "credential_store_failed"
                ? qsTr("Could not update the saved password. Check your system keychain.")
                : qsTr("Could not reconnect. Check the new app password and try again.");
            password.focusIn();
        }
    }

    K.TacitText {
        width: panel.width
        wrapMode: Text.Wrap
        text: qsTr("Enter a new app password for %1. Mail and drafts on this computer will be kept.").arg(panel.account.email)
    }
    K.Field {
        id: password
        width: panel.width
        hint: qsTr("New app password")
        input.echoMode: TextInput.Password
        input.inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
        enabled: !panel.waiting
        onAccepted: panel.reconnect()
    }
    K.TacitText {
        width: panel.width
        visible: !!panel.error
        text: panel.error
        wrapMode: Text.Wrap
        ink: "risk"
    }
    K.Slab {
        tone: "default"
        text: panel.waiting ? qsTr("Checking your connection…") : qsTr("Reconnect")
        waiting: panel.waiting || !password.text
        onActivated: panel.reconnect()
    }
    MailAction {
        enabled: !panel.waiting
        text: qsTr("Cancel")
        onActivated: panel.closed()
    }
}
