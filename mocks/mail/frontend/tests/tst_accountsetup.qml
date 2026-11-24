import QtQuick
import QtTest
import ".." as Mail

Item {
    width: 900
    height: 720

    QtObject {
        id: mockClient
        property int attempts: 0
        property int googleAttempts: 0
        property int googleCancels: 0
        function connectGoogleAccount() { ++googleAttempts; }
        function cancelGoogleAccount() { ++googleCancels; }
        signal internetAccountConnected(bool ok, string error)
        function connectInternetAccount(settings) {
            ++attempts;
            test.compare(settings.email, "mail@example.test");
            test.compare(settings.imap, "imap.example.test:993");
            test.compare(settings.smtp, "smtp.example.test:465");
            test.compare(settings.password, "fixture-only");
        }
    }

    Mail.MailInternetAccountForm {
        id: form
        anchors.fill: parent
        client: mockClient
        columnWidth: 400
    }

    QtObject {
        id: setupController
        readonly property var accounts: []
        readonly property var ui: ({provider: "", view: "setup"})
        readonly property var mailboxClient: mockClient
    }

    Component {
        id: setupComponent
        Mail.MailAccountSetup {
            width: 900
            height: 720
            controller: setupController
        }
    }

    TestCase {
        id: test
        name: "InternetAccountSetup"
        when: windowShown

        function test_googleSignInCanBeCanceled() {
            const setup = createTemporaryObject(setupComponent, form.parent);
            verify(setup !== null);
            const google = findChild(setup, "provider-Google");
            const cancel = findChild(setup, "cancelGoogleSignIn");
            verify(google !== null && cancel !== null);
            tryVerify(() => google.width > 0 && google.mapToItem(setup, 0, 0).y > 0);
            google.forceActiveFocus();
            keyClick(Qt.Key_Space);
            compare(mockClient.googleAttempts, 1);
            verify(cancel.visible);
            verify(!google.enabled);
            cancel.activated();
            compare(mockClient.googleCancels, 1);
            verify(google.enabled);
            verify(!cancel.visible);
        }

        function test_formSitsAtBottomAndScrollsInShortWindow() {
            const viewport = form.parent;
            const originalHeight = viewport.height;
            const submit = findChild(form, "connectInternetAccount");
            compare(findChild(form, "accountEmail").width, form.columnWidth);
            const bottom = () => submit.mapToItem(form, 0, submit.height).y;
            tryCompare(form, "contentHeight", originalHeight);
            compare(Math.round(bottom()), originalHeight - form.tokens.space.page);

            try {
                viewport.height = 320;
                tryVerify(() => form.contentHeight > form.height);
                form.contentY = form.contentHeight - form.height;
                compare(Math.round(bottom()), form.height - form.tokens.space.page);
            } finally {
                viewport.height = originalHeight;
                form.contentY = 0;
            }
        }

        function test_autofillUpdatesOnlySuggestedFields() {
            const email = findChild(form, "accountEmail");
            const username = findChild(form, "accountUsername");
            const imap = findChild(form, "accountIncomingServer");
            const smtp = findChild(form, "accountOutgoingServer");
            const password = findChild(form, "accountAppPassword");
            email.text = "test@gmx.";
            compare(username.text, "");
            compare(imap.text, "");
            compare(smtp.text, "");

            email.text = "test@GMX.DE";
            compare(username.text, "test@GMX.DE");
            compare(imap.text, "imap.gmx.net:993");
            compare(smtp.text, "mail.gmx.net:465");
            compare(password.text, "");

            imap.text = "custom.example.test:993";
            imap.edited();
            email.text = "other@gmail.com";
            compare(username.text, "other@gmail.com");
            compare(imap.text, "custom.example.test:993");
            compare(smtp.text, "smtp.gmail.com:465");

            email.text = "other@example.test";
            compare(username.text, "other@example.test");
            compare(imap.text, "custom.example.test:993");
            compare(smtp.text, "");
            compare(password.text, "");
            imap.manuallyEdited = false;
            email.text = "";
        }

        function test_passwordClearedOnSubmit_data() {
            return [{tag: "click", keyboard: false}, {tag: "enter", keyboard: true}];
        }

        function test_passwordClearedOnSubmit(row) {
            mockClient.attempts = 0;
            const submit = findChild(form, "connectInternetAccount");
            const password = findChild(form, "accountAppPassword");
            verify(!submit.enabled);
            compare(password.input.echoMode, TextInput.Password);
            findChild(form, "accountEmail").text = "mail@example.test";
            findChild(form, "accountIncomingServer").text = "imap.example.test:993";
            findChild(form, "accountOutgoingServer").text = "smtp.example.test:465";
            password.text = "fixture-only";
            verify(submit.enabled);
            if (row.keyboard) {
                password.focusIn();
                keyClick(Qt.Key_Return);
            } else {
                mouseClick(submit);
            }
            compare(mockClient.attempts, 1);
            compare(password.text, "");
            verify(!submit.enabled);
            mockClient.internetAccountConnected(false, "imap_setup_failed");
            verify(!form.submitting);
            verify(form.failure.length > 0);
        }
    }
}
