import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Tacit.Kit as K

Item {
    id: setup
    required property var controller
    readonly property var t: K.Kit.tokens
    readonly property real columnWidth: Math.max(0, Math.min(width - t.space.xl * 2, 560,
        Math.max(t.width.panel, Math.round(width / 3))))
    readonly property bool canReturnToMail: controller.accounts.some(account =>
        !["offline-imap", "stopping-imap", "removing-imap"].includes(account.provider))
    property bool addingInternetAccount: false
    property bool signingInWithGoogle: false
    property string googleFailure: ""
    Connections {
        target: setup.controller.mailboxClient
        ignoreUnknownSignals: true
        function onInternetAccountConnected(ok, error) {
            if (!setup.signingInWithGoogle)
                return;
            setup.signingInWithGoogle = false;
            if (ok) {
                if (setup.controller.ui.view === "setup")
                    setup.controller.act("back");
                return;
            }
            const failures = {
                google_oauth_timeout: qsTr("Google sign-in timed out. Select Google to try again."),
                google_oauth_denied: qsTr("Google sign-in was canceled."),
                conflict: qsTr("This account is already connected. Check Accounts in Settings."),
                imap_setup_failed: qsTr("Google signed in, but Tacit could not open your Gmail inbox."),
                smtp_setup_failed: qsTr("Google signed in, but Tacit could not connect to Gmail for sending."),
                credential_store_failed: qsTr("Could not save the Google connection in your system keychain.")
            };
            setup.googleFailure = failures[error] || qsTr("Could not connect to Google. Try again.");
        }
    }
    function cancelGoogleSignIn() {
        if (!signingInWithGoogle)
            return;
        signingInWithGoogle = false;
        controller.mailboxClient.cancelGoogleAccount();
    }
    onVisibleChanged: if (!visible) {
        addingInternetAccount = false;
        if (controller.ui.view !== "setup") {
            cancelGoogleSignIn();
            googleFailure = "";
        }
    }
    function selectProvider(provider) {
        if (provider === "Google" && controller.mailboxClient) {
            signingInWithGoogle = true;
            googleFailure = "";
            controller.mailboxClient.connectGoogleAccount();
            return;
        }
        if (controller.mailboxClient && provider === "Another provider") {
            addingInternetAccount = true;
            return;
        }
        controller.act("provider", {name: provider});
    }
    Loader {
        anchors.fill: parent
        active: setup.addingInternetAccount
        sourceComponent: MailInternetAccountForm {
            client: setup.controller.mailboxClient
            columnWidth: setup.columnWidth
            onCanceled: setup.addingInternetAccount = false
            onConnected: setup.controller.act("back")
        }
    }
    Flickable {
        anchors.fill: parent
        visible: !setup.addingInternetAccount
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: Math.max(height, setupContent.y + setupContent.implicitHeight + setup.t.space.page)
        MailAction {
            visible: setup.canReturnToMail
            objectName: "setupBackToMail"
            anchors.right: setupContent.right
            y: setup.t.space.xl
            text: qsTr("Back to Mail")
            onActivated: setup.controller.act("back")
        }
        ColumnLayout {
            id: setupContent
            objectName: "setupContent"
            x: (parent.width - width) / 2
            y: Math.max(setup.canReturnToMail ? setup.t.space.xl + setup.t.height.action : setup.t.space.xl,
                setup.height - implicitHeight - setup.t.space.page)
            width: setup.columnWidth
            spacing: setup.t.space.l
            MailHeadline {
                Layout.fillWidth: true
                text: qsTr("Add your mail")
            }
            K.TacitText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                ink: "sec"
                text: setup.controller.mailboxClient
                    ? qsTr("Sign in with Google or connect another provider with an app password.")
                    : qsTr("Choose your provider to continue in the system sign-in window.")
            }
            K.TacitText {
                Layout.fillWidth: true
                visible: setup.signingInWithGoogle || setup.googleFailure !== ""
                wrapMode: Text.Wrap
                text: setup.signingInWithGoogle ? qsTr("Finish signing in to Google in your browser.") : setup.googleFailure
            }
            MailAction {
                visible: setup.signingInWithGoogle
                objectName: "cancelGoogleSignIn"
                text: qsTr("Cancel Google sign-in")
                onActivated: setup.cancelGoogleSignIn()
            }
            Column {
                Layout.fillWidth: true
                Layout.topMargin: setup.t.space.m
                Repeater {
                    model: ["Google", "Microsoft", "iCloud", "Fastmail", "Another provider"]
                    delegate: AbstractButton {
                        id: providerRow
                        required property string modelData
                        readonly property string detail: modelData === "Another provider" ? qsTr("IMAP and SMTP") : ""
                        readonly property bool highlighted: enabled && (hovered || activeFocus || down)
                        objectName: "provider-" + modelData
                        width: parent.width
                        height: setup.t.height.row + 2
                        text: modelData === "Another provider" ? qsTr("Another provider") : modelData
                        Accessible.name: detail ? qsTr("%1, %2").arg(text).arg(detail) : text
                        hoverEnabled: true
                        focusPolicy: Qt.StrongFocus
                        enabled: !setup.signingInWithGoogle && (!setup.controller.mailboxClient || modelData === "Another provider" || modelData === "Google")
                        onClicked: setup.selectProvider(modelData)
                        Keys.onReturnPressed: if (enabled) setup.selectProvider(modelData)

                        HoverHandler {
                            enabled: providerRow.enabled
                            cursorShape: Qt.PointingHandCursor
                        }

                        background: Item {
                            Rectangle {
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: Qt.alpha(setup.t.inkMain, setup.t.wash.hover)
                            }
                            Rectangle {
                                objectName: "providerMarker"
                                visible: providerRow.highlighted
                                anchors.right: parent.left
                                anchors.rightMargin: setup.t.space.m
                                anchors.verticalCenter: parent.verticalCenter
                                width: providerRow.down ? 3 : 2
                                height: setup.t.icon.rail
                                color: setup.t.inkMain
                            }
                        }

                        contentItem: RowLayout {
                            spacing: setup.t.space.m
                            K.TacitText {
                                objectName: "providerName"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: providerRow.text
                                elide: Text.ElideRight
                                ink: !providerRow.enabled ? "meta" : providerRow.highlighted ? "main" : "sec"
                            }
                            K.TacitText {
                                visible: !!providerRow.detail
                                Layout.maximumWidth: providerRow.width * 0.42
                                text: providerRow.detail
                                elide: Text.ElideRight
                                size: "meta"
                                ink: "meta"
                            }
                            K.Symbol {
                                text: "chevron_right"
                                size: setup.t.icon.rail
                                color: providerRow.highlighted ? setup.t.inkMain : setup.t.inkMeta
                            }
                        }
                        padding: 0
                    }
                }
            }
        }
    }
    K.TacitText {
        visible: !setup.addingInternetAccount && setup.controller.ui.provider !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: setup.t.space.xl
        text: qsTr("Waiting for %1 sign-in in the system…").arg(setup.controller.ui.provider)
        ink: "meta"
    }
}
