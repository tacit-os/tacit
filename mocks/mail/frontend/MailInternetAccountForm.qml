import QtQuick
import QtQuick.Layouts
import Tacit.Kit as K

Flickable {
    id: form
    required property var client
    required property real columnWidth
    signal canceled()
    signal connected()
    property bool submitting: false
    property string failure: ""
    readonly property var tokens: K.Kit.tokens
    readonly property bool canConnect: !submitting && !!email.text.trim() && !!imap.text.trim()
        && !!smtp.text.trim() && !!password.text
    readonly property string validEmail: {
        const address = email.text.trim();
        const pattern = /^[^\s@.,;<>]+(?:\.[^\s@.,;<>]+)*@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$/i;
        return pattern.test(address) ? address : "";
    }
    contentWidth: width
    contentHeight: Math.max(height, fields.y + fields.implicitHeight + tokens.space.page)
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    function submit() {
        if (!canConnect)
            return;
        submitting = true;
        failure = "";
        client.connectInternetAccount({
            email: email.text.trim(),
            username: username.text.trim(),
            imap: imap.text.trim(),
            smtp: smtp.text.trim(),
            password: password.text
        });
        password.text = "";
    }

    Connections {
        target: form.client
        function onInternetAccountConnected(ok, error) {
            form.submitting = false;
            if (ok) {
                form.connected();
                return;
            }
            const errors = {
                imap_setup_failed: qsTr("Could not sign in to the incoming mail server. Check its address and your app password."),
                smtp_setup_failed: qsTr("Could not sign in to the outgoing mail server. Check its address and your app password."),
                credential_store_failed: qsTr("Could not save the password. Check that your system keychain is available and unlocked.")
            };
            form.failure = errors[error] || qsTr("Could not connect this account. Check the details and try again.");
            password.focusIn();
        }
    }

    onValidEmailChanged: {
        const domain = validEmail.slice(validEmail.lastIndexOf("@") + 1).toLowerCase();
        const isGmx = ["gmx.de", "gmx.net"].includes(domain);
        const isGmail = domain === "gmail.com" || domain === "googlemail.com";
        username.suggest(validEmail);
        imap.suggest(isGmx ? "imap.gmx.net:993" : isGmail ? "imap.gmail.com:993" : "");
        smtp.suggest(isGmx ? "mail.gmx.net:465" : isGmail ? "smtp.gmail.com:465" : "");
    }

    component SuggestedField: K.Field {
        property bool manuallyEdited: false
        onEdited: manuallyEdited = true

        function suggest(value) {
            if (!manuallyEdited)
                text = value;
        }
    }

    ColumnLayout {
        id: fields
        x: (form.width - width) / 2
        y: Math.max(form.tokens.space.xl, form.height - implicitHeight - form.tokens.space.page)
        width: form.columnWidth
        spacing: form.tokens.space.l
        MailAction {
            text: qsTr("Back to providers")
            enabled: !form.submitting
            onActivated: form.canceled()
        }
        MailHeadline {
            Layout.fillWidth: true
            text: qsTr("Connect with an app password")
        }
        K.TacitText {
            Layout.fillWidth: true
            text: qsTr("Create an app password in your provider’s settings. Enter the servers with their TLS ports, for example imap.example.com:993 and smtp.example.com:465.")
            wrapMode: Text.Wrap
            ink: "sec"
        }
        K.Field {
            id: email
            objectName: "accountEmail"
            Layout.fillWidth: true
            enabled: !form.submitting
            hint: qsTr("Email address")
            input.inputMethodHints: Qt.ImhEmailCharactersOnly
        }
        SuggestedField {
            id: username
            objectName: "accountUsername"
            Layout.fillWidth: true
            enabled: !form.submitting
            hint: qsTr("Username (optional)")
        }
        SuggestedField {
            id: imap
            objectName: "accountIncomingServer"
            Layout.fillWidth: true
            enabled: !form.submitting
            hint: qsTr("Incoming server (IMAP)")
        }
        SuggestedField {
            id: smtp
            objectName: "accountOutgoingServer"
            Layout.fillWidth: true
            enabled: !form.submitting
            hint: qsTr("Outgoing server (SMTP)")
        }
        K.Field {
            id: password
            objectName: "accountAppPassword"
            Layout.fillWidth: true
            enabled: !form.submitting
            hint: qsTr("App password")
            input.echoMode: TextInput.Password
            input.inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            onAccepted: form.submit()
        }
        K.Slab {
            objectName: "connectInternetAccount"
            tone: "default"
            maxWidth: fields.width
            text: form.submitting ? qsTr("Checking your connection…") : qsTr("Connect")
            waiting: !form.canConnect
            onActivated: form.submit()
        }
        K.TacitText {
            Layout.fillWidth: true
            visible: !!form.failure
            text: form.failure
            wrapMode: Text.Wrap
        }
    }
}
