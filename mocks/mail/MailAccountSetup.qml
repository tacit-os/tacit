import QtQuick
import QtQuick.Layouts
import Tacit.Kit as K

Item {
    id: setup
    required property var controller
    readonly property var t: K.Kit.tokens
    Flickable {
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: setupContent.y + setupContent.implicitHeight + setup.t.space.page
        ColumnLayout {
            id: setupContent
            x: (parent.width - width) / 2
            y: setup.t.space.page
            width: Math.min(parent.width - setup.t.space.page * 2, setup.t.width.panel + setup.t.space.page * 4)
            spacing: setup.t.space.l
            MailAction {
                text: qsTr("Back to Mail")
                onActivated: setup.controller.act("back")
            }
            MailHeadline {
                Layout.fillWidth: true
                text: qsTr("Add your mail")
            }
            K.TacitText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                ink: "sec"
                text: qsTr("Every account in one place. Choose your provider to continue in the system sign-in window.")
            }
            Column {
                Layout.fillWidth: true
                Repeater {
                    model: ["Google", "Microsoft", "iCloud", "Fastmail", "Another provider"]
                    delegate: K.ListRow {
                        required property string modelData
                        objectName: "provider-" + modelData
                        width: parent.width
                        name: modelData
                        aside: modelData === "Another provider" ? qsTr("IMAP and SMTP") : ""
                        facts: []
                        onClicked: setup.controller.act("provider", {
                            name: modelData
                        })
                        onActivated: setup.controller.act("provider", {
                            name: modelData
                        })
                        accessory: [
                            K.Symbol {
                                text: "chevron_right"
                                size: K.Kit.tokens.icon.rail
                            }
                        ]
                    }
                }
            }
        }
    }
    K.TacitText {
        visible: setup.controller.ui.provider !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: setup.t.space.xl
        text: qsTr("Waiting for %1 sign-in in the system…").arg(setup.controller.ui.provider)
        ink: "meta"
    }
}
