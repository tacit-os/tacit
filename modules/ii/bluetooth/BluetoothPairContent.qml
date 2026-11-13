import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The pairing question, drawn as the notch opening down into it, the way the password request is
 * (../polkit/PolkitContent.qml): the notch's shape, frost, strip and type; the lock's confirm disc
 * and field. The window is a full-screen overlay (BluetoothPairing.qml) that holds the keyboard
 * while asking; the real notch stays closed underneath.
 *
 * Five kinds arrive from quiet-btagent. Four are questions; "display" is a code to type on the other
 * device and has nothing to answer, so it gets one action that only puts the sheet away.
 */
Item {
    id: root
    // The last question stays readable while the sheet folds back after the answer.
    property var held: null
    readonly property var ask: BluetoothAgent.ask ?? root.held
    readonly property string kind: root.ask?.kind ?? ""
    readonly property string device: root.ask?.device ?? ""
    readonly property string code: root.ask?.code ?? ""
    readonly property bool needsTyping: root.kind === "pin" || root.kind === "passkey"
    readonly property bool informational: root.kind === "display"
    // False while the window stays up for the fold back into the notch.
    readonly property bool shown: BluetoothAgent.asking && root.entered
    property bool entered: false
    // Enter answers only after the sheet has been up a moment, so a key meant for another window
    // cannot pair a device the user has not looked at.
    property bool armed: false

    function submit(): void {
        if (!BluetoothAgent.asking) return;
        if (root.needsTyping && codeField.text.length === 0) return;
        BluetoothAgent.accept(codeField.text);
    }
    function close(): void {
        if (!BluetoothAgent.asking) return;
        if (root.informational) BluetoothAgent.dismiss();
        else BluetoothAgent.refuse();
    }
    function focusEntry(): void {
        if (root.needsTyping) codeField.forceActiveFocus();
        else root.forceActiveFocus();
    }

    Component.onCompleted: {
        root.held = BluetoothAgent.ask;
        root.entered = true;
        arm.restart();
        root.focusEntry();
    }
    Timer {
        id: arm
        interval: 600
        onTriggered: root.armed = true
    }
    Connections {
        target: BluetoothAgent
        // A new question in the same sheet must not inherit the last one's typing.
        function onAskChanged() {
            if (!BluetoothAgent.ask) return;
            root.held = BluetoothAgent.ask;
            codeField.text = "";
            root.armed = false;
            arm.restart();
            root.focusEntry();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.close();
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !root.needsTyping && root.armed) {
            if (root.informational) root.close();
            else root.submit();
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
            color: IslandController.bodyColor
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
            color: Appearance.colors.colOnLayer0
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
                        Layout.alignment: Qt.AlignVCenter
                        text: "bluetooth"
                        iconSize: 26
                        color: Appearance.colors.colPrimary
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                if (root.kind === "service") return Translation.tr("Let %1 connect?").arg(root.device);
                                if (root.informational) return Translation.tr("Type this on %1").arg(root.device);
                                return Translation.tr("Pair with %1?").arg(root.device);
                            }
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnLayer0
                        }
                        // The address earns its place only when the name is the address, or absent.
                        StyledText {
                            Layout.fillWidth: true
                            visible: (root.ask?.address ?? "").length > 0 && root.device !== root.ask?.address
                            text: root.ask?.address ?? ""
                            elide: Text.ElideMiddle
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    text: {
                        switch (root.kind) {
                        case "confirm":
                            return Translation.tr("The same code should be on the other screen. If it is not, this is not the device you think it is.");
                        case "authorize":
                            return Translation.tr("It asked to pair. Nothing is shown on either side to compare, so only accept a device you just put in pairing mode.");
                        case "service":
                            return Translation.tr("A device you have paired is asking to use a service on this machine.");
                        case "pin":
                            return Translation.tr("The device has a PIN, usually printed on it or shown on its screen. Older keyboards and speakers use 0000.");
                        case "passkey":
                            return Translation.tr("Enter the digits the device is showing.");
                        case "display":
                            return Translation.tr("The pairing finishes on the other device, or it goes away on its own.");
                        }
                        return "";
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: root.code.length > 0 || root.needsTyping
                    implicitHeight: 1
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
                }

                // The code: the one thing on the sheet the user has to read carefully, so it is set
                // out on its own line rather than left inside a sentence.
                StyledText {
                    visible: root.code.length > 0
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.code
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: 44
                    font.letterSpacing: 8
                    color: Appearance.colors.colOnLayer0
                }

                // The lock's field (LockSurface.qml:309-404): transparent, large text.
                ToolbarTextField {
                    id: codeField
                    visible: root.needsTyping
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    Layout.leftMargin: 0
                    padding: 0
                    colBackground: "transparent"
                    placeholderText: root.kind === "pin" ? Translation.tr("PIN") : Translation.tr("Passkey")
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.large
                    inputMethodHints: root.kind === "passkey" ? Qt.ImhDigitsOnly : Qt.ImhNone
                    // the hint only shapes an on-screen keyboard; a passkey is a number up to six digits, and
                    // digits only: an IntValidator takes the locale's group separator (123,456) and a sign, which
                    // the agent's strtoull reads as a shorter number
                    validator: root.kind === "passkey" ? passkeyValidator : null
                    RegularExpressionValidator {
                        id: passkeyValidator
                        regularExpression: /[0-9]{0,6}/
                    }
                    onAccepted: root.submit()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.close();
                            event.accepted = true;
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 14
                    spacing: 6
                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (root.informational) return Translation.tr("Enter or Esc hides");
                            return root.kind === "service" ? Translation.tr("Enter allows · Esc refuses") : Translation.tr("Enter pairs · Esc refuses");
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    TextAction {
                        visible: !root.informational
                        label: Translation.tr("Refuse")
                        onClicked: root.close()
                    }
                    TextAction {
                        visible: root.informational
                        label: Translation.tr("Hide")
                        onClicked: root.close()
                    }
                    Disc {
                        visible: !root.informational
                        glyph: "check"
                        enabled: !root.needsTyping || codeField.text.length > 0
                        opacity: enabled ? 1 : 0.5
                        onActivated: root.submit()
                    }
                }
            }
        }
    }

    // The lock's confirm disc (LockSurface.qml:476-504), always filled.
    component Disc: RippleButton {
        id: disc
        property string glyph: ""
        signal activated
        implicitWidth: 44
        implicitHeight: 44
        padding: 0
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimary
        colRipple: Appearance.colors.colPrimaryActive
        releaseAction: () => disc.activated()
        contentItem: MaterialSymbol {
            text: disc.glyph
            iconSize: 22
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Appearance.colors.colOnPrimary
        }
    }

    // The control panel's quiet text action (SidebarRightContent.qml TextAction), label only.
    component TextAction: RippleButton {
        id: taction
        property string label: ""
        implicitWidth: tactionLabel.implicitWidth + 20
        implicitHeight: 32
        buttonRadius: 16
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer1Hover
        contentItem: StyledText {
            id: tactionLabel
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: taction.label
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
        }
    }
}
