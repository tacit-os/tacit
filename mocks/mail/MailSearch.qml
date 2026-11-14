import QtQuick
import QtQuick.Layouts
import Tacit.Kit as K

FocusScope {
    id: search

    property alias text: input.text
    signal accepted()
    signal dismissed()
    signal down()

    readonly property var t: K.Kit.tokens
    property string folder: "Inbox"
    readonly property string label: qsTr("Search %1").arg(folder)
    implicitHeight: t.height.field
    activeFocusOnTab: true
    Accessible.ignored: true

    K.FocusRing {
        shown: input.activeFocus && K.Kit.focusVisible
    }

    RowLayout {
        anchors.fill: parent
        spacing: search.t.space.s

        K.Symbol {
            text: "search"
            size: search.t.icon.rail
            color: input.activeFocus ? search.t.inkMain : search.t.quiet
            Accessible.ignored: true
        }

        Item {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.fillHeight: true

            K.TacitText {
                id: placeholder
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !input.text
                text: search.label
                ink: "quiet"
                elide: Text.ElideRight
                Accessible.ignored: true
            }

            TextInput {
                id: input
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                focus: true
                clip: true
                selectByMouse: true
                font: placeholder.font
                renderType: placeholder.renderType
                color: search.t.inkMain
                selectionColor: search.t.accent
                selectedTextColor: search.t.inkOnAccent
                Accessible.role: Accessible.EditableText
                Accessible.name: search.label
                onAccepted: search.accepted()

                Keys.onPressed: event => {
                    K.Kit.focusVisible = true;
                    if (event.key === Qt.Key_Escape) {
                        if (input.text.length)
                            input.clear();
                        else {
                            search.focus = false;
                            search.dismissed();
                        }
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        search.down();
                        event.accepted = true;
                    }
                }
            }
        }

        K.IconButton {
            visible: !!input.text
            symbol: "close"
            label: qsTr("Clear search")
            onActivated: {
                input.clear();
                input.forceActiveFocus();
            }
        }
    }

    TapHandler {
        onTapped: {
            K.Kit.focusVisible = false;
            input.forceActiveFocus(Qt.MouseFocusReason);
        }
    }
}
