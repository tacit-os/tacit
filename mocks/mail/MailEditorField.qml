import QtQuick
import Tacit.Kit as K

Item {
    id: field

    required property string label
    property string hint: ""
    property bool error: false
    property alias text: input.text
    readonly property alias input: input
    readonly property var t: K.Kit.tokens
    signal edited()

    implicitHeight: t.height.field
    Accessible.ignored: true

    function focusIn() { input.forceActiveFocus(); }

    K.TacitText {
        id: placeholder
        width: parent.width
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text === "" && input.preeditText === ""
        text: field.hint
        ink: "quiet"
        elide: Text.ElideRight
        Accessible.ignored: true
    }

    TextInput {
        id: input
        anchors.fill: parent
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        selectByMouse: true
        activeFocusOnTab: true
        font: placeholder.font
        renderType: placeholder.renderType
        color: field.t.inkMain
        selectionColor: Qt.alpha(field.t.accent, 0.4)
        selectedTextColor: field.t.inkMain
        cursorDelegate: Rectangle {
            width: 1.5
            color: field.error ? field.t.risk : field.t.accent
            visible: input.cursorVisible
        }
        Accessible.role: Accessible.EditableText
        Accessible.name: field.label
        Accessible.description: field.error ? qsTr("Invalid email address") : ""
        onTextEdited: field.edited()
        Keys.onPressed: K.Kit.focusVisible = true
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        visible: field.error || input.activeFocus
        color: field.error ? field.t.risk : field.t.accent
        Accessible.ignored: true
    }
}
