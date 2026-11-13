import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The keyring question (dialogs v2, approved 2026-10-04), drawn as the notch opened down into a sheet at its
 * normal size, the way the pairing and password sheets are (../bluetooth/BluetoothPairContent.qml,
 * ../polkit/PolkitContent.qml). It only emits answered(result) or refused(reason); Keyring.qml talks to the bridge.
 *
 * ask = { id, kind, params } with the prompter's params (all strings but where noted):
 *   mode "password" | "confirm", title, message, description, warning, choiceLabel, choiceChosen (bool),
 *   passwordNew (bool: choose a new password, asked twice), continueLabel, cancelLabel,
 *   retry (bool: asked again after a wrong password)
 * answered: { reply: "continue", password (password mode), choice (bool) }
 */
Item {
    id: root

    property var ask: null
    // false while the window stays up for the fold back into the notch
    property bool active: false
    // a harness can show the sheet without a window around it
    property bool entered: false
    // answered, waiting to hear whether the password was right
    property bool busy: false

    // the typed text, for a harness that renders the sheet part-filled
    property alias password: pw1.text
    property alias repeat: pw2.text

    signal answered(var result)
    signal refused(string reason)

    // The last question stays readable while the sheet folds away.
    property var held: null
    readonly property var p: (root.ask ?? root.held)?.params ?? ({})
    readonly property bool confirm: root.p.mode === "confirm"
    readonly property bool isNew: !root.confirm && (root.p.passwordNew ?? false)
    readonly property bool retry: (root.p.retry ?? false) && !root.isNew
    readonly property string choiceLabel: root.p.choiceLabel ?? ""
    // a short choice ("Always") is a button beside the others; a long one ("Automatically unlock this keyring
    // whenever I'm logged in") is a check above them
    readonly property bool choiceIsButton: root.confirm && root.choiceLabel.length > 0 && root.choiceLabel.length <= 14
    readonly property bool shown: root.active && root.entered

    // the keyring the unlock names ('An application wants access to the keyring "Login", but it is locked'), which
    // Keyring.qml reads from gnome-keyring's wording in any language it speaks
    property string named: ""
    readonly property var keyringName: root.confirm || root.isNew ? "" : root.named
    readonly property bool isLogin: root.keyringName.toLowerCase() === "login"
    // gnome-keyring's own placeholder name; not something to show
    readonly property bool isPlain: root.isLogin || root.keyringName.toLowerCase() === "default keyring"
    // "Store passwords unencrypted?": the weak choice, which Enter must never pick
    readonly property bool weakConfirm: root.confirm && (root.p.passwordNew ?? false)
    readonly property string headTitle: {
        if (root.isNew) return Translation.tr("Choose a password");
        if (root.weakConfirm) return Translation.tr("Save passwords without protection?");
        if (root.keyringName.length > 0)
            return root.isPlain ? Translation.tr("Unlock your keyring") : Translation.tr("Unlock the “%1” keyring").arg(root.keyringName);
        return (root.p.message ?? "") || (root.p.title ?? "");
    }
    readonly property string headLine: {
        if (root.retry) return Translation.tr("Wrong password. Try again.");
        if ((root.p.warning ?? "").length > 0) return root.p.warning;
        if (root.keyringName.length > 0)
            return root.isLogin ? Translation.tr("An app needs your saved passwords. Use your login password.") : Translation.tr("An app needs your saved passwords.");
        if (root.isNew) return Translation.tr("An app wants to save passwords. Choose the password that will protect them.");
        if (root.weakConfirm) return Translation.tr("With no password, anyone who can open your files can read your saved passwords.");
        return root.p.description ?? "";
    }
    // an account name ("you@example.org on mail.example.org") is set in the mono face
    readonly property bool monoLine: root.confirm && /^\S+@\S+/.test(root.p.description ?? "")
    readonly property bool headIsError: root.retry || (root.p.warning ?? "").length > 0
    readonly property bool mismatch: root.isNew && pw2.text.length > 0 && pw2.text !== pw1.text
    readonly property bool canContinue: {
        if (root.confirm) return true;
        if (root.isNew) return pw1.text === pw2.text;
        return pw1.text.length > 0;
    }
    readonly property string continueText: {
        if (root.busy) return Translation.tr("Checking…");
        if (root.confirm) return (root.p.continueLabel ?? "") || Translation.tr("Continue");
        return root.isNew ? Translation.tr("Set password") : Translation.tr("Unlock");
    }
    readonly property string cancelText: {
        if (root.confirm) return (root.p.cancelLabel ?? "") || Translation.tr("Cancel");
        return root.isNew ? Translation.tr("Cancel") : Translation.tr("Leave locked");
    }

    property bool choice: false
    // Enter answers a confirm only after the sheet has been up a moment, so a key meant for another window
    // cannot approve something the user has not looked at.
    property bool armed: false

    readonly property color ink: Appearance.colors.colInkMain
    readonly property color ink2: Appearance.colors.colInkSecondary
    readonly property color errInk: ColorUtils.mix(Appearance.colors.colError, root.ink, 0.45)
    // primary actions: colPrimary 30 % toward white, dark text on it (Lc 82)
    readonly property color accentFill: ColorUtils.mix(Appearance.colors.colPrimary, root.ink, 0.7)
    readonly property color onAccent: Appearance.m3colors.m3surfaceContainerLowest

    function submit(): void {
        if (!root.shown || !root.canContinue || root.busy) return;
        if (root.confirm && !root.armed) return;
        const r = { reply: "continue", choice: root.choice };
        if (!root.confirm) r.password = pw1.text;
        root.answered(r);
    }
    function answerChoice(): void {
        if (!root.shown || !root.armed) return;
        root.answered({ reply: "continue", choice: true });
    }
    function cancel(): void {
        if (!root.shown || root.busy) return;
        root.refused(root.confirm ? "refused" : "cancelled");
    }
    function focusEntry(): void {
        if (!root.confirm) pw1.input.forceActiveFocus();
        else root.forceActiveFocus();
    }
    // a new question in the same sheet (or a retry) must not inherit the last one's typing
    function reset(): void {
        pw1.text = "";
        pw2.text = "";
        // from the ask itself: `p` may not have re-evaluated yet when this runs from onAskChanged
        root.choice = root.ask?.params?.choiceChosen ?? false;
        root.armed = false;
        arm.restart();
        root.focusEntry();
    }

    onAskChanged: {
        if (!root.ask) return;
        root.held = root.ask;
        root.reset();
        if (root.ask.params?.retry && !root.ask.params?.passwordNew) shake.restart();
    }
    Component.onCompleted: {
        root.held = root.ask;
        root.choice = root.p.choiceChosen ?? false;
        arm.restart();
        if (!root.entered) enter.restart();
    }
    Timer { id: arm; interval: 600; onTriggered: root.armed = true }
    // lets the closed notch geometry draw once before it opens
    Timer { id: enter; interval: 1; onTriggered: { root.entered = true; root.focusEntry(); } }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.cancel();
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.confirm) {
            if (!root.weakConfirm) root.submit();
            event.accepted = true;
        }
    }

    // WindowDialog's dim. Clicks outside do nothing, so a stray click cannot answer or refuse.
    Rectangle {
        anchors.fill: parent
        color: ColorUtils.transparentize(Appearance.colors.colScrim, 0.5)
        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        MouseArea {
            anchors.fill: parent
            onPressed: root.focusEntry()
        }
    }

    // The notch's closed and open geometry (IslandController.geometryFor, IslandContent.qml:162).
    readonly property var closedGeometry: IslandController.geometryFor(IslandController.transientShowing ? IslandController.transientState : "idle")
    readonly property real openWidth: 560

    Item {
        id: sheet
        readonly property real fillet: 6
        width: root.shown ? root.openWidth : root.closedGeometry.w
        height: root.shown ? 34 + body.implicitHeight : 34
        property real cornerRadius: root.shown ? 24 : root.closedGeometry.r
        x: (root.width - width) / 2
        y: Config.options.island.topMargin

        // Open on the notch's spring curve, fold back on its close curve (IslandContent.qml:153-158).
        readonly property int duration: root.shown ? Appearance.animationCurves.expressiveDefaultSpatialDuration : 450
        readonly property list<real> curve: root.shown ? Appearance.animationCurves.expressiveDefaultSpatial : Appearance.animationCurves.emphasizedDecel
        Behavior on width {
            NumberAnimation { duration: sheet.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: sheet.curve }
        }
        Behavior on height {
            NumberAnimation { duration: sheet.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: sheet.curve }
        }
        Behavior on cornerRadius {
            NumberAnimation { duration: sheet.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: sheet.curve }
        }

        DockedRect {
            anchors.fill: parent
            cornerRadius: sheet.cornerRadius
            fillet: sheet.fillet
            // solid: the layer's blur skips anything under 79 % alpha, so the frost would show what is behind it
            color: Appearance.m3colors.m3surfaceContainerHigh
        }

        // The strip: the time where it always is (IslandHeader.qml:85-87).
        StyledText {
            width: parent.width
            height: 34
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: DateTime.time
            font.family: Appearance.font.family.numbers
            font.pixelSize: 16
            color: root.ink
        }

        Item {
            anchors.fill: parent
            anchors.topMargin: 34
            clip: true

            ColumnLayout {
                id: body
                x: 20
                width: root.openWidth - 40
                spacing: 12
                opacity: root.shown ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    Layout.topMargin: 8
                    Layout.fillWidth: true
                    spacing: 12
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 1
                        text: root.confirm ? "key" : "lock"
                        iconSize: 26
                        color: Appearance.colors.colPrimary
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        StyledText {
                            Layout.fillWidth: true
                            text: root.headTitle
                            elide: Text.ElideRight
                            font.pixelSize: 17
                            font.weight: Font.Medium
                            color: root.ink
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: root.mismatch ? Translation.tr("The two passwords differ.") : root.headLine
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            font.family: root.monoLine ? Appearance.font.family.monospace : Appearance.font.family.main
                            font.pixelSize: 14
                            color: (root.headIsError || root.mismatch) ? root.errInk : root.ink
                        }
                    }
                }

                PasswordField {
                    id: pw1
                    visible: !root.confirm
                    hint: root.isNew ? Translation.tr("Password") : ""
                    failed: root.retry
                    onAccepted: root.isNew ? pw2.input.forceActiveFocus() : root.submit()
                }
                PasswordField {
                    id: pw2
                    visible: root.isNew
                    hint: Translation.tr("Repeat password")
                    failed: root.mismatch
                    onAccepted: root.submit()
                }

                Check {
                    visible: root.choiceLabel.length > 0 && !root.choiceIsButton
                    Layout.fillWidth: true
                    label: root.choiceLabel
                    on: root.choice
                    onToggled: root.choice = !root.choice
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 14
                    spacing: 6
                    Item { Layout.fillWidth: true }
                    TextAction { label: root.cancelText; onClicked: root.cancel() }
                    TextAction { visible: root.choiceIsButton; label: root.choiceLabel; onClicked: root.answerChoice() }
                    Primary { label: root.continueText; dim: !root.canContinue || root.busy; onClicked: root.submit() }
                }
            }
        }
    }

    // ErrorShakeAnimation shakes by Layout.leftMargin, which the field does not use; a plain offset on the first field.
    SequentialAnimation {
        id: shake
        NumberAnimation { target: pw1; property: "shiftX"; to: -14; duration: 50 }
        NumberAnimation { target: pw1; property: "shiftX"; to: 14; duration: 50 }
        NumberAnimation { target: pw1; property: "shiftX"; to: -7; duration: 40 }
        NumberAnimation { target: pw1; property: "shiftX"; to: 7; duration: 40 }
        NumberAnimation { target: pw1; property: "shiftX"; to: 0; duration: 30 }
    }

    // ------------------------------------------------------------------ parts

    // The approved field: a tinted slab with round dots, 2 px error ring when wrong.
    component PasswordField: Rectangle {
        id: pf
        property string hint: ""
        property bool failed: false
        property real shiftX: 0
        property alias input: ti
        property alias text: ti.text
        signal accepted

        Layout.fillWidth: true
        Layout.preferredHeight: 48
        radius: 14
        color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
        border.width: pf.failed ? 2 : 0
        border.color: root.errInk
        transform: Translate { x: pf.shiftX }

        StyledText {
            x: 18
            anchors.verticalCenter: parent.verticalCenter
            visible: ti.text.length === 0 && pf.hint.length > 0
            text: pf.hint
            font.pixelSize: 14
            color: Appearance.colors.colInkMeta
        }
        TextInput {
            id: ti
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            verticalAlignment: TextInput.AlignVCenter
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            color: "transparent"
            selectionColor: "transparent"
            selectedTextColor: "transparent"
            cursorVisible: false
            cursorDelegate: Item {}
            font.pixelSize: 16
            clip: true
            onAccepted: pf.accepted()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.cancel();
                    event.accepted = true;
                }
            }
            // dots drawn over the hidden text; the newest end stays in view
            Item {
                anchors.fill: parent
                clip: true
                Row {
                    id: dots
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.min(0, parent.width - width - 4)
                    Repeater {
                        model: ti.text.length
                        Rectangle { width: 11; height: 11; radius: 5.5; color: root.ink }
                    }
                    Rectangle {
                        width: 2; height: 20; radius: 1
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.ink
                        visible: ti.activeFocus
                        SequentialAnimation on opacity {
                            running: ti.activeFocus
                            loops: Animation.Infinite
                            NumberAnimation { to: 0; duration: 500 }
                            NumberAnimation { to: 1; duration: 500 }
                        }
                    }
                }
            }
        }
    }

    component TextAction: Rectangle {
        id: ta
        property string label: ""
        signal clicked
        Layout.maximumWidth: 220
        implicitWidth: Math.min(220, tal.implicitWidth + 24)
        implicitHeight: 36
        radius: 18
        color: tama.containsMouse ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.92) : "transparent"
        StyledText {
            id: tal
            anchors.centerIn: parent
            width: Math.min(implicitWidth, ta.width - 24)
            elide: Text.ElideRight
            text: ta.label
            font.pixelSize: 14
            color: root.ink
        }
        MouseArea { id: tama; anchors.fill: parent; hoverEnabled: true; onClicked: ta.clicked() }
    }

    component Primary: Rectangle {
        id: pr
        property string label: ""
        property bool dim: false
        signal clicked
        implicitWidth: prl.implicitWidth + 32
        implicitHeight: 36
        radius: 18
        // inert: a quiet tint with meta-level ink (a faded accent fill left the label unreadable)
        color: pr.dim ? ColorUtils.transparentize(root.ink, 0.88) : root.accentFill
        StyledText {
            id: prl
            anchors.centerIn: parent
            text: pr.label
            font.pixelSize: 14
            font.weight: Font.Medium
            color: pr.dim ? root.ink2 : root.onAccent
        }
        MouseArea { anchors.fill: parent; enabled: !pr.dim; onClicked: pr.clicked() }
    }

    component Check: Item {
        id: ck
        property string label: ""
        property bool on: false
        signal toggled
        implicitHeight: 28
        implicitWidth: 30 + cl.implicitWidth
        Rectangle {
            id: box
            width: 20; height: 20; radius: 6
            anchors.verticalCenter: parent.verticalCenter
            color: ck.on ? root.accentFill : "transparent"
            border.width: 2
            border.color: ck.on ? root.accentFill : root.ink2
            MaterialSymbol {
                anchors.centerIn: parent
                visible: ck.on
                text: "check"
                iconSize: 15
                color: root.onAccent
            }
        }
        StyledText {
            id: cl
            anchors.left: box.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: ck.label
            font.pixelSize: 14
            color: root.ink2
        }
        MouseArea { anchors.fill: parent; onClicked: ck.toggled() }
    }
}
