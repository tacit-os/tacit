import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * VPN, unfolded inside the quick panel like Wi-Fi. Rows: one per NetworkManager VPN
 * profile; a click brings it up (and the one that is up, down). The connected row carries
 * its facts; a click on its actions line offers "On when not trusted" and Forget. Adding one
 * is dropping a WireGuard .conf on the notch; the last row says so when there is none.
 */
Item {
    id: root
    property bool shown: false
    readonly property int rowHeight: 40
    // What nmcli said when the last action failed. The service collects its stderr and nothing
    // read it, so a wrong key or a missing networkmanager-openvpn plugin was indistinguishable
    // from a mis-click.
    property string errorText: ""
    function clearError() {
        root.errorText = "";
        Vpn.lastError = "";
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
    // The error is kept while the section is folded: the pill and the "On when not trusted" rule
    // connect with it folded, and opening it to see why the VPN is off wiped the reason. It goes
    // with the next action, or once the VPN or an import gets through.
    onShownChanged: if (root.shown) {
        refreshLater.restart();
    }
    Connections {
        target: Vpn
        function onBusyChanged() {
            if (!Vpn.busy)
                root.errorText = Vpn.lastError;
        }
        function onConnectedChanged() {
            if (Vpn.connected)
                root.errorText = "";
        }
        function onImported() {
            root.errorText = "";
        }
        function onImportFailed(path, reason) {
            root.errorText = reason.length > 0 ? reason : Translation.tr("Could not import that file");
        }
    }
    Timer {
        id: refreshLater
        interval: 500
        onTriggered: Vpn.refresh()
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
                text: Translation.tr("VPN")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            Item {
                Layout.fillWidth: true
            }
            StyledText {
                visible: Vpn.busy
                text: Vpn.active ? Translation.tr("Disconnecting") : Translation.tr("Connecting")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
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
                visible: Vpn.busy
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            visible: root.errorText.length > 0
            text: root.errorText
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
        }

        Column {
            id: rows
            Layout.fillWidth: true
            Repeater {
                model: ScriptModel {
                    values: Vpn.connections
                    objectProp: "name"   // rows keep their identity across refreshes
                }
                delegate: VpnRow {
                    required property var modelData
                    conn: modelData
                    width: rows.width
                    rowHeight: root.rowHeight
                }
            }
            // The way to add one: no form. A caption, not a row - there is nothing to click
            // here, so it carries neither a row's height nor an icon.
            StyledText {
                x: 10
                width: rows.width - 20
                topPadding: 8
                bottomPadding: 8
                text: Vpn.connections.length === 0
                    ? Translation.tr("Drop a WireGuard .conf file on the notch to add a VPN")
                    : Translation.tr("Drop a WireGuard .conf on the notch to add another")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    component VpnRow: Item {
        id: row
        required property var conn
        property int rowHeight: 40
        property bool more: false
        readonly property bool current: row.conn.active
        readonly property bool auto: Vpn.autoVpn === row.conn.name
        readonly property string kindLabel: row.conn.kind === "wireguard" ? "WireGuard" : "OpenVPN"
        readonly property int lineHeight: row.current ? row.rowHeight + 14 : row.rowHeight
        onCurrentChanged: if (!row.current) row.more = false
        implicitHeight: row.lineHeight + (actions.visible ? actions.implicitHeight : 0)
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
            enabled: !Vpn.busy
            onClicked: {
                root.clearError();
                Vpn.toggle(row.conn.name);
            }
            altAction: () => { row.more = !row.more; }
            altOnHold: true   // a touch screen holds the row, a keyboard presses Menu: no right-click there
            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10
                MaterialSymbol {
                    text: row.current ? "vpn_key" : "vpn_key_off"
                    iconSize: 20
                    color: row.current ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        Layout.fillWidth: true
                        text: row.conn.name
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: row.current
                        text: [row.kindLabel, row.auto ? Translation.tr("on when not trusted") : ""].filter(x => x.length > 0).join(" · ")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                StyledText {
                    visible: !row.current
                    text: row.auto ? Translation.tr("auto") : row.kindLabel
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                MaterialSymbol {
                    visible: row.current
                    text: "check"
                    iconSize: 18
                    color: Appearance.colors.colPrimary
                }
            }
        }

        RowLayout {
            id: actions
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: line.bottom
            anchors.leftMargin: 40
            anchors.rightMargin: 10
            visible: row.more
            spacing: 6
            RippleButton {
                Layout.bottomMargin: 8
                implicitHeight: 30
                implicitWidth: autoLabel.implicitWidth + 24
                buttonRadius: Appearance.rounding.small
                toggled: row.auto
                colBackground: Appearance.colors.colLayer4
                colBackgroundHover: Appearance.colors.colLayer4Hover
                colBackgroundToggled: Appearance.colors.colPrimary
                colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colLayer4Active
                onClicked: Vpn.setAuto(row.conn.name)
                contentItem: StyledText {
                    id: autoLabel
                    anchors.centerIn: parent
                    text: Translation.tr("On when not trusted")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: row.auto ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                }
            }
            RippleButton {
                Layout.bottomMargin: 8
                implicitHeight: 30
                implicitWidth: forgetLabel.implicitWidth + 24
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer4
                colBackgroundHover: Appearance.colors.colLayer4Hover
                colRipple: Appearance.colors.colLayer4Active
                // Forget waits its turn now (Vpn.forget guards on busy), so the button says so
                // instead of being pressed into nothing.
                enabled: !Vpn.busy
                onClicked: {
                    row.more = false;
                    root.clearError();
                    Vpn.forget(row.conn.name);
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
