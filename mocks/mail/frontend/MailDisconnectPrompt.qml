import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Tacit.Kit as K

ColumnLayout {
    id: prompt
    required property var client
    required property var account
    signal closed()
    signal removalStarted(string accountId)
    property var summary: null
    property bool busy: false
    property string failure: ""
    property var lastChoice: null
    spacing: K.Kit.tokens.space.s

    function loadSummary() {
        failure = "";
        client.loadDisconnectSummary(account.id);
    }
    function submit(remove) {
        busy = true;
        failure = "";
        lastChoice = remove;
        if (remove)
            removalStarted(account.id);
        client.disconnectInternetAccount(account.id, remove);
    }

    Component.onCompleted: loadSummary()
    Connections {
        target: prompt.client
        function onDisconnectSummaryLoaded(id, info, ok) {
            if (id !== prompt.account.id)
                return;
            if (ok)
                prompt.summary = info;
            else
                prompt.failure = qsTr("Could not check for unsent mail.");
        }
        function onInternetAccountDisconnected(id, removed, ok) {
            if (id !== prompt.account.id)
                return;
            prompt.busy = false;
            if (ok)
                prompt.closed();
            else
                prompt.failure = qsTr("Could not finish. Try again.");
        }
    }

    K.TacitText {
        Layout.fillWidth: true
        weight: "strong"
        wrapMode: Text.Wrap
        text: prompt.account.provider === "offline-imap" || prompt.account.provider === "removing-imap"
            ? qsTr("Remove local mail for %1?").arg(prompt.account.email)
            : qsTr("Disconnect %1?").arg(prompt.account.email)
    }
    K.TacitText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: prompt.account.provider === "offline-imap" || prompt.account.provider === "removing-imap"
            ? qsTr("This removes the local copy. Mail at your provider will stay as it is.")
            : qsTr("Mail will stop syncing. Do you want to keep downloaded messages on this computer? Mail at your provider will stay as it is.")
    }
    K.TacitText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        ink: "sec"
        text: prompt.summary
            ? qsTr("Local drafts: %1. Waiting or failed sends: %2. Unconfirmed deliveries: %3.")
                .arg(prompt.summary.drafts).arg(prompt.summary.waiting).arg(prompt.summary.uncertain)
            : qsTr("Checking for unsent mail…")
    }
    K.TacitText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        ink: "sec"
        visible: !!prompt.summary && (prompt.summary.drafts > 0 || prompt.summary.waiting > 0 || prompt.summary.uncertain > 0)
        text: qsTr("If you keep mail, waiting and failed sends return to Drafts. If you remove mail, local drafts and outbox records are deleted too. Mail already handed to your provider can still arrive.")
    }
    K.TacitText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        visible: !!prompt.failure
        text: prompt.failure
    }
    Button {
        text: qsTr("Cancel")
        enabled: !prompt.busy
        onClicked: prompt.closed()
    }
    Button {
        visible: !!prompt.failure
        text: qsTr("Try again")
        enabled: !prompt.busy
        onClicked: if (prompt.lastChoice === null) prompt.loadSummary(); else prompt.submit(prompt.lastChoice)
    }
    Button {
        visible: !prompt.failure && prompt.account.provider !== "offline-imap" && prompt.account.provider !== "removing-imap"
        objectName: "keepLocalMail"
        text: qsTr("Keep mail on this computer")
        enabled: !!prompt.summary && !prompt.busy
        onClicked: prompt.submit(false)
    }
    Button {
        visible: !prompt.failure
        objectName: "removeLocalMail"
        text: qsTr("Remove mail from this computer")
        enabled: !!prompt.summary && !prompt.busy
        onClicked: prompt.submit(true)
    }
}
