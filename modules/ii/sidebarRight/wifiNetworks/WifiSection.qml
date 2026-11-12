import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Wi-Fi, unfolded inside the quick panel: the same in-place growth as the "more" row and the
 * date group (one motion, the panel following its content), flat rows with hairlines like the
 * notch's sheet and the notification centre, no box and no scrim. Header: name, Details, the
 * switch. Rows: signal, name, state. A secure network you have no profile for unfolds its
 * password line under the row; Enter connects.
 */
Item {
    id: root
    property bool shown: false
    readonly property int rowHeight: 40
    readonly property int maxRows: 6
    property bool settling: false
    property real unfolded: 0   // sum of what rows have unfolded (password lines, actions)
    function recount() {
        let u = 0;
        for (const c of rows.children)
            if (c.extraHeight !== undefined)
                u += c.extraHeight;
        root.unfolded = u;
    }
    Timer {
        id: settleTimer
        interval: 600
        onTriggered: root.settling = false
    }

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
    // The scan starts after the unfold, not with it: starting nmcli processes stalls the GUI
    // thread for tens of milliseconds each, and doing that as the motion begins dropped its
    // first frames (measured: 42, 70, 76 ms gaps; without the calls a steady 16 ms).
    onShownChanged: {
        if (root.shown) {
            root.settling = true;
            settleTimer.restart();
            scanLater.restart();
        } else {
            scanLater.stop();
            Network.wifiActionError = "";
        }
    }
    readonly property bool canScan: Network.wifiEnabled && Network.wifiStatus !== "disabled"
    // The radio reports enabled a moment before the interface can scan: scan when it can.
    onCanScanChanged: if (root.shown && root.canScan) scanLater.restart()
    Timer {
        id: scanLater
        interval: 500
        // A look at the list does not flip the radio: the switch does. Off stays off. The radio
        // reports enabled before the interface is up, so the device has to be usable too.
        onTriggered: if (root.canScan) Network.rescanWifi()
    }
    // While the section is open the signals and the set of networks keep up with the room.
    Timer {
        interval: 15000
        repeat: true
        running: root.shown && root.canScan
        onTriggered: if (!Network.wifiScanning && !Network.wifiConnecting) Network.rescanWifi()
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        // ------------------------------------------------------------ header
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 6
            StyledText {
                text: Translation.tr("Wi-Fi")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            Item {
                Layout.fillWidth: true
            }
            StyledSwitch {
                // What was asked for until nmcli's own state agrees: the radio takes a moment, and
                // the switch must not sit on the state it has just left.
                checked: Network.wifiRadioPending ? Network.wifiRadioWanted : Network.wifiEnabled
                onClicked: {
                    Network.enableWifi(checked);
                    checked = Qt.binding(() => Network.wifiRadioPending ? Network.wifiRadioWanted : Network.wifiEnabled);
                    if (root.shown)
                        scanLater.restart();
                }
            }
        }

        // The hairline under the header carries the scan: it fills while a scan runs.
        Item {
            Layout.fillWidth: true
            implicitHeight: 1
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colLayer0Border
            }
            StyledIndeterminateProgressBar {
                anchors.fill: parent
                visible: Network.wifiScanning
            }
        }

        // What the switch, Disconnect or Forget said when it failed.
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 6
            visible: Network.wifiActionError.length > 0
            text: Network.wifiActionError
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
        }

        // A network that does not broadcast its name: with the header, not under every access
        // point in range, and out of the list's height accounting.
        HiddenRow {
            Layout.fillWidth: true
            rowHeight: root.rowHeight
            visible: Network.wifiEnabled
        }

        // ------------------------------------------------------------ rows
        // A Column, not a ListView: a row that unfolds its password line grows after it was
        // placed, and a ListView keeps the height it measured at placement.
        StyledFlickable {
            id: list
            Layout.fillWidth: true
            // While a scan runs the list keeps its full height, so the unfold has one target
            // instead of jumping when results land mid-motion.
            // Full height only while the unfold settles, so results landing mid-motion do not
            // move the target; then the list is as tall as its rows (an empty list stays short).
            // The cap is on rows, not on what a row unfolds: a password line or the actions of
            // the last visible row grow the list by exactly their height, so they are never
            // hidden below the clip.
            readonly property real cap: root.maxRows * root.rowHeight + 8 + root.unfolded
            implicitHeight: root.settling ? cap : Math.min(rows.implicitHeight, cap)
            contentHeight: rows.implicitHeight
            clip: true

            Column {
                id: rows
                width: list.width
                Repeater {
                    model: ScriptModel {
                        values: Network.friendlyWifiNetworks
                    }
                    delegate: WifiRow {
                        required property WifiAccessPoint modelData
                        network: modelData
                        width: rows.width
                        rowHeight: root.rowHeight
                    }
                }
                StyledText {
                    width: rows.width
                    height: root.rowHeight
                    visible: Network.friendlyWifiNetworks.length === 0
                    verticalAlignment: Text.AlignVCenter
                    // An empty list is where a user decides whether the switch above it will help,
                    // and "Wi-Fi is off" on a machine with no wireless device sends them to it for
                    // nothing. nmcli lists no wifi device at all in that case.
                    text: Network.wifiDevice.length === 0 ? Translation.tr("No Wi-Fi adapter")
                        : Network.wifiEnabled ? (Network.wifiScanning ? Translation.tr("Looking for networks") : Translation.tr("No networks"))
                        : Translation.tr("Wi-Fi is off")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // A network that does not broadcast its name. Unfolds name and password.
    component HiddenRow: Item {
        id: hrow
        property int rowHeight: 40
        property bool open: false
        readonly property real extraHeight: hiddenFields.visible ? hiddenFields.implicitHeight : 0
        implicitHeight: hrow.rowHeight + hrow.extraHeight
        Behavior on implicitHeight {
            Anim {
                type: Anim.Emphasized
            }
        }
        // folded away with the section: the form closes and nothing typed lingers (the password lines of the rows do the same)
        Connections {
            target: root
            function onShownChanged() {
                if (!root.shown) {
                    hrow.open = false;
                    hiddenName.text = "";
                    hiddenPassword.text = "";
                }
            }
        }
        RippleButton {
            id: hline
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            implicitHeight: hrow.rowHeight
            buttonRadius: Appearance.rounding.small
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            onClicked: {
                hrow.open = !hrow.open;
                if (hrow.open)
                    Network.hiddenJoinFailed = false;
            }
            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10
                MaterialSymbol {
                    text: "wifi_find"
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Network.hiddenJoining ? Translation.tr("Joining") : Translation.tr("Join a hidden network")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.maximumWidth: hrow.width / 2
                    visible: Network.hiddenJoinFailed && !hrow.open
                    text: Network.hiddenError.length > 0 ? Network.hiddenError : Translation.tr("Could not join")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colError
                }
            }
        }
        ColumnLayout {
            id: hiddenFields
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: hline.bottom
            anchors.leftMargin: 40
            anchors.rightMargin: 10
            visible: hrow.open
            spacing: 6
            ToolbarTextField {
                id: hiddenName
                Layout.fillWidth: true
                implicitHeight: 30
                padding: 8
                leftPadding: 10
                rightPadding: 10
                radius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer4
                placeholderText: Translation.tr("Network name")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onAccepted: hiddenPassword.forceActiveFocus()
                onVisibleChanged: if (visible) forceActiveFocus()
                Keys.onEscapePressed: hrow.open = false
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                spacing: 6
                ToolbarTextField {
                    id: hiddenPassword
                    Layout.fillWidth: true
                    implicitHeight: 30
                    padding: 8
                    leftPadding: 10
                    rightPadding: 10
                    radius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer4
                    placeholderText: Translation.tr("Password, if any")
                    echoMode: TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData
                    onAccepted: if (hiddenName.text.trim().length > 0) { Network.joinHidden(hiddenName.text.trim(), text); text = ""; hrow.open = false; }
                    Keys.onEscapePressed: hrow.open = false
                }
                RippleButton {
                    implicitHeight: 30
                    implicitWidth: joinLabel.implicitWidth + 24
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    enabled: hiddenName.text.trim().length > 0
                    onClicked: {
                        Network.joinHidden(hiddenName.text.trim(), hiddenPassword.text);
                        hiddenPassword.text = "";
                        hrow.open = false;
                    }
                    contentItem: StyledText {
                        id: joinLabel
                        anchors.centerIn: parent
                        text: Translation.tr("Join")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnPrimary
                    }
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

    // One network: signal, name, state. The connected one carries its facts on a second line
    // (address · band · security) and a click on it unfolds what you can do to it; a secure
    // one you have no profile for unfolds its password line when clicked.
    component WifiRow: Item {
        id: row
        required property WifiAccessPoint network
        property int rowHeight: 40
        property bool more: false
        readonly property bool current: row.network?.active ?? false
        readonly property bool connecting: Network.wifiConnectTarget === row.network && !row.current
        readonly property bool asking: row.network?.askingPassword ?? false
        readonly property string failure: row.network?.lastError ?? ""
        readonly property bool known: Network.isKnown(row.network?.ssid ?? "")
        readonly property bool enterprise: Network.isEnterprise(row.network)
        property string eapMethod: "peap"   // PEAP+MSCHAPv2 (eduroam, most offices) or TTLS+PAP
        readonly property bool trusted: Network.isTrusted(row.network?.ssid ?? "")
        // NetworkManager's own answer, as Settings reads it: a hotel's network can have a password and a sign-in page,
        // and an open network often has neither
        readonly property bool portal: row.current && Network.connectivity === "portal"
        readonly property string band: {
            const f = row.network?.frequency ?? 0;
            return f >= 5925 ? "6 GHz" : f >= 4900 ? "5 GHz" : f > 0 ? "2.4 GHz" : "";
        }
        readonly property string facts: [Network.ipAddress, row.band, Network.securityLabel(row.network?.security), row.trusted ? Translation.tr("trusted") : ""].filter(x => x.length > 0).join(" · ")
        readonly property int lineHeight: row.current ? row.rowHeight + 14 : row.rowHeight
        onCurrentChanged: {
            if (!row.current) {
                row.more = false;
                row.acting = "";   // no longer the network in use: that is what both actions wanted
            } else if (row.network) {
                row.network.lastError = "";   // it got on in the end: nothing left to report
            }
        }
        // Disconnect and Forget used to fold this row away as their first statement, which took the
        // only place their state could be shown with it: the row kept its check and its facts line
        // for as long as nmcli took, with no busy and no end. Neither call reports back, so the row
        // waits under the word for it until the network stops being the one in use.
        property string acting: ""
        function act(word) {
            Network.wifiActionError = "";
            row.acting = word;
            actTimer.restart();
        }
        readonly property string actionError: Network.wifiActionError
        onActionErrorChanged: if (row.actionError.length > 0) row.acting = "";
        Timer {
            id: actTimer
            interval: 12000
            onTriggered: {
                if (row.acting.length === 0)
                    return;
                row.acting = "";
                Network.wifiActionError = Translation.tr("Wi-Fi did not answer");
            }
        }
        onAskingChanged: if (!row.asking) { passwordField.text = ""; identityField.text = ""; if (row.network) row.network.lastError = ""; }   // nothing lingers
        function submit() {
            if (row.enterprise)
                Network.joinEnterprise(row.network, identityField.text, passwordField.text, row.eapMethod);
            else
                Network.changePassword(row.network, passwordField.text);
        }
        readonly property real extraHeight: extra.visible ? extra.implicitHeight : 0
        onExtraHeightChanged: root.recount()
        Component.onDestruction: Qt.callLater(root.recount)
        implicitHeight: row.lineHeight + row.extraHeight
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
            implicitHeight: row.lineHeight
            buttonRadius: Appearance.rounding.small
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            onClicked: {
                if (row.connecting) {   // a second click gives up on the join
                    Network.cancelJoin(Translation.tr("Stopped joining"));
                    return;
                }
                if (row.asking) {   // a second click on the row folds the password line
                    row.network.askingPassword = false;
                    return;
                }
                if (row.current) {
                    row.more = !row.more;
                    return;
                }
                Network.connectToWifiNetwork(row.network);
            }
            // Right-click opens a row's actions in the Bluetooth and VPN sections; this one had no
            // right-click at all, so the same gesture did three different things across one panel.
            altAction: () => {
                if (row.current)
                    row.more = !row.more;
            }
            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10
                MaterialSymbol {
                    text: Network.strengthIcon(row.network?.strength ?? 0)
                    iconSize: 20
                    color: row.current ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        Layout.fillWidth: true
                        text: row.network?.ssid ?? Translation.tr("Unknown")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: row.current && row.facts.length > 0
                        text: row.facts
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                StyledText {
                    // The join can be given up on: the row says so where the pointer is.
                    visible: row.connecting
                    text: line.hovered ? Translation.tr("Stop") : Translation.tr("Connecting")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: line.hovered ? Appearance.colors.colError : Appearance.colors.colSubtext
                }
                StyledText {
                    visible: !row.connecting && row.acting.length > 0
                    text: row.acting
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    visible: !row.connecting && !row.current && row.known
                    text: Translation.tr("Saved")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                MaterialSymbol {
                    visible: !row.connecting && row.acting.length === 0 && ((row.network?.isSecure || row.network?.active) ?? false)
                    text: row.network?.active ? "check" : "lock"
                    iconSize: 18
                    color: row.network?.active ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
            }
        }

        StyledIndeterminateProgressBar {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: line.bottom
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            height: 1
            visible: row.connecting || row.acting.length > 0
        }

        // Under the line: the password (a secure network without a profile), the reason the last
        // attempt did not get on, or the portal button (the network you are on asks you to sign in).
        ColumnLayout {
            id: extra
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: line.bottom
            anchors.leftMargin: 40
            anchors.rightMargin: 10
            visible: row.asking || row.portal || row.more || row.failure.length > 0
            spacing: 6

            // What you can do to the network you are on.
            RowLayout {
                visible: row.more
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                spacing: 6
                RippleButton {
                    implicitHeight: 30
                    implicitWidth: disconnectLabel.implicitWidth + 24
                    buttonRadius: Appearance.rounding.small
                    enabled: row.acting.length === 0
                    colBackground: Appearance.colors.colLayer4
                    colBackgroundHover: Appearance.colors.colLayer4Hover
                    colRipple: Appearance.colors.colLayer4Active
                    onClicked: {
                        row.act(Translation.tr("Disconnecting"));
                        Network.disconnectWifiNetwork();
                    }
                    contentItem: StyledText {
                        id: disconnectLabel
                        anchors.centerIn: parent
                        text: Translation.tr("Disconnect")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                    }
                }
                RippleButton {
                    implicitHeight: 30
                    implicitWidth: trustLabel.implicitWidth + 24
                    buttonRadius: Appearance.rounding.small
                    toggled: row.trusted
                    enabled: row.acting.length === 0
                    colBackground: Appearance.colors.colLayer4
                    colBackgroundHover: Appearance.colors.colLayer4Hover
                    colBackgroundToggled: Appearance.colors.colPrimary
                    colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colLayer4Active
                    onClicked: Network.setTrusted(row.network.ssid, !row.trusted)
                    contentItem: StyledText {
                        id: trustLabel
                        anchors.centerIn: parent
                        text: Translation.tr("Trusted")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: row.trusted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                    }
                    StyledToolTip {
                        text: Translation.tr("Home or work: no VPN needed here")
                    }
                }
                RippleButton {
                    implicitHeight: 30
                    implicitWidth: forgetLabel.implicitWidth + 24
                    buttonRadius: Appearance.rounding.small
                    enabled: row.acting.length === 0
                    colBackground: Appearance.colors.colLayer4
                    colBackgroundHover: Appearance.colors.colLayer4Hover
                    colRipple: Appearance.colors.colLayer4Active
                    onClicked: {
                        row.act(Translation.tr("Forgetting"));
                        Network.forgetWifiNetwork(row.network.ssid);
                    }
                    contentItem: StyledText {
                        id: forgetLabel
                        anchors.centerIn: parent
                        text: Translation.tr("Forget")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
            }

            // Enterprise: who you are, then the password. The method line is there for the
            // rare network that is not PEAP.
            ToolbarTextField {
                id: identityField
                visible: row.asking && row.enterprise
                Layout.fillWidth: true
                implicitHeight: 30
                padding: 8
                leftPadding: 10
                rightPadding: 10
                radius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer4
                placeholderText: Translation.tr("Username")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onAccepted: passwordField.forceActiveFocus()
                onVisibleChanged: if (visible) forceActiveFocus()
                Keys.onEscapePressed: row.network.askingPassword = false
            }
            // The last attempt did not get on: said once, gone when you type.
            StyledText {
                Layout.fillWidth: true
                Layout.bottomMargin: row.asking ? 0 : 8
                visible: row.failure.length > 0
                text: row.failure
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colError
            }
            RowLayout {
                visible: row.asking
                Layout.fillWidth: true
                Layout.bottomMargin: row.enterprise ? 0 : 8
                spacing: 6
                ToolbarTextField {
                    id: passwordField
                    Layout.fillWidth: true
                    implicitHeight: 30
                    padding: 8
                    leftPadding: 10
                    rightPadding: 10
                    radius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer4
                    placeholderText: Translation.tr("Password")
                    echoMode: TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData
                    onAccepted: if (text.length > 0) row.submit()
                    onTextChanged: if (row.network) row.network.lastError = ""
                    onVisibleChanged: if (visible && !row.enterprise) forceActiveFocus()
                    Keys.onEscapePressed: row.network.askingPassword = false
                }
                RippleButton {
                    implicitHeight: 30
                    implicitWidth: connectLabel.implicitWidth + 24
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    enabled: passwordField.text.length > 0 && (!row.enterprise || identityField.text.length > 0)
                    onClicked: row.submit()
                    contentItem: StyledText {
                        id: connectLabel
                        anchors.centerIn: parent
                        text: Translation.tr("Connect")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
            RowLayout {
                visible: row.asking && row.enterprise
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                spacing: 6
                StyledText {
                    text: row.eapMethod === "ttls" ? "TTLS · PAP" : "PEAP · MSCHAPv2"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                RippleButton {
                    implicitHeight: 22
                    implicitWidth: changeLabel.implicitWidth + 16
                    buttonRadius: 11
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: row.eapMethod = row.eapMethod === "ttls" ? "peap" : "ttls"
                    contentItem: StyledText {
                        id: changeLabel
                        anchors.centerIn: parent
                        text: Translation.tr("change")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
            }
            RippleButton {
                visible: row.portal
                Layout.bottomMargin: 8
                implicitHeight: 30
                implicitWidth: portalRow.implicitWidth + 24
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer4
                colBackgroundHover: Appearance.colors.colLayer4Hover
                colRipple: Appearance.colors.colLayer4Active
                onClicked: {
                    Network.openPublicWifiPortal();
                    GlobalStates.sidebarRightOpen = false;
                }
                contentItem: Row {
                    id: portalRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "captive_portal"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Open network portal")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                    }
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
