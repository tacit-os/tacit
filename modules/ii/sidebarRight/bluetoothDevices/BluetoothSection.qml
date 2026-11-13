import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

/**
 * Bluetooth, unfolded inside the quick panel like Wi-Fi: one motion (the panel following its
 * content), flat rows with hairlines. Header: name, the switch. Rows: device, state, and a
 * click connects or disconnects; the actions a device carries (forget, keep paired) unfold
 * under it on a right-click. Discovery runs while the section is open, started a beat after
 * the unfold so it never shares a frame with the motion.
 */
Item {
    id: root
    property bool shown: false
    readonly property int rowHeight: 40
    readonly property int maxRows: 6
    property bool settling: false
    Timer {
        id: settleTimer
        interval: 600
        onTriggered: root.settling = false
    }
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool discovering: root.adapter?.discovering ?? false
    // What the switch was last asked for, held until BlueZ confirms it (null = nothing asked).
    // Powering an adapter on is not instant, and it is the confirmation that moves the thumb,
    // so without this the switch appears to reject the click and invites a second one.
    property var pendingPower: null
    property bool powerFailed: false

    Layout.fillWidth: true
    implicitHeight: root.shown ? body.implicitHeight : 0
    clip: true
    opacity: root.shown ? 1 : 0
    // Folded = not there: opacity 0 alone still lays every row out and builds its scene
    // nodes on the panel's first frame, which was most of the panel's stutter on opening.
    visible: root.shown || root.implicitHeight > 0
    Behavior on implicitHeight {
        Anim {
            type: Anim.Emphasized
        }
    }
    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }
    onShownChanged: {
        if (root.shown) {
            root.settling = true;
            settleTimer.restart();
            discoverLater.restart();
        } else {
            discoverLater.stop();
            if (root.adapter) {
                root.adapter.discovering = false;
                root.adapter.pairable = false;
            }
        }
    }
    // A look at the list does not power the adapter on: the switch does. Pairable goes on with
    // discovery, because the adapter comes up unpairable after boot and BlueZ then refuses to
    // bond, which looks from here like a click that did nothing.
    function startLooking() {
        if (!root.shown || !root.adapter || !root.adapter.enabled)
            return;
        // Discovery first, pairable after the event loop turn: written back to back, only the
        // first of the two property writes reached BlueZ.
        root.adapter.discovering = true;
        Qt.callLater(() => { if (root.adapter) root.adapter.pairable = true; });
        keepAsking.left = 8;
        keepAsking.restart();
    }
    Timer {
        id: keepAsking
        // An adapter that has just powered on is not ready for StartDiscovery for a second or
        // two, and the request is lost without a word. Ask again until it takes.
        property int left: 0
        interval: 900        // BlueZ answers "Resource Not Ready" until the adapter settles
        repeat: true
        onTriggered: {
            if (!root.shown || !root.adapter || !root.adapter.enabled || root.adapter.discovering || keepAsking.left <= 0) {
                keepAsking.stop();
                return;
            }
            keepAsking.left -= 1;
            root.adapter.discovering = true;
        }
    }
    // Powering Bluetooth off can replace the adapter object rather than flip its enabled flag,
    // and then nothing on the old one ever reports the change.
    onAdapterChanged: root.startLooking()
    Timer {
        id: discoverLater
        interval: 500
        onTriggered: root.startLooking()
    }
    Connections {
        target: root.adapter
        // Powering the adapter on takes longer than any timer worth waiting on, so switching
        // Bluetooth on used to leave the list empty for good: the timer fired while it was
        // still off and nothing tried again. Start looking when it actually comes up.
        function onEnabledChanged() {
            root.pendingPower = null;
            root.powerFailed = false;
            powerWatchdog.stop();
            if (root.adapter?.enabled)
                root.startLooking();
        }
    }
    Timer {
        id: powerWatchdog
        // A power switch that is refused - a soft rfkill block, firmware that did not come up -
        // never reports back, so the value the user asked for would stand for the whole session.
        interval: 4000
        onTriggered: {
            root.pendingPower = null;
            root.powerFailed = true;
        }
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 6
            StyledText {
                text: Translation.tr("Bluetooth")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            Item {
                Layout.fillWidth: true
            }
            StyledSwitch {
                // With no adapter togglePower() writes to nothing, so the thumb used to slide and
                // the watchdog reported a failure four seconds later.
                enabled: BluetoothStatus.available
                checked: root.pendingPower ?? BluetoothStatus.enabled
                onClicked: {
                    // Switch flips checked itself on release, so the binding has to go back on;
                    // pendingPower is set first so it goes back on over the asked-for value.
                    root.pendingPower = !BluetoothStatus.enabled;
                    root.powerFailed = false;
                    checked = Qt.binding(() => root.pendingPower ?? BluetoothStatus.enabled);
                    BluetoothStatus.togglePower();
                    powerWatchdog.restart();
                    if (root.shown)
                        discoverLater.restart();
                }
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 1
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colLayer0Border
            }
            StyledIndeterminateProgressBar {
                anchors.fill: parent
                visible: root.discovering
            }
        }

        StyledFlickable {
            id: list
            Layout.fillWidth: true
            // Full height only while the unfold settles, so results landing mid-motion do not
            // move the target; then the list is as tall as its rows (an empty list stays short).
            implicitHeight: root.settling ? root.maxRows * root.rowHeight + 8
                : Math.min(rows.implicitHeight, root.maxRows * root.rowHeight + 8)
            contentHeight: rows.implicitHeight
            clip: true

            Column {
                id: rows
                width: list.width
                // Leads the list, because BlueZ keeps its paired devices whether the adapter is
                // powered or not: with the radio off the rows are still there, dimmed, and the
                // reason they do nothing has to be on screen.
                StyledText {
                    width: rows.width
                    height: root.rowHeight
                    visible: root.powerFailed || !BluetoothStatus.enabled || BluetoothStatus.friendlyDeviceList.length === 0
                    verticalAlignment: Text.AlignVCenter
                    // "Bluetooth is off" with no adapter present blames the switch above, which is
                    // the one thing the user cannot fix from here.
                    text: !BluetoothStatus.available ? Translation.tr("No Bluetooth adapter")
                        : root.powerFailed ? (BluetoothStatus.enabled ? Translation.tr("Bluetooth did not turn off") : Translation.tr("Bluetooth did not turn on"))
                        : BluetoothStatus.enabled ? (root.discovering ? Translation.tr("Looking for devices") : Translation.tr("No devices")) : Translation.tr("Bluetooth is off")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                Repeater {
                    model: ScriptModel {
                        values: BluetoothStatus.friendlyDeviceList
                    }
                    delegate: DeviceRow {
                        required property BluetoothDevice modelData
                        device: modelData
                        width: rows.width
                        rowHeight: root.rowHeight
                    }
                }
                // The scan list hides nameless strangers (BluetoothStatus.unnamedRegex), and a
                // real device whose name has not resolved yet is behind that filter too. Say how
                // many, where they would have been, and let the list be opened up.
                RippleButton {
                    width: rows.width
                    implicitHeight: root.rowHeight
                    visible: BluetoothStatus.enabled && (BluetoothStatus.hiddenUnnamedCount > 0 || !BluetoothStatus.hideUnnamedDevices)
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: Config.options.bluetooth.hideUnnamedDevices = !BluetoothStatus.hideUnnamedDevices
                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        StyledText {
                            Layout.fillWidth: true
                            text: BluetoothStatus.hideUnnamedDevices
                                ? Translation.tr("Show %1 unnamed").arg(BluetoothStatus.hiddenUnnamedCount)
                                : Translation.tr("Hide unnamed devices")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }

    component DeviceRow: Item {
        id: row
        required property BluetoothDevice device
        property int rowHeight: 40
        property bool more: false
        readonly property bool busy: (row.device?.pairing || row.device?.state === BluetoothDeviceState.Connecting || row.device?.state === BluetoothDeviceState.Disconnecting) ?? false
        // An attempt that can still be called off: bonding, connecting, or waiting out the
        // adapter's settle window in keepTrying.
        readonly property bool cancellable: (row.device?.pairing ?? false)
            || row.device?.state === BluetoothDeviceState.Connecting
            || row.asked === "connect"
        // Neither pair() nor connect() reports failure: they return nothing and there is no error
        // signal on the device, so a headset that is out of pairing mode looks exactly like a
        // click that did nothing. Remember what was asked for and say so if it does not happen.
        property string asked: ""
        property string failed: ""
        // A bond can land after waitTimer has given up, and the trust-and-connect follow-up is
        // the point of pairing, so it stays armed until the device bonds or is forgotten.
        property bool pairPending: false
        // Was it connected a moment ago? A link that dropped and a device that never connected
        // this session both read "Paired" otherwise.
        property bool wasConnected: false
        Component.onCompleted: row.wasConnected = row.device?.connected ?? false
        function ask(what) {
            row.failed = "";
            row.asked = what;
            waitTimer.restart();
        }
        function stopWaiting() {
            row.asked = "";
            row.failed = "";
            row.pairPending = false;
            waitTimer.stop();
            keepTrying.stop();
        }
        // One way in for a pairing, from the row and from the actions row alike: the trust and
        // connect that make a headset come back on its own hang off pairPending.
        function pairNow() {
            const d = row.device;
            if (!d) return;
            row.pairPending = true;
            row.ask("pair");
            d.pair();
        }
        // Trust first, so the device is allowed back on its own after one of this laptop's
        // supervision-timeout drops.
        function connectNow() {
            const d = row.device;
            if (!d) return;
            if (d.paired && !d.trusted)
                d.trusted = true;
            row.ask("connect");
            d.connect();
            keepTrying.left = 3;
            keepTrying.restart();
        }
        Timer {
            id: waitTimer
            interval: 12000                      // pairing a headset can take ten seconds
            onTriggered: {
                const d = row.device;
                if (!d || row.asked === "")
                    return;
                if (row.asked === "connect" && !d.connected)
                    row.failed = Translation.tr("Did not answer");
                else if (row.asked === "disconnect" && d.connected)
                    row.failed = Translation.tr("Did not disconnect");
                else if (row.asked === "pair" && !d.paired)
                    // Nothing in this shell answers a passkey or a confirmation request - there is
                    // no pairing agent - so the only place left to finish the bond is the device.
                    row.failed = Translation.tr("Confirm on the device");
                row.asked = "";
            }
        }
        Timer {
            id: keepTrying
            // An adapter that has just powered on rejects Connect for a second or two, the same
            // settle window keepAsking covers for discovery, and answers with nothing catchable.
            property int left: 0
            interval: 900
            repeat: true
            onTriggered: {
                const d = row.device;
                if (!d || row.asked !== "connect" || d.connected || d.state === BluetoothDeviceState.Connecting || keepTrying.left <= 0) {
                    keepTrying.stop();
                    return;
                }
                keepTrying.left -= 1;
                d.connect();
            }
        }
        Connections {
            target: row.device
            // A device that pairs but does not connect is the normal case for audio: BlueZ
            // bonds, and the profile only comes up when something asks for it. Keyed on
            // pairPending, not on asked, so a bond that lands late is still followed up.
            function onPairedChanged() {
                if (!row.pairPending || !row.device?.paired)
                    return;
                row.pairPending = false;
                row.failed = "";
                if (row.device.connected)
                    row.device.trusted = true;
                else
                    row.connectNow();
            }
            function onConnectedChanged() {
                if (row.device?.connected) {
                    row.wasConnected = true;
                    row.asked = "";
                    row.failed = "";
                    waitTimer.stop();
                    keepTrying.stop();
                    return;
                }
                if (row.asked === "disconnect") {   // asked for, and it answered
                    row.stopWaiting();
                    row.wasConnected = false;
                    return;
                }
                // The 0x08 supervision timeouts this laptop sees drop the link without a word,
                // and falling back to "Paired" says nothing happened.
                if (row.wasConnected && row.asked === "" && BluetoothStatus.enabled)
                    row.failed = Translation.tr("Dropped");
                row.wasConnected = false;
            }
        }
        readonly property string stateText: {
            const d = row.device;
            if (!d) return "";
            if (d.pairing) return Translation.tr("Pairing");
            // From the moment the user asks, as with Connecting below: BlueZ's own Disconnecting
            // state never arrives for a device that has walked out of range.
            if (d.state === BluetoothDeviceState.Disconnecting || row.asked === "disconnect") return Translation.tr("Disconnecting");
            if (d.connected) return BluetoothStatus.hasBattery(d) ? `${Math.round(d.battery * 100)}%` : "";
            // From the moment the user asks, not from BlueZ's state change: the wait before the
            // profile comes up is where a silent row looks like a click that did nothing.
            if (d.state === BluetoothDeviceState.Connecting || row.asked === "connect") return Translation.tr("Connecting");
            if (row.failed.length > 0) return row.failed;
            if (d.paired) return Translation.tr("Paired");
            return "";
        }
        // One label carries five things, so "Did not answer" used to be typographically identical
        // to "Paired". Failures are red here as they are in the Wi-Fi section.
        readonly property bool showingFailure: row.failed.length > 0 && row.stateText === row.failed
        implicitHeight: row.rowHeight + (actions.visible ? actions.implicitHeight : 0)
        Behavior on implicitHeight {
            Anim {
                type: Anim.Emphasized
            }
        }

        RippleButton {
            id: line
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            implicitHeight: row.rowHeight
            buttonRadius: Appearance.rounding.small
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            // Enabled even while busy: disabling the button disables its own MouseArea, which is
            // where the right-click (or held press) that opens the actions - the only way to call an
            // attempt off - is dispatched. The state text is the busy cue; the dimming is for a dead adapter.
            opacity: BluetoothStatus.enabled ? 1 : 0.4
            onClicked: {
                const d = row.device;
                if (!d || row.busy) return;
                if (!BluetoothStatus.enabled) {
                    // BlueZ keeps its paired devices with the radio off and answers a Connect with
                    // "adapter-not-powered", which arrives nowhere.
                    row.failed = Translation.tr("Bluetooth is off");
                    return;
                }
                if (!d.paired) {        // a new device: pair first, then connect when it bonds
                    row.pairNow();
                } else if (d.connected) {
                    row.wasConnected = false;   // asked for, so not a drop
                    row.stopWaiting();
                    // BlueZ reports no Disconnecting state for a device that is already physically
                    // gone (this laptop's 0x08 supervision timeouts), so without the same watchdog
                    // pair and connect use, the click read as ignored and the check glyph stood.
                    row.ask("disconnect");
                    d.disconnect();
                } else {
                    row.connectNow();
                }
            }
            altAction: () => { row.more = !row.more; }
            altOnHold: true   // a touch screen holds the row, a keyboard presses Menu: no right-click there
            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10
                MaterialSymbol {
                    text: Icons.getBluetoothDeviceMaterialSymbol(row.device?.icon || "")
                    iconSize: 20
                    color: row.device?.connected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    text: row.device?.name || Translation.tr("Unknown device")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    visible: text.length > 0
                    text: row.stateText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: row.showingFailure ? Appearance.colors.colError : Appearance.colors.colSubtext
                }
                MaterialSymbol {
                    visible: (row.device?.connected ?? false) && !row.busy && row.asked !== "disconnect"
                    text: "check"
                    iconSize: 18
                    color: Appearance.colors.colPrimary
                }
            }
        }

        // Right-click, a held press or the Menu key: what else a device can do. Call off an attempt while one is under way;
        // trust and forget for a paired device; keep paired for a new one so it reconnects on
        // its own.
        RowLayout {
            id: actions
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: line.bottom
            anchors.leftMargin: 40
            anchors.rightMargin: 10
            visible: row.more
            spacing: 6
            Item {
                Layout.fillWidth: true
            }
            RippleButton {
                Layout.bottomMargin: 8
                visible: row.cancellable
                implicitHeight: 30
                implicitWidth: cancelLabel.implicitWidth + 24
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer4
                colBackgroundHover: Appearance.colors.colLayer4Hover
                colRipple: Appearance.colors.colLayer4Active
                onClicked: {
                    const d = row.device;
                    if (!d) return;
                    if (d.pairing)
                        d.cancelPair();
                    else
                        d.disconnect();
                    row.stopWaiting();      // or the wait would paint a failure over the cancel
                    row.more = false;
                }
                contentItem: StyledText {
                    id: cancelLabel
                    anchors.centerIn: parent
                    text: Translation.tr("Cancel")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                }
            }
            RippleButton {
                Layout.bottomMargin: 8
                visible: row.device?.paired ?? false
                implicitHeight: 30
                implicitWidth: trustLabel.implicitWidth + 24
                buttonRadius: Appearance.rounding.small
                toggled: row.device?.trusted ?? false
                colBackground: Appearance.colors.colLayer4
                colBackgroundHover: Appearance.colors.colLayer4Hover
                colBackgroundToggled: Appearance.colors.colPrimary
                colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colLayer4Active
                onClicked: {
                    const d = row.device;
                    if (!d) return;
                    d.trusted = !d.trusted;
                }
                contentItem: StyledText {
                    id: trustLabel
                    anchors.centerIn: parent
                    text: Translation.tr("Trusted")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: (row.device?.trusted ?? false) ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                }
                StyledToolTip {
                    text: Translation.tr("Let it come back on its own")
                }
            }
            RippleButton {
                Layout.bottomMargin: 8
                readonly property bool p: row.device?.paired ?? false
                implicitHeight: 30
                implicitWidth: pairLabel.implicitWidth + 24
                buttonRadius: Appearance.rounding.small
                colBackground: p ? Appearance.colors.colLayer4 : Appearance.colors.colPrimary
                colBackgroundHover: p ? Appearance.colors.colLayer4Hover : Appearance.colors.colPrimaryHover
                colRipple: p ? Appearance.colors.colLayer4Active : Appearance.colors.colPrimaryActive
                onClicked: {
                    const d = row.device;
                    if (!d) return;
                    if (d.paired) {
                        row.stopWaiting();
                        d.forget();
                    } else {
                        row.pairNow();      // the same way in as the row: bond, trust, connect
                    }
                    row.more = false;
                }
                contentItem: StyledText {
                    id: pairLabel
                    anchors.centerIn: parent
                    text: parent.parent.p ? Translation.tr("Forget") : Translation.tr("Keep paired")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: parent.parent.p ? Appearance.colors.colOnLayer0 : Appearance.colors.colOnPrimary
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            height: 1
            color: Appearance.colors.colLayer0Border
        }
    }
}
