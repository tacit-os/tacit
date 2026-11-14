import QtQuick
import QtQuick.Layouts
import Tacit.Kit as K

Item {
    id: rail

    required property var controller
    readonly property var t: K.Kit.tokens
    readonly property int agentDrafts: controller.data.drafts.filter(draft => draft.agent).length
    objectName: "mailboxes"
    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Mailboxes")

    component FolderRow: Item {
        id: folder
        required property string label
        property string account: "All accounts"
        readonly property bool current: rail.controller.ui.folder === label && rail.controller.ui.account === account
        readonly property bool lit: current || pointer.hovered
        readonly property int count: rail.controller.count(label, account)
        readonly property bool showAgentDrafts: label === "Drafts" && account === "All accounts" && rail.agentDrafts > 0

        width: parent.width
        height: rail.t.height.field + (showAgentDrafts ? agentNote.implicitHeight : 0)
        activeFocusOnTab: true
        Accessible.role: Accessible.ListItem
        Accessible.name: count ? qsTr("%1, %2").arg(label).arg(count) : label
        Accessible.description: showAgentDrafts ? agentNote.label : ""
        Accessible.selected: current
        Accessible.onPressAction: pick()

        function pick() { rail.controller.act("folder", {folder: label, account: account}); }

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: selectionTick.x + selectionTick.width / 2
            anchors.rightMargin: -rail.t.space.s
            radius: rail.t.radius.row
            color: rail.t.inkMain
            opacity: press.pressed ? rail.t.wash.pressed
                : folder.current ? (pointer.hovered ? rail.t.wash.currentHover : rail.t.wash.current)
                : pointer.hovered ? rail.t.wash.hover : 0
            Accessible.ignored: true
            Behavior on opacity {
                NumberAnimation { duration: K.Kit.ms(rail.t.motion.hover.ms) }
            }
        }

        Rectangle {
            id: selectionTick
            visible: folder.current
            x: -rail.t.space.m
            y: (rail.t.height.field - height) / 2
            width: 2
            height: rail.t.space.l
            color: rail.t.inkMain
            Accessible.ignored: true
        }

        RowLayout {
            width: parent.width
            height: rail.t.height.field
            spacing: rail.t.space.s

            K.TacitText {
                Layout.fillWidth: true
                text: folder.label
                elide: Text.ElideRight
                ink: folder.lit ? "main" : "faint"
                weight: folder.current ? "strong" : "regular"
            }

            K.TacitText {
                visible: folder.count > 0
                text: folder.count.toLocaleString(Qt.locale(), "f", 0)
                size: "meta"
                ink: folder.current ? "main" : "faint"
                cut: "numbers"
            }
        }

        Row {
            id: agentNote
            readonly property string label: qsTr("%n by your agent", "", rail.agentDrafts)
            visible: folder.showAgentDrafts
            y: rail.t.height.field - rail.t.space.xs
            spacing: rail.t.space.xs
            Accessible.ignored: true

            K.TacitText { text: "├"; size: "meta"; weight: "strong"; color: rail.controller.agentInk }
            K.TacitText { text: agentNote.label; size: "meta"; color: rail.controller.agentInk }
        }

        K.FocusRing { shown: folder.activeFocus && K.Kit.focusVisible }
        HoverHandler { id: pointer; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: press
            onTapped: {
                K.Kit.focusVisible = false;
                folder.forceActiveFocus(Qt.MouseFocusReason);
                folder.pick();
            }
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                K.Kit.focusVisible = true;
                folder.pick();
                event.accepted = true;
            }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 1
        color: Qt.alpha(rail.t.inkMain, rail.t.wash.hover)
        Accessible.ignored: true
    }

    Flickable {
        anchors.fill: parent
        anchors.topMargin: rail.t.space.page
        anchors.bottomMargin: footer.height + 2 * rail.t.space.l
        contentWidth: width
        contentHeight: groups.height + rail.t.space.s
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: groups
            x: rail.t.space.xl
            y: rail.t.space.xs
            width: parent.width - 2 * x

            K.TacitText {
                text: qsTr("All accounts")
                size: "meta"
                ink: "faint"
                bottomPadding: rail.t.space.s
            }

            Repeater {
                model: ["Inbox", "Starred", "Drafts", "Sent", "Archive", "Spam", "Trash"]
                FolderRow {
                    required property string modelData
                    label: modelData
                }
            }

            Repeater {
                model: rail.controller.accounts
                delegate: Column {
                    id: accountSection
                    required property var modelData
                    width: groups.width

                    Item { width: 1; height: rail.t.space.l }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Qt.alpha(rail.t.inkMain, rail.t.wash.hover)
                        Accessible.ignored: true
                    }

                    K.TacitText {
                        text: accountSection.modelData.name
                        size: "meta"
                        weight: "strong"
                        ink: "faint"
                        topPadding: rail.t.space.m
                    }

                    K.TacitText {
                        width: parent.width
                        text: accountSection.modelData.email
                        size: "meta"
                        ink: "faint"
                        elide: Text.ElideRight
                        bottomPadding: rail.t.space.s
                    }

                    Repeater {
                        model: ["Inbox"].concat(accountSection.modelData.name === "Personal" ? ["Family", "Receipts"]
                            : accountSection.modelData.name === "Work" ? ["Clients", "Invoices"] : [])
                        FolderRow {
                            required property string modelData
                            label: modelData
                            account: accountSection.modelData.name
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        id: footer
        anchors.left: parent.left
        anchors.leftMargin: rail.t.space.xl
        anchors.bottom: parent.bottom
        anchors.bottomMargin: rail.t.space.l
        spacing: rail.t.space.xl

        MailAction {
            text: qsTr("Add account")
            onActivated: rail.controller.act("setup")
        }

        MailAction {
            text: qsTr("Settings")
            onActivated: rail.controller.act("settings")
        }
    }
}
