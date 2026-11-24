import QtQuick
import Tacit.Kit as K

Item {
    id: control

    property string text
    property var items: []
    readonly property bool menuOpen: menu.opened
    function dismissMenu() { menu.close(); }
    onVisibleChanged: if (!visible) menu.close()
    signal picked(int index)
    signal activated()

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    K.MenuButton {
        id: button
        anchors.fill: parent
        text: control.text
        previewState: menu.opened ? "hover" : ""
        onActivated: {
            if (control.items.length)
                menu.openAt(button, button.width - menu.implicitWidth, button.height + K.Kit.tokens.space.xs);
            else
                control.activated();
        }
    }

    MailMenu {
        id: menu
        items: control.items
        onPicked: index => control.picked(index)
        onClosed: {
            let focused = button.Window.activeFocusItem;
            while (focused && focused !== menu.contentItem)
                focused = focused.parent;
            if (focused || !button.Window.activeFocusItem)
                button.forceActiveFocus();
        }
    }
}
